#!/usr/bin/env bash
# Probe origin di balik Nginx (localhost) — pengganti ringan Uptime Kuma.
# Mencatat TRANSISI UP↔DOWN + heartbeat tiap ~5 menit saat UP + tiap menit saat DOWN.
#
# Cron (setiap menit, sebagai root):
#   * * * * * root /opt/jepangku-infra/logging/scripts/origin-uptime-probe.sh >>/var/log/jepangku/origin-uptime-cron.err 2>&1
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/jepangku}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/origin-uptime.log}"
STATE_DIR="${STATE_DIR:-/var/lib/jepangku-uptime}"
HEARTBEAT_EVERY_SEC="${HEARTBEAT_EVERY_SEC:-300}"

mkdir -p "$LOG_DIR" "$STATE_DIR"
chmod 755 "$LOG_DIR" 2>/dev/null || true

TARGETS=(
  "portal|http://127.0.0.1:3001/"
  "lms|http://127.0.0.1:3002/"
  "core|http://127.0.0.1:8080/health"
)

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
now_epoch() { date +%s; }

emit() {
  local name="$1" state="$2" code="$3" ms="$4" event="$5"
  printf '{"ts":"%s","service":"origin-uptime","target":"%s","state":"%s","http":%s,"latencyMs":%s,"event":"%s"}\n' \
    "$(now_iso)" "$name" "$state" "$code" "$ms" "$event" >>"$LOG_FILE"
}

for entry in "${TARGETS[@]}"; do
  IFS='|' read -r name url <<<"$entry"

  start_ms=$(date +%s%3N 2>/dev/null || echo 0)
  code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 "$url" 2>/dev/null || echo "000")
  end_ms=$(date +%s%3N 2>/dev/null || echo 0)
  if [[ "$start_ms" != "0" && "$end_ms" != "0" ]]; then
    ms=$((end_ms - start_ms))
  else
    ms=-1
  fi

  state="DOWN"
  if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
    state="UP"
  fi

  state_file="$STATE_DIR/${name}.state"
  prev="UNKNOWN"
  last_hb=0
  if [[ -f "$state_file" ]]; then
    prev=$(cut -d'|' -f1 "$state_file")
    last_hb=$(cut -d'|' -f2 "$state_file")
  fi
  [[ -z "${last_hb:-}" || ! "$last_hb" =~ ^[0-9]+$ ]] && last_hb=0

  now=$(now_epoch)
  emit_event=""
  if [[ "$prev" != "$state" ]]; then
    emit_event="transition"
  elif [[ "$state" == "DOWN" ]]; then
    emit_event="still_down"
  elif [[ $((now - last_hb)) -ge $HEARTBEAT_EVERY_SEC ]]; then
    emit_event="heartbeat"
  fi

  if [[ -n "$emit_event" ]]; then
    emit "$name" "$state" "$code" "$ms" "$emit_event"
    echo "${state}|${now}" >"$state_file"
  elif [[ ! -f "$state_file" ]]; then
    echo "${state}|${now}" >"$state_file"
  fi
done
