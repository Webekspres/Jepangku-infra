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

## Troubleshooting

| Masalah | Cek |
|---|---|
| Tidak ada log di Grafana | `docker logs jepangku-promtail` — cek error koneksi ke Loki |
| Grafana error 502 | `docker logs jepangku-grafana` — cek plugin/datasource |
| Disk penuh | `docker system df` — pruning: `docker system prune -f` |
| Loki crash | Cek permission folder `loki-data` — `chown 10001:10001 loki-data` |

## Resource

| Service | RAM | Disk |
|---|---|---|
| Promtail | ~15 MB | ~100 MB (config) |
| Loki | ~50-100 MB | ~500 MB - 2 GB (tergantung volume log) |
| Grafana | ~50 MB | ~200 MB (dashboard + plugin) |
| **Total** | **~150 MB** | **~1-3 GB** |
