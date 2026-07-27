#!/bin/bash
# =============================================================================
# run_isolation_tests.sh — Fase 1 / T1.4
#
# Executa os testes de isolamento SQL gerados por apply_test_uuids.sh
# (test/_generated/) contra o banco informado, e produz um relatório
# PASS/FAIL consolidado. O conjunto é dinâmico — quem decide quais arquivos
# entram é o apply_test_uuids.sh (glob 0002–NNNN, menos o 0006 manual).
#
# Este script varre test/_generated/*.sql — quem decide o conjunto é o
# apply_test_uuids.sh. Rode-o novamente sempre que criar um teste novo.
#
# Uso:
#   ./scripts/apply_test_uuids.sh   # gera test/_generated/ primeiro
#   ./scripts/run_isolation_tests.sh "postgresql://postgres:SENHA@db.pkbluscdssiiumrppmwa.supabase.co:5432/postgres"
#
# Requer: psql instalado e acesso de rede ao banco (direct connection, não
# o pooler, pois os testes usam SET LOCAL role e set_config em transação).
# =============================================================================
set -uo pipefail

DATABASE_URL="${1:?Uso: $0 <DATABASE_URL>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN_DIR="$SCRIPT_DIR/test/_generated"
REPORT_FILE="$SCRIPT_DIR/test_results_isolation_$(date +%Y-%m-%d_%H%M%S).txt"

if [ ! -d "$GEN_DIR" ]; then
  echo "ERRO: $GEN_DIR não existe. Rode ./scripts/apply_test_uuids.sh primeiro." >&2
  exit 1
fi

echo "Relatório de execução — testes de isolamento RLS" > "$REPORT_FILE"
echo "Data: $(date)" >> "$REPORT_FILE"
echo "======================================================" >> "$REPORT_FILE"

TOTAL=0
FAILED=0

for f in "$GEN_DIR"/*.sql; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  TOTAL=$((TOTAL + 1))

  echo >> "$REPORT_FILE"
  echo "--- $name ---" >> "$REPORT_FILE"

  output=$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f" 2>&1)
  status=$?

  # Antes só pegava NOTICE:/ERROR:, o que escondia falhas de conexão do psql
  # (que vêm como "psql: error:" ou "FATAL:") — um teste podia falhar com
  # exit != 0 e o relatório não mostrar nenhuma pista do motivo real.
  echo "$output" | grep -E "NOTICE:|ERROR:|FATAL:|psql: error:" >> "$REPORT_FILE"

  if [ $status -ne 0 ] && ! echo "$output" | grep -q "Dados de teste revertidos"; then
    echo "RESULTADO: FALHOU (exit=$status)" >> "$REPORT_FILE"
    FAILED=$((FAILED + 1))
    echo "FALHOU: $name"
  elif echo "$output" | grep -qi "FALHOU"; then
    echo "RESULTADO: FALHOU (asserção interna reportou FALHOU)" >> "$REPORT_FILE"
    FAILED=$((FAILED + 1))
    echo "FALHOU: $name"
  else
    echo "RESULTADO: PASSOU" >> "$REPORT_FILE"
    echo "PASSOU: $name"
  fi
done

echo >> "$REPORT_FILE"
echo "======================================================" >> "$REPORT_FILE"
echo "Total: $TOTAL | Falhas: $FAILED | Sucesso: $((TOTAL - FAILED))" >> "$REPORT_FILE"

echo
echo "== Resumo =="
echo "Total: $TOTAL | Falhas: $FAILED | Sucesso: $((TOTAL - FAILED))"
echo "Relatório completo salvo em: $REPORT_FILE"

if [ "$FAILED" -gt 0 ]; then
  echo
  echo "ATENÇÃO: existem falhas. NÃO prossiga para a Fase 2 até corrigir e reexecutar."
  exit 1
fi

echo
echo "Todos os testes automatizados passaram. Falta ainda rodar manualmente:"
echo "  - test/isolation/0006_public_quotation_link_test.sql (precisa de um orçamento aprovado real)"
echo "  - test/isolation/rls_isolation_test.sql (checagem complementar de invariantes, não substitui os testes de RLS)"
