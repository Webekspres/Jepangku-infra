# Incident investigation — Jepangku VPS

## Arsitektur (yang harus dicek dulu)

```
Cloudflare
    │
    ▼
Nginx (host)          ← /etc/nginx , log: /var/log/nginx/
    │  proxy_pass 127.0.0.1:3001|3002|8080
    ▼
Docker containers     ← jepangku_portal / jepangku_lms / jepangku_core / db / redis
```

Bukan Nginx-in-container, bukan Traefik/Caddy. Log yang relevan: **host Nginx** + **Docker events** + **origin probe** + (opsional) **Prometheus**.

---

## Sumber bukti (setelah `vps-install-observability.sh`)

| Sumber | File / sistem | Menjawab |
| :--- | :--- | :--- |
| Nginx upstream access | `/var/log/nginx/access.log` (`us=`, `urt=`, `uct=`) | 502 dari refused / timeout / app 5xx? |
| Nginx error | `/var/log/nginx/error.log` (+ `.1` setelah rotate) | `connect() failed`, `upstream timed out` |
| Docker events | `/var/log/jepangku/docker-events.log` | Kapan stop/die/oom/start, exitCode |
| Origin uptime | `/var/log/jepangku/origin-uptime.log` | Window DOWN→UP per target |
| Prometheus (opsional) | `:9090` | CPU/RAM/disk/jaringan historis |

---

## LogQL siap pakai (Grafana → Explore → Loki)

```logql
# Kapan origin down?
{service="origin-uptime"} | json | state="DOWN"

# Transisi UP/DOWN saja
{service="origin-uptime"} | json | event="transition"

# Container stop/die/oom
{service="docker-events"} | json | Action=~"stop|die|oom|kill"

# Khusus produksi
{service="docker-events"} |~ "jepangku_(portal|lms|core|db|redis)"

# Nginx: upstream gagal
{job="nginx", log_type="error"} |= "connect() failed" or "upstream timed out"

# Nginx: access dengan upstream status 502/504 (butuh format jepangku_upstream)
{job="nginx", log_type="access"} |~ `us="502"|us="504"|us="-"`
```

## PromQL (jika metrics stack aktif)

```promql
# CPU host (100% - idle)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# RAM available
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Memory per container
container_memory_usage_bytes{name=~"jepangku_.*"}
```

---

## Checklist 5 menit saat Cloudflare 502

1. `{service="origin-uptime"} | json` → target mana DOWN, sejak kapan?
2. `{service="docker-events"} | json` → ada `stop`/`die`/`oom` sebelum window DOWN?
3. `{job="nginx",log_type="error"}` → `Connection refused` vs `upstream timed out`?
4. (Opsional) Prometheus → CPU/RAM spike di window yang sama?
5. `last -F` / `auth.log` → siapa login di sekitar event stop?

Dengan urutan itu, penyebab bisa dinyatakan dengan bukti, bukan dugaan.
