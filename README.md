# 🏗️ Jepangku Infra

Infrastruktur observability bersama untuk ekosistem Jepangku di VPS: **logging (Loki/Grafana)** + **Nginx upstream** + **Docker lifecycle** + **uptime origin**, opsional **Prometheus**.

## Struktur

```
jepangku-infra/
├── logging/                              ← Stack observability terpusat
│   ├── docker-compose.logging.yml        # Loki + Promtail + Grafana + docker-events
│   ├── docker-compose.metrics.yml        # Opsional: Prometheus + node-exporter + cAdvisor
│   ├── nginx/                            # Format access log upstream (us=/urt=/uct=)
│   ├── scripts/                          # origin-uptime-probe, docker-events-logger
│   ├── loki/                             # Config + alert rules
│   ├── promtail/                         # Collector (Docker + Nginx + host logs)
│   ├── grafana/                          # Datasource Loki (+ Prometheus)
│   ├── prometheus/                       # Scrape config (jika metrics aktif)
│   ├── INCIDENT_QUERIES.md               # Runbook query saat 502 / downtime
│   └── README.md                         # Setup & cara pakai Grafana
├── deploy/scripts/
│   ├── vps-setup-logging.sh              # Bootstrap logging pertama kali
│   ├── vps-install-observability.sh      # Nginx upstream + probe + recreate stack
│   └── vps-verify-logging.sh             # Verifikasi Promtail/Loki
└── .github/workflows/deploy-logging.yml  # Deploy otomatis ke VPS (push main)
```

## Arsitektur production

```
Cloudflare → Nginx (host) → Docker (portal / lms / core / db / redis)
                 │
                 ▼
         Promtail → Loki → Grafana (:3040)
```

## Service yang dilayani

| Service | Repo / sumber | Sinyal di Grafana |
| :--- | :--- | :--- |
| News Portal | `jepangku-news` | Log Pino (`jepangku-news`) |
| Core API | `jepangku-core` | Log Pino (`jepangku-core`) |
| LMS | `jepangkuLMS` | Log Pino (`jepangku-lms`) |
| Nginx | host VPS | Access/error + upstream status |
| Origin uptime | cron host | UP/DOWN portal·lms·core |
| Docker events | `jepangku-docker-events` | stop / die / oom / start |

## Setup singkat (VPS)

```bash
cd ~/Jepangku-infra

# Pertama kali
bash deploy/scripts/vps-setup-logging.sh

# Aktifkan observability penuh (Nginx upstream + probe + docker-events)
bash deploy/scripts/vps-install-observability.sh

# Opsional: metrics CPU/RAM/disk (~450MB RAM ekstra)
bash deploy/scripts/vps-install-observability.sh --with-metrics
```

Deploy otomatis: merge/push ke `main` (perubahan `logging/**` atau `deploy/**`) → workflow **Deploy Logging Stack to VPS**.

## Akses Grafana

```bash
ssh -L 3040:127.0.0.1:3040 vps-jepangku
# http://localhost:3040  (user: admin — password di logging/.env)
```

## Dokumentasi

| Dokumen | Isi |
| :--- | :--- |
| [`logging/README.md`](./logging/README.md) | Pembaruan observability, setup, cara pakai Grafana/LogQL/PromQL, alert |
| [`logging/INCIDENT_QUERIES.md`](./logging/INCIDENT_QUERIES.md) | Checklist 5 menit + query siap pakai saat 502/downtime |
| [`jepangku-news` runbook](../jepangku-news/docs/runbooks/checking-errors-grafana.md) | Cek error khusus portal berita |

### Query cepat (Explore → Loki)

```logql
{service="origin-uptime"} | json | state="DOWN"
{service="docker-events"} | json | Action=~"stop|die|oom"
{job="nginx", log_type="error"} |= "connect() failed" or "upstream timed out"
{service="jepangku-news"} | json | level="error"
```
