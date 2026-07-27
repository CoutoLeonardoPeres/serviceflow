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

# Pega todos os testes numerados automaticamente, exceto os que exigem execução
# manual. Antes esta lista era fixa (000{2,3,4,5,7,8,9} e 001{0,1,2,3}), o que
# fez os testes do F2 (0014–0016) ficarem de fora silenciosamente ao serem
# criados. Não volte para uma lista fixa: novos testes precisam entrar sozinhos.
#
# Excluídos de propósito:
#   0006_public_quotation_link_test.sql — depende de orçamento aprovado real
#   rls_isolation_test.sql              — checagem complementar de invariantes
SKIP_PATTERN='0006_public_quotation_link_test\.sql|rls_isolation_test\.sql'

for f in "$SRC_DIR"/[0-9][0-9][0-9][0-9]_*.sql; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  if echo "$name" | grep -qE "$SKIP_PATTERN"; then
    echo "PULADO (execução manual): $name"
    continue
  fi
  # Duas passadas por variável:
  #   1) troca o UUID placeholder dentro da linha `\set NOME 'uuid'` no topo do
  #      arquivo — cosmético, só documentação, o psql não usa mais essa
  #      variável para nada depois da passada 2.
  #   2) troca `:'NOME'` (a forma como o corpo do teste referenciava a
  #      variável) pelo literal `'uuid-real'` diretamente no SQL.
  #
  # A passada 2 existe porque a interpolação de variáveis do psql (`:'VAR'`)
  # não é confiável dentro de blocos `DO $$ ... $$`: o psql rastreia aspas
  # simples caractere a caractere para saber se está "dentro de uma string" e
  # não entende $$ como delimitador — toda vez que o corpo do PL/pgSQL tem um
  # número ímpar de aspas simples antes da referência (comum, já que RAISE
  # NOTICE/EXCEPTION usam strings com aspas), o rastreador do psql desalinha e
  # a substituição é pulada, causando `syntax error at or near ":"` em
  # runtime. Descoberto em 2026-07-26 na primeira execução real destes testes
  # contra um banco de verdade — nunca tinha sido pego porque os testes nunca
  # tinham rodado antes. Substituição literal no corpo elimina a dependência
  # da interpolação do psql e funciona independente de contagem de aspas.
  sed \
    -e "s/a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1/$TENANT_ALPHA/g" \
    -e "s/b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2/$TENANT_BETA/g" \
    -e "s/a1000000-0000-4000-8000-000000000001/$USER_ALPHA/g" \
    -e "s/b2000000-0000-4000-8000-000000000002/$USER_BETA/g" \
    -e "s/a1000000-0000-4000-8000-000000000003/$USER_TECH/g" \
    -e "s/a1000000-0000-4000-8000-000000000004/$USER_VIEWER/g" \
    -e "s/:'TENANT_ALPHA'/'$TENANT_ALPHA'/g" \
    -e "s/:'TENANT_BETA'/'$TENANT_BETA'/g" \
    -e "s/:'USER_ALPHA'/'$USER_ALPHA'/g" \
    -e "s/:'USER_BETA'/'$USER_BETA'/g" \
    -e "s/:'USER_TECH'/'$USER_TECH'/g" \
    -e "s/:'USER_VIEWER'/'$USER_VIEWER'/g" \
    "$f" > "$OUT_DIR/$name"
  echo "OK: $name"
done

echo
echo "== Concluído. Arquivos prontos em test/_generated/ =="
echo "Rode ./scripts/run_isolation_tests.sh \"\$DATABASE_URL\" para executar todos em sequência."
