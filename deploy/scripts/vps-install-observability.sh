#!/usr/bin/env bash
# Install observability extras di VPS Jepangku:
#   1) Nginx upstream access log ($upstream_status, $upstream_response_time, ...)
#   2) Origin uptime probe (cron tiap menit)
#   3) Recreate logging stack (docker-events + promtail mounts)
#   4) Opsional: metrics stack (Prometheus + node-exporter + cAdvisor)
#
# Usage (di VPS):
#   bash deploy/scripts/vps-install-observability.sh
#   bash deploy/scripts/vps-install-observability.sh --with-metrics
set -euo pipefail

WITH_METRICS=0
for arg in "$@"; do
  case "$arg" in
    --with-metrics) WITH_METRICS=1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOGGING_DIR="${LOGGING_DIR:-$REPO_ROOT/logging}"
# Fallback path yang dipakai di VPS
if [[ ! -d "$LOGGING_DIR" && -d /home/developer/Jepangku-infra/logging ]]; then
  LOGGING_DIR=/home/developer/Jepangku-infra/logging
fi
if [[ ! -d "$LOGGING_DIR" && -d /opt/jepangku-infra/logging ]]; then
  LOGGING_DIR=/opt/jepangku-infra/logging
fi

NGINX_SNIPPET_SRC="$LOGGING_DIR/nginx/jepangku-upstream-log.conf"
NGINX_SNIPPET_DST="/etc/nginx/conf.d/jepangku-upstream-log.conf"
PROBE_SRC="$LOGGING_DIR/scripts/origin-uptime-probe.sh"
PROBE_DST="/usr/local/bin/jepangku-origin-uptime-probe.sh"
CRON_FILE="/etc/cron.d/jepangku-observability"

echo "==> Jepangku observability install"
echo "    logging dir: $LOGGING_DIR"

if [[ ! -f "$NGINX_SNIPPET_SRC" ]]; then
  echo "ERROR: snippet tidak ditemukan: $NGINX_SNIPPET_SRC"
  exit 1
fi

# --- 1) Nginx upstream log ---
echo "==> Install Nginx upstream log format"
sudo mkdir -p /etc/nginx/conf.d
sudo cp "$NGINX_SNIPPET_SRC" "$NGINX_SNIPPET_DST"

# Hapus access_log default di http{} agar tidak double-log (snippet sudah set access_log)
if sudo grep -qE '^\s*access_log\s+/var/log/nginx/access\.log;' /etc/nginx/nginx.conf; then
  echo "    comment out default access_log di nginx.conf (diganti format upstream)"
  sudo sed -i -E 's|^(\s*)access_log\s+/var/log/nginx/access\.log;|\1# access_log /var/log/nginx/access.log; # diganti jepangku_upstream|' /etc/nginx/nginx.conf
fi

if sudo nginx -t; then
  sudo systemctl reload nginx
  echo "    nginx reloaded OK"
else
  echo "ERROR: nginx -t gagal — batalkan perubahan snippet"
  sudo rm -f "$NGINX_SNIPPET_DST"
  exit 1
fi

# --- 2) Origin uptime probe ---
echo "==> Install origin uptime probe"
sudo mkdir -p /var/log/jepangku /var/lib/jepangku-uptime
sudo chmod 755 /var/log/jepangku
sudo cp "$PROBE_SRC" "$PROBE_DST"
sudo chmod 755 "$PROBE_DST"

sudo tee "$CRON_FILE" >/dev/null <<EOF
# Jepangku origin uptime probe — bukti kapan origin mulai DOWN/UP
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* * * * * root $PROBE_DST
EOF
sudo chmod 644 "$CRON_FILE"
echo "    cron: $CRON_FILE"

# Jalankan sekali sekarang
sudo "$PROBE_DST" || true
echo "    sample:"
sudo tail -n 3 /var/log/jepangku/origin-uptime.log 2>/dev/null || echo "    (belum ada log)"

# --- 3) Logging stack recreate ---
echo "==> Recreate logging stack (docker-events + promtail host mounts)"
cd "$LOGGING_DIR"
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

COMPOSE=(docker compose -f docker-compose.logging.yml)
if [[ "$WITH_METRICS" -eq 1 ]]; then
  COMPOSE+=(-f docker-compose.metrics.yml)
  echo "    + metrics stack (Prometheus/node-exporter/cAdvisor)"
fi

"${COMPOSE[@]}" up -d

echo ""
echo "==> Selesai"
echo "    Nginx access: field us=/urt=/uct= (upstream)"
echo "    Docker events: /var/log/jepangku/docker-events.log"
echo "    Origin uptime: /var/log/jepangku/origin-uptime.log"
echo ""
echo "LogQL cepat (Grafana Explore → Loki):"
echo '  {service="origin-uptime"} | json'
echo '  {service="docker-events"} | json | Action="die"'
echo '  {job="nginx",log_type="error"} |= "connect() failed"'
echo '  {job="nginx",log_type="access"} |~ "us=\"502\"|us=\"504\""'
if [[ "$WITH_METRICS" -eq 1 ]]; then
  echo ""
  echo "Prometheus: http://127.0.0.1:9090 (SSH tunnel -L 9090:127.0.0.1:9090)"
  echo "PromQL contoh: rate(node_cpu_seconds_total{mode=\"idle\"}[5m])"
  echo "               container_memory_usage_bytes{name=~\"jepangku_.*\"}"
fi
