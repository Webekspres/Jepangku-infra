# Runbook: investigasi downtime / 502 — Jepangku VPS

Dokumen ini melengkapi [`README.md`](./README.md). Fokus: **cara membaca sinyal baru di Grafana** agar kesimpulan berbasis bukti.

---

## Arsitektur

```
Cloudflare
    │
    ▼
Nginx (host)          ← /var/log/nginx/
    │  proxy_pass 127.0.0.1:3001|3002|8080
    ▼
Docker                ← portal / lms / core / db / redis
```

| Sumber | Label Loki | Menjawab |
| :--- | :--- | :--- |
| Origin uptime probe | `service="origin-uptime"` | Sejak kapan portal/lms/core tidak menjawab di localhost? |
| Docker events | `service="docker-events"` | Apakah ada stop/die/oom/kill? |
| Nginx error/access | `job="nginx"` | Connection refused vs upstream timeout vs status upstream? |
| App Pino | `service="jepangku-…"` | Error aplikasi saat proses masih hidup |
| Prometheus (opsional) | datasource Prometheus | CPU/RAM/disk di window yang sama |

---

## Buka Grafana

1. Tunnel: `ssh -L 3040:127.0.0.1:3040 vps-jepangku`
2. Browser: http://localhost:3040
3. **Explore** → datasource **Loki**
4. Set **time range** ke waktu insiden

---

## Query siap pakai

### 1. Uptime origin (paling cepat)

```logql
{service="origin-uptime"} | json | state="DOWN"
```

```logql
{service="origin-uptime"} | json | event="transition"
```

Interpretasi:

- `target=portal|lms|core` + `state=DOWN` → origin tidak merespons  
- `event=transition` → titik ganti UP↔DOWN (awal/akhir downtime)  
- `still_down` → masih down (log tiap menit)  

### 2. Lifecycle container

```logql
{service="docker-events"} | json | Action=~"stop|die|oom|kill|start"
```

```logql
{service="docker-events"} |~ "jepangku_(portal|lms|core|db|redis)"
```

Interpretasi:

- `Action=stop|die` + `exitCode=0` → biasanya dihentikan sengaja (`compose stop` / `docker stop`)  
- `Action=oom` → kehabisan memori  
- Bandingkan timestamp dengan transisi `origin-uptime`  

### 3. Nginx upstream

```logql
{job="nginx", log_type="error"} |= "connect() failed" or "upstream timed out" or "Connection refused"
```

```logql
{job="nginx", log_type="access"} |~ `us="502"|us="504"|us="-"`
```

Interpretasi:

| Gejala Nginx | Kemungkinan |
| :--- | :--- |
| `connect() failed (111: Connection refused)` | Proses upstream tidak listen (container down) |
| `upstream timed out` | App hang / terlalu lambat |
| `us="502"` / `us="-"` di access | Upstream gagal; lihat `urt` / `uct` |

### 4. Aplikasi

```logql
{service="jepangku-news"} | json | level="error"
{service="jepangku-lms"} | json | status >= 500
{service="jepangku-core"} | json | level="error"
```

Hanya relevan jika origin masih UP. Jika container mati, log app biasanya **berhenti** — bukan berarti “tidak ada error”.

### 5. Metrics (jika metrics stack aktif)

Explore → **Prometheus**:

```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
container_memory_usage_bytes{name=~"jepangku_.*"}
```

---

## Checklist 5 menit (502 / site down)

1. Origin DOWN? → `{service="origin-uptime"} | json | state="DOWN"`  
2. Ada stop/die/oom? → `{service="docker-events"} | json | Action=~"stop|die|oom"`  
3. Nginx bilang apa? → refused vs timeout  
4. Resource spike? → Prometheus (opsional)  
5. App error? → Pino, hanya jika origin UP  

Contoh kesimpulan berbasis bukti:

- “Portal DOWN 23:28–07:01; docker-events `stop`/`die` exit 0; Nginx `Connection refused` ke `:3001`.”  
- “CPU 100% selama 12 menit; Nginx `upstream timed out`; container tetap running.”  

---

## File host (tanpa Grafana)

```bash
tail -f /var/log/jepangku/origin-uptime.log
tail -f /var/log/jepangku/docker-events.log
sudo tail -f /var/log/nginx/error.log
# access dengan field upstream:
sudo tail -f /var/log/nginx/access.log
```
