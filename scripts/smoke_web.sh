#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8091}"
BASE_URL="${BASE_URL%/}"

fail() {
  echo "FALHOU: $1"
  exit 1
}

echo "Smoke test ServiceFlow: $BASE_URL"

status="$(curl -L -s -o /tmp/serviceflow-index.html -w "%{http_code}" "$BASE_URL/")"
[[ "$status" == "200" ]] || fail "homepage retornou HTTP $status"

grep -qi "ServiceFlow" /tmp/serviceflow-index.html ||
  fail "homepage nao contem ServiceFlow"

grep -q "flutter_bootstrap.js" /tmp/serviceflow-index.html ||
  fail "homepage nao referencia flutter_bootstrap.js"

for asset in \
  "/flutter_bootstrap.js" \
  "/main.dart.js" \
  "/assets/FontManifest.json" \
  "/manifest.json"; do
  asset_status="$(curl -L -s -o /dev/null -w "%{http_code}" "$BASE_URL$asset")"
  [[ "$asset_status" == "200" ]] ||
    fail "asset $asset retornou HTTP $asset_status"
done

login_status="$(curl -L -s -o /dev/null -w "%{http_code}" "$BASE_URL/#/login")"
[[ "$login_status" == "200" ]] || fail "rota /#/login retornou HTTP $login_status"

echo "OK: app web responde e assets principais carregam."
