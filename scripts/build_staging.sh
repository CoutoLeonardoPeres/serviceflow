#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES_FILE="${1:-dart_defines/staging.json}"
PACKAGE_NAME="${2:-serviceflow-staging.zip}"
DEFINES_PATH="$ROOT_DIR/$DEFINES_FILE"
OUTPUT_PATH="$ROOT_DIR/dist/$PACKAGE_NAME"

if [[ ! -f "$DEFINES_PATH" ]]; then
  echo "Arquivo de ambiente nao encontrado: $DEFINES_FILE"
  echo "Crie a partir de dart_defines/staging.example.json antes do build."
  exit 1
fi

cd "$ROOT_DIR"
flutter build web \
  --dart-define-from-file="$DEFINES_FILE" \
  --no-source-maps \
  --no-wasm-dry-run \
  --pwa-strategy=none

cp "$ROOT_DIR/web/.htaccess" "$ROOT_DIR/build/web/.htaccess"

mkdir -p "$ROOT_DIR/dist"
rm -f "$OUTPUT_PATH"
(
  cd "$ROOT_DIR/build/web"
  zip -qr "$OUTPUT_PATH" .
)

"$ROOT_DIR/scripts/write_release_manifest.sh" "dist/$PACKAGE_NAME"

echo "Pacote staging gerado em: $OUTPUT_PATH"
