#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES_FILE="${1:-dart_defines/dev.json}"
PORT="${2:-8091}"
BASE_URL="http://127.0.0.1:$PORT"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

cd "$ROOT_DIR"

if [[ ! -f "$DEFINES_FILE" ]]; then
  echo "Arquivo de ambiente nao encontrado: $DEFINES_FILE"
  exit 1
fi

echo "1/7 Dependencias"
flutter pub get

echo "2/7 Analise estatica"
flutter analyze

echo "3/7 Testes criticos"
flutter test \
  test/dashboard/dashboard_screen_test.dart \
  test/financials/financial_list_screen_test.dart \
  test/financials/receipt_pdf_generator_test.dart \
  test/work_orders/work_order_detail_screen_test.dart \
  test/quotations/quotation_detail_screen_test.dart \
  test/router/app_router_redirect_test.dart

echo "4/7 Build web"
flutter build web \
  --dart-define-from-file="$DEFINES_FILE" \
  --no-source-maps \
  --no-wasm-dry-run \
  --pwa-strategy=none

cp "$ROOT_DIR/web/.htaccess" "$ROOT_DIR/build/web/.htaccess"

echo "5/7 Servidor local temporario"
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Porta $PORT ja esta em uso; validando servidor existente."
else
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT_DIR/build/web" >/tmp/serviceflow-release-check.log 2>&1 &
  SERVER_PID="$!"
  sleep 2
fi

echo "6/7 Smoke web"
"$ROOT_DIR/scripts/smoke_web.sh" "$BASE_URL"

echo "7/7 Security preflight"
"$ROOT_DIR/scripts/security_preflight.sh"

echo "OK: release check concluido para $BASE_URL"
