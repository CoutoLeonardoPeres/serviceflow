#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_PATH="${1:-dist/serviceflow-staging.zip}"
PACKAGE_ABS="$ROOT_DIR/$PACKAGE_PATH"

if [[ ! -f "$PACKAGE_ABS" ]]; then
  echo "Pacote nao encontrado: $PACKAGE_PATH"
  exit 1
fi

PACKAGE_FILE="$(basename "$PACKAGE_ABS")"
MANIFEST_PATH="$ROOT_DIR/dist/${PACKAGE_FILE%.zip}.manifest.txt"
CHECKSUM="$(shasum -a 256 "$PACKAGE_ABS" | awk '{print $1}')"
SIZE_BYTES="$(wc -c < "$PACKAGE_ABS" | tr -d ' ')"
COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
CREATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

cat > "$MANIFEST_PATH" <<EOF
ServiceFlow release package
package=$PACKAGE_FILE
size_bytes=$SIZE_BYTES
sha256=$CHECKSUM
commit=$COMMIT
created_at_utc=$CREATED_AT
EOF

echo "Manifesto gerado em: $MANIFEST_PATH"
cat "$MANIFEST_PATH"
