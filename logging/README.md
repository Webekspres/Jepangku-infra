# 🌲 Logging Stack — Jepangku Infra

Infrastruktur logging terpusat: **Pino (app) → stdout → Promtail → Loki → Grafana**.

| Service | Label `service` | Container Docker (VPS) |
| :--- | :--- | :--- |
| News Portal | `jepangku-news` | `jepangku_portal` |
| Core API | `jepangku-core` | `jepangku_core` |
| LMS | `jepangku-lms` | `jepangku_lms` |

---

## Arsitektur request (production VPS)

```
Cloudflare
    │
    ▼
Nginx (host)                    ← log: /var/log/nginx/  (bukan container)
    │  proxy_pass 127.0.0.1:3001 / 3002 / 8080
    ▼
Docker: portal / lms / core / db / redis
```

Bukan Traefik/Caddy, bukan Nginx di dalam container. Saat Cloudflare 502, periksa **Nginx host** + **Docker lifecycle**, bukan hanya log aplikasi.

## Arsitektur logging

```
 Nginx access/error ──┐
 docker-events.log  ──┼──► Promtail ──► Loki ──► Grafana (:3040)
 origin-uptime.log  ──┤
 app stdout (Pino)  ──┘
                              ▲
 Prometheus / node / cAdvisor ┘  (opsional, docker-compose.metrics.yml)
```

Runbook investigasi: [`INCIDENT_QUERIES.md`](./INCIDENT_QUERIES.md)

---

## Setup di VPS

> **Port 3002** sudah dipakai `jepangku_lms`. Grafana logging memakai **3040**.

```bash
# Clone (sekali)
git clone https://github.com/Webekspres/Jepangku-infra.git ~/Jepangku-infra
cd ~/Jepangku-infra/logging
cp .env.example .env   # edit GRAFANA_ADMIN_PASSWORD

# Jalankan logging
docker compose -f docker-compose.logging.yml up -d

# Observability penuh (Nginx upstream log + uptime probe + docker-events)
bash ~/Jepangku-infra/deploy/scripts/vps-install-observability.sh

# + metrics historis CPU/RAM/disk/container (~450MB RAM ekstra)
bash ~/Jepangku-infra/deploy/scripts/vps-install-observability.sh --with-metrics
```

Atau setup logging saja:

```bash
bash ~/Jepangku-infra/deploy/scripts/vps-setup-logging.sh
```

**Deploy otomatis:** push ke branch `main` memicu GitHub Action `Deploy Logging Stack to VPS` (butuh secret SSH di repo).

---

## Akses Grafana

Loki dan Grafana hanya bind ke **localhost** di VPS — tidak diekspos publik.

### 1. SSH tunnel (dari laptop)

```bash
ssh -L 3040:127.0.0.1:3040 103.25.223.16
```

Buka browser: **http://localhost:3040**

### 2. Login

| Field | Nilai |
| :--- | :--- |
| Username | `admin` |
| Password | Lihat di server: `cat ~/jepangku-grafana-password.txt` |

Password diset saat bootstrap pertama (`vps-setup-logging.sh`) dan disimpan di `logging/.env` (tidak di-commit).

---

## Panduan penggunaan Grafana

### Dashboard utama

**Dashboards** → **Jepangku — Logging Dashboard**

| Panel | Fungsi |
| :--- | :--- |
| 🔥 Error Rate per Module | Error per menit, per `module` |
| ⏱ Request Duration P50/P95/P99 | Latency per `path` |
| 📊 HTTP Status Distribution | 2xx / 4xx / 5xx per menit |
| 🐌 Top 10 Slowest Endpoints | P95 endpoint terlambat |
| 📈 Error Trend per Jam | Tren error per modul |

**Variabel dashboard (dropdown atas):**

| Variabel | Default | Fungsi |
| :--- | :--- | :--- |
| `service` | `jepangku-news` | Filter aplikasi (`jepangku-news`, `jepangku-core`, `jepangku-lms`) |
| `module` | All | Filter modul log (`http`, `auth`, `core.client`, dll.) |

### Explore — query manual (LogQL)

**Explore** → pilih datasource **Loki**.

#### Query dasar

```logql
# Semua log satu service
{service="jepangku-news"}

# Parse JSON + filter level
{service="jepangku-news"} | json | level="error"

# Filter modul
{service="jepangku-news"} | json | module="core.client"

# Filter HTTP 5xx
{service="jepangku-news"} | json | status >= 500

# Satu endpoint
{service="jepangku-news"} | json | path="/api/articles"

# Korelasi request (reqId = x-request-id)
{service="jepangku-news"} | json | reqId="UUID-DI-SINI"
```

#### Filter by container (alternatif)

Jika field `service` belum ada (build lama), pakai label container:

```logql
{container="jepangku_portal"} | json | level="error"
```

| Aplikasi | Container |
| :--- | :--- |
| News | `jepangku_portal` |
| Core | `jepangku_core` |
| LMS | `jepangku_lms` |
| Staging News | `jepangku_staging_portal` |

#### Tips Explore

- **Time range** (kanan atas): sesuaikan dengan waktu insiden
- **Live** (tombol): tail log real-time
- Klik baris log → **Show context** untuk lihat log sebelum/sesudah
- **Add to dashboard** untuk simpan panel baru

### Alerting

Rules didefinisikan di `loki/rules/jepangku/jepangku-alerts.yaml` (Loki Ruler).

| Alert | Kondisi | Severity |
| :--- | :--- | :--- |
| `JepangkuNews_HighErrorRate` | >5 error/menit, 2 menit | critical |
| `JepangkuNews_HighLatencyP95` | P95 >5 detik, 5 menit | warning |
| `JepangkuNews_CrashLoop` | >3 error/fatal/menit | critical |
| `JepangkuNews_ErrorRateWarning` | >10 error/5 menit | warning |
| `JepangkuNews_High5xxRate` | 5xx >10%/5 menit | warning |
| `JepangkuNews_CoreApiDegraded` | >5 core.client warn/5 menit | warning |
| `JepangkuOrigin_Down` | probe localhost DOWN ≥2 menit | critical |
| `JepangkuContainer_LifecycleCritical` | stop/die/oom/kill pada prod | critical |
| `JepangkuNginx_UpstreamFailure` | >5 upstream error Nginx /2 menit | critical |

**Setup notifikasi (manual, sekali):**

1. Grafana → **Alerting** → **Contact points** → tambah Telegram / Slack / Email
2. **Notification policies** → arahkan alert ke contact point
3. Uji dengan tombol **Test** di contact point

---

## Verifikasi & maintenance

```bash
# Status container
cd ~/Jepangku-infra/logging
docker compose -f docker-compose.logging.yml ps

# Verifikasi label & error promtail (read-only)
bash ~/Jepangku-infra/deploy/scripts/vps-verify-logging.sh

# Maintenance log (retensi, backup)
./scripts/maintain-logs.sh --status
./scripts/maintain-logs.sh --all
```

Retensi default: **7 hari** (`loki/loki-config.yml` → `retention_period: 168h`).

---

## Konfigurasi

### Environment (`logging/.env`)

```env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<password-kuat>
GRAFANA_PORT=3040
```

### Port

| Service | Port host (VPS) | Akses |
| :--- | :--- | :--- |
| Grafana | `127.0.0.1:3040` | SSH tunnel |
| Loki | `127.0.0.1:3100` | Internal / tunnel |
| Promtail | internal | — |

---

## Troubleshooting

| Masalah | Langkah |
| :--- | :--- |
| Grafana tidak bisa dibuka | Pastikan SSH tunnel aktif (`-L 3040:127.0.0.1:3040`) |
| Dashboard kosong | Cek variabel `service`; pastikan app emit field `service` di JSON log |
| Tidak ada label `service` | Redeploy app dengan Pino `base: { service: '...' }` |
| Promtail error `timestamp too old` | Restart promtail; pastikan tidak pakai job `docker_files` lama |
| Datasource error | Cek UID = `loki` di `grafana/provisioning/datasources/` |
| Label `container` kosong | Cek regex relabel promtail (`"/?(.*)"`) |
| Disk penuh | `docker system df`; jalankan `maintain-logs.sh --prune` |

```bash
# Log komponen
docker logs jepangku-promtail --tail 30
docker logs jepangku-loki --tail 20
docker logs jepangku-grafana --tail 20
```

---

## Resource

| Service | RAM | Disk |
| :--- | :--- | :--- |
| Promtail | ~15 MB | ~100 MB |
| Loki | ~50–100 MB | ~500 MB – 2 GB |
| Grafana | ~50 MB | ~200 MB |
| **Total** | **~150 MB** | **~1–3 GB** |

---

## Panduan per aplikasi

- **jepangku-news** (cek error): [`jepangku-news/docs/runbooks/checking-errors-grafana.md`](../../jepangku-news/docs/runbooks/checking-errors-grafana.md)
