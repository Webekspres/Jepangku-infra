#!/bin/sh
# Stream Docker container lifecycle events → satu JSON object per baris.
set -eu

LOG_DIR="${LOG_DIR:-/var/log/jepangku}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/docker-events.log}"

mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR" 2>/dev/null || true

exec docker events \
  --filter 'type=container' \
  --filter 'event=start' \
  --filter 'event=die' \
  --filter 'event=kill' \
  --filter 'event=stop' \
  --filter 'event=oom' \
  --filter 'event=destroy' \
  --filter 'event=restart' \
  --format '{{json .}}' \
  >>"$LOG_FILE"
