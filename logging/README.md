# 🌲 Logging & Observability — Jepangku Infra

Stack terpusat di VPS: **log aplikasi + Nginx + lifecycle Docker + uptime origin** → Promtail → Loki → Grafana. Opsional: Prometheus untuk CPU/RAM/disk historis.

| Service | Label `service` | Container Docker (VPS) |
| :--- | :--- | :--- |
| News Portal | `jepangku-news` | `jepangku_portal` |
| Core API | `jepangku-core` | `jepangku_core` |
| LMS | `jepangku-lms` | `jepangku_lms` |
| Origin probe | `origin-uptime` | (host cron) |
| Docker lifecycle | `docker-events` | `jepangku-docker-events` |
| Nginx | `nginx` | (host) |

Panduan investigasi cepat: [`INCIDENT_QUERIES.md`](./INCIDENT_QUERIES.md)

---

## Apa yang baru (pembaruan observability)

Sebelumnya Grafana hampir hanya melihat **log stdout aplikasi** (Pino). Jika container dimatikan atau Nginx gagal ke upstream, bukti sering hilang atau sulit dibuktikan.

Sekarang ada empat lapisan bukti tambahan:

| Pembaruan | Fungsi | Bukti yang didapat |
| :--- | :--- | :--- |
| **Nginx upstream access log** | Field `us=`, `urt=`, `uct=` di access log | Bedakan 502: connection refused vs timeout vs app 5xx |
| **Docker events logger** | Catat `start` / `stop` / `die` / `oom` / `kill` | Kapan container prod dihentikan, exit code |
| **Origin uptime probe** | Curl localhost `:3001` / `:3002` / `:8080` tiap menit | Window DOWN→UP per target (setara uptime monitor ringan) |
| **Prometheus + node-exporter + cAdvisor** (opsional) | Metrics host & container | CPU/RAM/disk tepat di waktu insiden |

Alert baru di Loki:

- `JepangkuOrigin_Down` — probe localhost DOWN ≥2 menit  
- `JepangkuContainer_LifecycleCritical` — stop/die/oom/kill pada stack prod  
- `JepangkuNginx_UpstreamFailure` — banyak error upstream Nginx  

---

## Arsitektur request (production VPS)

```
Cloudflare
    │
    ▼
Nginx (host)                    ← /var/log/nginx/
    │  proxy_pass 127.0.0.1:3001 / 3002 / 8080
    ▼
Docker: portal / lms / core / db / redis
```

Saat Cloudflare menampilkan 502, periksa **Nginx host** + **Docker lifecycle** + **origin probe**, bukan hanya log aplikasi.

## Arsitektur logging

```
 Nginx access/error ──┐
 docker-events.log  ──┼──► Promtail ──► Loki ──► Grafana (:3040)
 origin-uptime.log  ──┤
 app stdout (Pino)  ──┘
                              ▲
 Prometheus / node / cAdvisor ┘  (opsional)
```

| Sumber | Lokasi di VPS |
| :--- | :--- |
| Nginx access/error | `/var/log/nginx/` |
| Docker events | `/var/log/jepangku/docker-events.log` |
| Origin uptime | `/var/log/jepangku/origin-uptime.log` |
| App logs | stdout container → Docker → Promtail |

---

## Setup di VPS

> **Port 3002** = `jepangku_lms`. Grafana memakai **3040**.

```bash
cd ~/Jepangku-infra/logging
cp -n .env.example .env   # edit GRAFANA_ADMIN_PASSWORD jika belum ada

# Logging stack (Loki + Promtail + Grafana + docker-events)
docker compose -f docker-compose.logging.yml up -d

# Aktifkan Nginx upstream log + origin probe (+ recreate stack)
bash ~/Jepangku-infra/deploy/scripts/vps-install-observability.sh

# Opsional: metrics historis (~450MB RAM ekstra)
bash ~/Jepangku-infra/deploy/scripts/vps-install-observability.sh --with-metrics
```

Bootstrap pertama kali saja: `bash ~/Jepangku-infra/deploy/scripts/vps-setup-logging.sh`

Deploy otomatis: push ke `main` (perubahan di `logging/**` atau `deploy/**`) memicu workflow **Deploy Logging Stack to VPS**.

---

## Akses Grafana

Grafana & Loki hanya bind **localhost** — akses via SSH tunnel.

```bash
# Dari laptop
ssh -L 3040:127.0.0.1:3040 vps-jepangku
# atau: ssh -L 3040:127.0.0.1:3040 -p 8288 developer@103.25.223.16
```

Buka **http://localhost:3040**

| Field | Nilai |
| :--- | :--- |
| Username | `admin` |
| Password | `grep GRAFANA_ADMIN_PASSWORD ~/Jepangku-infra/logging/.env` |

Jika metrics aktif, tunnel tambahan untuk Prometheus UI:

```bash
ssh -L 3040:127.0.0.1:3040 -L 9090:127.0.0.1:9090 vps-jepangku
```

---

## Cara pakai Grafana

### 1. Dashboard aplikasi (lama)

**Dashboards** → folder **Jepangku** → **Jepangku — Logging Dashboard**

| Panel | Fungsi |
| :--- | :--- |
| Error Rate per Module | Error/menit per `module` |
| Request Duration P50/P95/P99 | Latency per `path` |
| HTTP Status Distribution | 2xx / 4xx / 5xx |
| Top 10 Slowest Endpoints | Endpoint paling lambat |
| Error Trend per Jam | Tren error |

Dropdown atas: `service` (`jepangku-news` / `jepangku-core` / `jepangku-lms`), `module`.

### 2. Explore — datasource Loki (inti investigasi)

**Explore** → datasource **Loki** → set **time range** ke jendela insiden.

#### A) Apakah origin hidup?

```logql
{service="origin-uptime"} | json
```

```logql
{service="origin-uptime"} | json | state="DOWN"
```

```logql
{service="origin-uptime"} | json | event="transition"
```

Field penting: `target` (`portal` / `lms` / `core`), `state`, `event` (`transition` / `still_down` / `heartbeat`), `http`, `latencyMs`.

#### B) Apakah container di-stop / OOM?

```logql
{service="docker-events"} | json
```

```logql
{service="docker-events"} | json | Action=~"stop|die|oom|kill"
```

```logql
{service="docker-events"} |~ "jepangku_(portal|lms|core|db|redis)"
```

#### C) Apa kata Nginx tentang upstream?

```logql
{job="nginx", log_type="error"} |= "connect() failed" or "upstream timed out"
```

```logql
{job="nginx", log_type="access"} |~ `us="502"|us="504"|us="-"`
```

Field access (setelah format `jepangku_upstream` aktif):

| Field | Arti |
| :--- | :--- |
| `us=` | Upstream HTTP status (`502`, `-` = tidak ada respons) |
| `urt=` | Upstream response time |
| `uct=` | Upstream connect time |
| `rt=` | Total request time |
| `host=` | Virtual host (`kursus.jepangku.com`, dll.) |

#### D) Log aplikasi (Pino)

```logql
{service="jepangku-news"} | json | level="error"
{service="jepangku-lms"} | json | status >= 500
{container="jepangku_portal"} | json | level="error"
```

### 3. Explore — datasource Prometheus (jika `--with-metrics`)

**Explore** → **Prometheus**

```promql
# CPU host (%)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# RAM tersedia (rasio)
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Memory container Jepangku
container_memory_usage_bytes{name=~"jepangku_.*"}
```

### 4. Alur 5 menit saat 502 / downtime

1. `{service="origin-uptime"} | json | state="DOWN"` → target mana, sejak kapan?  
2. `{service="docker-events"} | json | Action=~"stop|die|oom"` → ada lifecycle event sebelumnya?  
3. `{job="nginx",log_type="error"}` → `Connection refused` vs `upstream timed out`?  
4. (Opsional) Prometheus → spike CPU/RAM di window yang sama?  
5. Log app `{service="jepangku-…"} | json | level="error"` jika origin masih UP tapi error bisnis.

Detail query: [`INCIDENT_QUERIES.md`](./INCIDENT_QUERIES.md)

### 5. Tips Explore

- **Time range** (kanan atas) = jendela insiden  
- **Live** = tail real-time  
- Klik baris → **Show context**  
- Simpan query bagus lewat **Add to dashboard** / bookmark  

---

## Alerting

Rules: `loki/rules/jepangku/jepangku-alerts.yaml`

| Alert | Kondisi | Severity |
| :--- | :--- | :--- |
| `JepangkuNews_HighErrorRate` | >5 error/menit, 2 menit | critical |
| `JepangkuNews_HighLatencyP95` | P95 >5 detik, 5 menit | warning |
| `JepangkuNews_CrashLoop` | >3 error/fatal/menit | critical |
| `JepangkuNews_ErrorRateWarning` | >10 error/5 menit | warning |
| `JepangkuNews_High5xxRate` | 5xx >10%/5 menit | warning |
| `JepangkuNews_CoreApiDegraded` | >5 core.client warn/5 menit | warning |
| `JepangkuOrigin_Down` | probe localhost DOWN ≥2 menit | critical |
| `JepangkuContainer_LifecycleCritical` | stop/die/oom/kill prod | critical |
| `JepangkuNginx_UpstreamFailure` | >5 upstream error Nginx /2 menit | critical |
| `JepangkuInfra_DiskSpace` | Loki out of disk | critical |

**Notifikasi (sekali):** Grafana → Alerting → Contact points (Telegram/Slack/Email) → Notification policies → Test.

---

## Verifikasi & maintenance

```bash
cd ~/Jepangku-infra/logging
docker compose -f docker-compose.logging.yml ps

# Origin probe & docker-events
tail -n 5 /var/log/jepangku/origin-uptime.log
tail -n 5 /var/log/jepangku/docker-events.log

bash ~/Jepangku-infra/deploy/scripts/vps-verify-logging.sh
./scripts/maintain-logs.sh --status
```

Retensi Loki default: **7 hari**.

---

## Konfigurasi & port

```env
# logging/.env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<password-kuat>
GRAFANA_PORT=3040
```

| Service | Port host | Akses |
| :--- | :--- | :--- |
| Grafana | `127.0.0.1:3040` | SSH tunnel |
| Loki | `127.0.0.1:3100` | Internal |
| Prometheus (opsional) | `127.0.0.1:9090` | SSH tunnel |
| Promtail / cAdvisor / node-exporter | internal | — |

File terkait:

| Path | Isi |
| :--- | :--- |
| `nginx/jepangku-upstream-log.conf` | Format access log upstream |
| `scripts/origin-uptime-probe.sh` | Probe localhost tiap menit |
| `scripts/docker-events-logger.sh` | Stream Docker lifecycle |
| `docker-compose.metrics.yml` | Prometheus stack opsional |
| `deploy/scripts/vps-install-observability.sh` | Install/aktifkan semua di atas |

---

## Troubleshooting

| Masalah | Langkah |
| :--- | :--- |
| Grafana tidak terbuka | Pastikan tunnel `-L 3040:127.0.0.1:3040` aktif |
| Tidak ada `origin-uptime` di Loki | Jalankan `vps-install-observability.sh`; cek cron `/etc/cron.d/jepangku-observability` |
| Tidak ada `docker-events` | `docker ps \| grep docker-events`; cek `/var/log/jepangku/docker-events.log` |
| Access log tanpa `us=` / `urt=` | Snippet Nginx belum aktif — jalankan install script, `nginx -t && reload` |
| Dashboard app kosong | Cek dropdown `service`; pastikan app emit JSON `service` |
| Promtail `timestamp too old` | Restart promtail |
| Disk penuh | `docker system df`; `maintain-logs.sh --prune` |

```bash
docker logs jepangku-promtail --tail 30
docker logs jepangku-loki --tail 20
docker logs jepangku-grafana --tail 20
docker logs jepangku-docker-events --tail 20
```

---

## Resource (perkiraan)

| Komponen | RAM |
| :--- | :--- |
| Loki + Promtail + Grafana | ~150 MB |
| docker-events | ~32 MB |
| + Prometheus + node-exporter + cAdvisor | ~450 MB ekstra |

---

## Referensi

- Runbook query: [`INCIDENT_QUERIES.md`](./INCIDENT_QUERIES.md)  
- App news: `jepangku-news/docs/runbooks/checking-errors-grafana.md`
