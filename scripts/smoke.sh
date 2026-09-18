#!/usr/bin/env bash
# Smoke test after a deploy: GET <base_url>/v1/health must return 200.
# Usage: scripts/smoke.sh https://api-dev.example.com
set -euo pipefail

BASE_URL="${1:-}"
if [ -z "$BASE_URL" ]; then
  echo "usage: $0 <base_url>" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"

status=$(curl -sS -o /tmp/smoke_body.$$ -w '%{http_code}' --max-time 15 "$BASE_URL/v1/health" || true)
body=$(cat /tmp/smoke_body.$$ 2>/dev/null || true)
rm -f /tmp/smoke_body.$$

if [ "$status" = "200" ]; then
  echo "smoke: OK $BASE_URL/v1/health -> 200 $body"
  exit 0
fi
echo "smoke: FAIL $BASE_URL/v1/health -> ${status:-no response} $body" >&2
exit 1
