# 🏗️ Jepangku Infra

Infrastruktur logging bersama untuk ekosistem Jepangku.

## Struktur

```
jepangku-infra/
├── logging/                   ← Stack logging terpusat
│   ├── docker-compose.logging.yml  (Promtail + Loki + Grafana)
│   ├── loki/                       (konfigurasi penyimpanan)
│   ├── promtail/                   (konfigurasi collector)
│   ├── grafana/                    (provisioning datasource)
│   └── README.md
└── README.md
```

## Service yang Dilayani

| Service | Repo | Log Source |
|---|---|---|
| News Portal | `jepangku-news` | Next.js + Pino |
| Core API | `jepangku-core` | API + Pino |
| LMS | `jepangkuLMS` | Next.js + Pino |

## Cara Setup

Lihat dokumentasi masing-masing subfolder:

- [`logging/README.md`](./logging/README.md) — Setup Grafana + Loki + Promtail, **panduan penggunaan Grafana & LogQL**
- Deploy otomatis ke VPS: GitHub Action `.github/workflows/deploy-logging.yml` (push ke `main`)

## Akses cepat Grafana (production)

```bash
ssh -L 3040:127.0.0.1:3040 103.25.223.16
# http://localhost:3040  (user: admin)
```

Panduan cek error per aplikasi: [`jepangku-news/docs/runbooks/checking-errors-grafana.md`](../jepangku-news/docs/runbooks/checking-errors-grafana.md)
