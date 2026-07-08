#!/usr/bin/env bash
# Setup logging stack (Loki + Promtail + Grafana) di VPS Jepangku.
#
# Usage (sebagai user developer di VPS):
#   bash deploy/scripts/vps-setup-logging.sh
#
# Prasyarat: Docker + git. Promtail membaca semua container di host ini.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Webekspres/Jepangku-infra.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/jepangku-infra}"
BRANCH="${BRANCH:-main}"
GRAFANA_PORT="${GRAFANA_PORT:-3040}"

echo "==> Jepangku logging stack setup"
echo "    dir:   $INSTALL_DIR"
echo "    port:  Grafana $GRAFANA_PORT (3002 dipakai jepangku_lms)"

if ! command -v docker >/dev/null; then
  echo "ERROR: docker tidak ditemukan"
  exit 1
fi

if ss -tlnp 2>/dev/null | grep -q ":${GRAFANA_PORT} "; then
  echo "ERROR: port $GRAFANA_PORT sudah dipakai"
  ss -tlnp | grep ":${GRAFANA_PORT} " || true
  exit 1
fi

if [ ! -d "$INSTALL_DIR/.git" ]; then
  echo "==> Clone $REPO_URL"
  sudo mkdir -p "$INSTALL_DIR"
  sudo chown "$(whoami):$(whoami)" "$INSTALL_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
else
  echo "==> Pull latest"
  git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
fi

cd "$INSTALL_DIR/logging"

if [ ! -f .env ]; then
  echo "==> Buat .env dari .env.example"
  cp .env.example .env
  PASS="$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)"
  sed -i "s/^GRAFANA_ADMIN_PASSWORD=.*/GRAFANA_ADMIN_PASSWORD=${PASS}/" .env
  sed -i "s/^GRAFANA_PORT=.*/GRAFANA_PORT=${GRAFANA_PORT}/" .env
  echo ""
  echo "=========================================="
  echo " Grafana password (simpan!): $PASS"
  echo " URL: http://127.0.0.1:${GRAFANA_PORT}"
  echo "=========================================="
  echo ""
else
  echo "==> .env sudah ada — tidak di-overwrite"
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

echo "==> docker compose up"
docker compose -f docker-compose.logging.yml up -d

echo "==> Tunggu Loki ready..."
for i in $(seq 1 20); do
  if curl -sf http://127.0.0.1:3100/ready >/dev/null 2>&1; then
    echo "Loki OK"
    break
  fi
  sleep 2
done

for i in $(seq 1 20); do
  if curl -sf "http://127.0.0.1:${GRAFANA_PORT}/api/health" >/dev/null 2>&1; then
    echo "Grafana OK"
    break
  fi
  sleep 2
done

docker compose -f docker-compose.logging.yml ps

echo ""
echo "==> Setup selesai"
echo "    Grafana: http://127.0.0.1:${GRAFANA_PORT}  (SSH tunnel dari laptop)"
echo "    Query:   {service=\"jepangku-news\"} |= \"request.complete\""
echo ""
echo "SSH tunnel dari laptop:"
echo "  ssh -L 3040:127.0.0.1:${GRAFANA_PORT} 103.25.223.16"
echo "  lalu buka http://localhost:3040"
