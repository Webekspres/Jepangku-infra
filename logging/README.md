# 🌲 Logging Stack — Jepangku Infra

Infrastruktur logging terpusat menggunakan **Pino → stdout → Promtail → Loki → Grafana**.

Melayani semua service: **jepangku-news**, **jepangku-core**, **jepangkuLMS**.

## Arsitektur

```
                          ┌──────────────────┐
                          │  Grafana          │
                          │  http://VPS:3002  │  ← SATU Grafana untuk semua
                          └────────┬─────────┘
                                   │ query
                          ┌────────▼─────────┐
                          │  Loki             │
                          │  (database log)   │  ← SATU Loki untuk semua
                          └────────┬─────────┘
                                   │ push
                          ┌────────▼─────────┐
                          │  Promtail         │
                          │  (collector)      │  ← SATU Promtail, baca semua container
                          └────────┬─────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        ▼                          ▼                          ▼
┌───────────────┐        ┌───────────────┐        ┌──────────────────┐
│ jepangku-news │        │ jepangku-core  │        │ jepangkuLMS      │
│ Pino → stdout │        │ Pino → stdout  │        │ Pino → stdout    │
└───────────────┘        └───────────────┘        └──────────────────┘
```

## Cara Jalankan

```bash
# Clone repo
git clone https://github.com/jepangku/jepangku-infra
cd jepangku-infra/logging

# Jalankan stack logging
docker compose -f docker-compose.logging.yml up -d

# Cek status
docker compose -f docker-compose.logging.yml ps
```

## Akses Grafana

```
URL:      http://[VPS_IP]:3002
Username: admin
Password: admin  ← GANTI password setelah login pertama!
```

Datasource **Loki** sudah terdaftar otomatis (provisioning).

## Query Log di Grafana

| Container | Label | Contoh Query |
|---|---|---|
| jepangku-news | `{container="jepangku-news"}` | Semua log aplikasi |
| jepangku-core | `{container="jepangku-core"}` | Log Core API |
| jepangkuLMS | `{container="jepangkuLMS"}` | Log LMS |
| PostgreSQL | `{image="postgres:*"}` | Log database |
| Semua | `{}` | Semua container di VPS |

Filter level: `{container="jepangku-news"} |= "error"`
Filter JSON: `{container="jepangku-news"} | json | level="error"`

## Konfigurasi Penting

### Retensi Log (7 hari)

Di `logging/loki/loki-config.yml`:

```yaml
limits_config:
  retention_period: 168h  # 7 hari
```

### Grafana Password

Ubah password di `logging/docker-compose.logging.yml`:

```yaml
environment:
  - GF_SECURITY_ADMIN_PASSWORD=password_baru_yang_kuat
```

## Grafana Dashboard (Phase 6.1)

Dashboard **Jepangku — Logging Dashboard** auto-load via provisioning:

| Panel | Tipe | Query |
|---|---|---|
| 🔥 Error Rate per Module | Bar chart | `count_over_time` by `module` |
| ⏱ Request Duration P50/P95/P99 | Time series | `quantile_over_time` by `path` |
| 📊 HTTP Status Distribution | Bar chart (stacked) | 2xx vs 4xx vs 5xx per menit |
| 🐌 Top 10 Slowest Endpoints | Bar chart | `topk(10, quantile_over_time...)` |
| 📈 Error Trend per Jam | Time series | Error count over time by module |

**Variable:**
- `container` — filter by container name (default: jepangku-news)
- `module` — filter by log module (auth, article, core.client, etc.)

## Alert Rules (Phase 6.2)

| Alert | Condition | Severity |
|---|---|---|
| `JepangkuNews_HighErrorRate` | >5 error/menit selama 2 menit | 🔴 critical |
| `JepangkuNews_HighLatencyP95` | P95 >5 detik selama 5 menit | 🟡 warning |
| `JepangkuNews_CrashLoop` | >3 error/fatal dalam 1 menit | 🔴 critical |
| `JepangkuNews_ErrorRateWarning` | >10 error dalam 5 menit | 🟡 warning |
| `JepangkuNews_High5xxRate` | 5xx rate >10% dalam 5 menit | 🟡 warning |
| `JepangkuNews_CoreApiDegraded` | >5 core.client warn dalam 5 menit | 🟡 warning |

**Setup notifikasi:**
1. Dashboard Grafana → **Alerting → Contact points** → tambah Telegram/Email/Slack
2. Dashboard Grafana → **Alerting → Notification policies** → arahkan ke contact point

## Log Retention & Backup (Phase 6.3)

Retensi default: **7 hari (168h)** — diatur di `loki/loki-config.yml`.

### Maintenance Script

```bash
# Cek status disk
./scripts/maintain-logs.sh --status

# Pruning log expired
./scripts/maintain-logs.sh --prune

# Backup data Loki
./scripts/maintain-logs.sh --backup

# Semua langkah
./scripts/maintain-logs.sh --all
```

Backup disimpan di `./backups/` — otomatis hapus backup >30 hari.

## Troubleshooting

| Masalah | Cek |
|---|---|
| Tidak ada log di Grafana | `docker logs jepangku-promtail` — cek error koneksi ke Loki |
| Grafana error 502 | `docker logs jepangku-grafana` — cek plugin/datasource |
| Dashboard tidak muncul | Cek `provisioning/dashboards/` — file YAML & JSON harus ada |
| Alert tidak jalan | Cek `loki/rules/fake/` — pastikan YAML valid. Cek `ruler` config di `loki-config.yml` |
| Disk penuh | `docker system df` — pruning: `docker system prune -f` |
| Loki crash | Cek permission folder `loki-data` — `chown 10001:10001 loki-data` |
| Backup gagal | Pastikan `docker` running dan volume `jepangku-infra_loki-data` ada |

## Resource

| Service | RAM | Disk |
|---|---|---|
| Promtail | ~15 MB | ~100 MB (config) |
| Loki | ~50-100 MB | ~500 MB - 2 GB (tergantung volume log) |
| Grafana | ~50 MB | ~200 MB (dashboard + plugin) |
| **Total** | **~150 MB** | **~1-3 GB** (tanpa backup) |
