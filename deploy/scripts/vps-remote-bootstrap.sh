#!/usr/bin/env bash
set -euo pipefail
cd ~/Jepangku-infra/logging

sed -i 's|"3002:3000"|"${GRAFANA_PORT:-3040}:3000"|' docker-compose.logging.yml
sed -i 's|GF_SECURITY_ADMIN_USER=admin|GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}|' docker-compose.logging.yml
sed -i 's|GF_SECURITY_ADMIN_PASSWORD=admin|GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}|' docker-compose.logging.yml

cat > grafana/provisioning/datasources/datasources.yml <<'YAML'
apiVersion: 1

deleteDatasources:
  - name: Loki
    orgId: 1

datasources:
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: true
    editable: false
    jsonData:
      maxLines: 5000
YAML

if [ -f grafana/provisioning/dashboards/jepangku-logging-dashboard.json ]; then
  sed -i 's/"uid": "Loki"/"uid": "loki"/g' grafana/provisioning/dashboards/jepangku-logging-dashboard.json
fi

if [ ! -f .env ]; then
  PASS=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
  cat > .env <<ENV
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${PASS}
GRAFANA_PORT=3040
ENV
  echo "GRAFANA_PASSWORD=${PASS}" > ~/jepangku-grafana-password.txt
  chmod 600 ~/jepangku-grafana-password.txt
fi

set -a
source .env
set +a

docker compose -f docker-compose.logging.yml up -d

for i in $(seq 1 25); do curl -sf http://127.0.0.1:3100/ready >/dev/null 2>&1 && break; sleep 2; done
for i in $(seq 1 25); do curl -sf "http://127.0.0.1:${GRAFANA_PORT}/api/health" >/dev/null 2>&1 && break; sleep 2; done

docker compose -f docker-compose.logging.yml ps
echo "LOKI:"; curl -sf http://127.0.0.1:3100/ready; echo
echo "GRAFANA:"; curl -sf "http://127.0.0.1:${GRAFANA_PORT}/api/health"; echo
echo "CREDENTIALS:"; cat ~/jepangku-grafana-password.txt
