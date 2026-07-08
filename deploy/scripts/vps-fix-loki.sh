#!/usr/bin/env bash
set -euo pipefail
cd ~/Jepangku-infra/logging

# Fix Loki config for latest image (shared_store removed)
if grep -q 'shared_store' loki/loki-config.yml; then
  sed -i '/shared_store/d' loki/loki-config.yml
fi
if ! grep -q 'delete_request_store' loki/loki-config.yml; then
  sed -i '/retention_enabled: true/a\  delete_request_store: filesystem' loki/loki-config.yml
fi

# Fix compose: disable loki healthcheck, use service_started
python3 <<'PY'
from pathlib import Path
p = Path("docker-compose.logging.yml")
text = p.read_text()
text = text.replace("condition: service_healthy", "condition: service_started")
if "healthcheck:" in text and "disable: true" not in text.split("loki:")[1].split("promtail:")[0]:
    # insert disable healthcheck under loki volumes section end
    pass
# simpler: replace loki healthcheck block if present
import re
text = re.sub(
    r"(  loki:.*?volumes:.*?loki-data:/loki)\n(    healthcheck:\n      test:.*?\n      interval:.*?\n      timeout:.*?\n      retries:.*?\n      start_period:.*?\n)?",
    r"\1\n    healthcheck:\n      disable: true\n",
    text,
    count=1,
    flags=re.S,
)
p.write_text(text)
PY

docker compose -f docker-compose.logging.yml down 2>/dev/null || true
set -a; source .env; set +a
docker compose -f docker-compose.logging.yml up -d

for i in $(seq 1 30); do curl -sf http://127.0.0.1:3100/ready >/dev/null 2>&1 && break; sleep 2; done
for i in $(seq 1 30); do curl -sf "http://127.0.0.1:${GRAFANA_PORT}/api/health" >/dev/null 2>&1 && break; sleep 2; done

docker compose -f docker-compose.logging.yml ps
echo LOKI:; curl -sf http://127.0.0.1:3100/ready; echo
echo GRAFANA:; curl -sf "http://127.0.0.1:${GRAFANA_PORT}/api/health"; echo
echo PASS:; cat ~/jepangku-grafana-password.txt
