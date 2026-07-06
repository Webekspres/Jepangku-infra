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

- [`logging/README.md`](./logging/README.md) — Setup Grafana + Loki + Promtail
