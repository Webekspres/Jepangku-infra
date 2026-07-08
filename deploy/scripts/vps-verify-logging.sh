#!/usr/bin/env bash
# Verifikasi cepat stack logging di VPS: label, sample stream, error promtail.
set -euo pipefail

LOKI="http://127.0.0.1:3100"
NOW=$(date +%s)
S="$(( NOW - 300 ))000000000"
E="${NOW}000000000"

echo "=== Loki ready ==="
curl -s "$LOKI/ready" || true
echo

echo "=== label: job ==="
curl -s "$LOKI/loki/api/v1/label/job/values?start=$S&end=$E"; echo

echo "=== label: container ==="
curl -s "$LOKI/loki/api/v1/label/container/values?start=$S&end=$E"; echo

echo "=== label: service ==="
curl -s "$LOKI/loki/api/v1/label/service/values?start=$S&end=$E"; echo

echo "=== sample streams (job=docker, 5m) ==="
curl -s --get "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query={job="docker"}' \
  --data-urlencode 'limit=3' \
  --data-urlencode "start=$S" --data-urlencode "end=$E" \
  | grep -o '"stream":{[^}]*}' | sort -u | head -20 || echo "(tidak ada stream)"
echo

echo "=== all series (service_name present, 5m) ==="
curl -s --get "$LOKI/loki/api/v1/series" \
  --data-urlencode 'match[]={service_name=~".+"}' \
  --data-urlencode "start=$S" --data-urlencode "end=$E" \
  | grep -o '"container":"[^"]*"' | sort | uniq -c | head -20 || echo "(tidak ada container)"
echo

echo "=== unknown_service count (2m) ==="
curl -s --get "$LOKI/loki/api/v1/query_range" \
  --data-urlencode 'query=sum(count_over_time({service_name="unknown_service"}[2m]))' \
  --data-urlencode "start=$S" --data-urlencode "end=$E" \
  | grep -o '"values":\[.*\]' | head -c 200; echo
echo

echo "=== promtail errors (60s terakhir) ==="
docker logs --since 60s jepangku-promtail 2>&1 | grep -ic 'too old\|too far behind' || true
