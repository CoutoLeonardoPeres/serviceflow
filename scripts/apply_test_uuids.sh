#!/bin/bash
# =============================================================================
# apply_test_uuids.sh — Fase 1 / T1.3 + T1.4
#
# Gera cópias dos arquivos de seed e de teste de isolamento com os 7 UUIDs
# placeholder substituídos pelos UUIDs reais do seu ambiente, em test/_generated/
# (pasta ignorada pelo Git — nunca commitar dados de teste com UUIDs reais).
#
# Uso:
#   export TENANT_ALPHA="<uuid real do tenant Alpha>"
#   export TENANT_BETA="<uuid real do tenant Beta>"
#   export USER_ALPHA="<uuid real do owner Alpha>"
#   export USER_BETA="<uuid real do owner Beta>"
#   export USER_TECH="<uuid real do tecnico Alpha>"
#   export USER_VIEWER="<uuid real do viewer Alpha>"
#   ./scripts/apply_test_uuids.sh
#
# Depois, rode cada arquivo gerado com psql, por exemplo:
#   psql "$DATABASE_URL" -f test/_generated/0002_rls_customers_test.sql
# Ou use ./scripts/run_isolation_tests.sh para rodar todos em sequência.
# =============================================================================
set -euo pipefail

: "${TENANT_ALPHA:?Defina TENANT_ALPHA}"
: "${TENANT_BETA:?Defina TENANT_BETA}"
: "${USER_ALPHA:?Defina USER_ALPHA}"
: "${USER_BETA:?Defina USER_BETA}"
: "${USER_TECH:?Defina USER_TECH}"
: "${USER_VIEWER:?Defina USER_VIEWER}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$SCRIPT_DIR/test/isolation"
OUT_DIR="$SCRIPT_DIR/test/_generated"

mkdir -p "$OUT_DIR"

echo "== Gerando arquivos com UUIDs reais em $OUT_DIR =="

for f in "$SRC_DIR"/000{2,3,4,5,7,8,9}_*.sql "$SRC_DIR"/001{0,1,2,3}_*.sql; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  sed \
    -e "s/a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1/$TENANT_ALPHA/g" \
    -e "s/b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2/$TENANT_BETA/g" \
    -e "s/a1000000-0000-4000-8000-000000000001/$USER_ALPHA/g" \
    -e "s/b2000000-0000-4000-8000-000000000002/$USER_BETA/g" \
    -e "s/a1000000-0000-4000-8000-000000000003/$USER_TECH/g" \
    -e "s/a1000000-0000-4000-8000-000000000004/$USER_VIEWER/g" \
    "$f" > "$OUT_DIR/$name"
  echo "OK: $name"
done

echo
echo "== Concluído. Arquivos prontos em test/_generated/ =="
echo "Rode ./scripts/run_isolation_tests.sh \"\$DATABASE_URL\" para executar todos em sequência."
