#!/bin/bash
# =============================================================================
# create_test_users.sh — Fase 1 / T1.2
#
# Cria os 5 usuários de teste necessários para os testes de isolamento RLS
# via Supabase Auth Admin API (GoTrue), em vez de cadastro manual no painel.
#
# IMPORTANTE: a Admin API NÃO permite escolher o UUID do usuário — o Supabase
# gera um UUID aleatório para cada um. Este script cria os usuários e imprime
# a tabela de mapeamento email -> UUID real ao final. Você precisa usar esses
# UUIDs reais para substituir os placeholders em:
#   - supabase/seed/dev_seed.sql
#   - test/isolation/*.sql (todos)
# Use o script scripts/apply_test_uuids.sh para fazer essa substituição em lote.
#
# Uso:
#   export SUPABASE_URL="https://pkbluscdssiiumrppmwa.supabase.co"
#   export SUPABASE_SERVICE_ROLE_KEY="<service_role_key_do_painel>"
#   ./scripts/create_test_users.sh
#
# A SERVICE_ROLE_KEY nunca deve ir para o Flutter/dart_defines. Use-a apenas
# neste script, localmente, e não a commite em lugar nenhum.
# =============================================================================
set -euo pipefail

: "${SUPABASE_URL:?Defina SUPABASE_URL antes de rodar (ex.: https://pkbluscdssiiumrppmwa.supabase.co)}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Defina SUPABASE_SERVICE_ROLE_KEY antes de rodar (Settings > API > service_role)}"

PASSWORD="${TEST_USER_PASSWORD:-ServiceFlow!Teste2026}"

# Arrays indexados (não associativos) de propósito: o bash padrão do macOS é
# 3.2 (licenciamento da Apple) e não suporta `declare -A` (só existe a partir
# do bash 4). A sintaxe `["chave"]=valor` nesse bash é mal interpretada como
# índice numérico referenciando uma variável de mesmo nome, e falha com
# "unbound variable" sob `set -u`, sem criar nenhum usuário. Duas listas
# paralelas funcionam em qualquer bash 3+.
USER_KEYS=(alpha_owner alpha_tech alpha_viewer alpha_analyst beta_owner)
USER_EMAILS=(
  "alpha.owner.teste@serviceflow.local"
  "alpha.tech.teste@serviceflow.local"
  "alpha.viewer.teste@serviceflow.local"
  "alpha.analyst.teste@serviceflow.local"
  "beta.owner.teste@serviceflow.local"
)

echo "== Criando 5 usuários de teste em $SUPABASE_URL =="
echo

RESULT_KEYS=()
RESULT_IDS=()

for i in "${!USER_KEYS[@]}"; do
  key="${USER_KEYS[$i]}"
  email="${USER_EMAILS[$i]}"
  response=$(curl -sS -X POST "$SUPABASE_URL/auth/v1/admin/users" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$PASSWORD\",\"email_confirm\":true}")

  # `|| true` é necessário: sob set -e + pipefail, se a chave for inválida a
  # resposta não tem "id" e o grep sai com status 1, o que mataria o script
  # inteiro aqui mesmo, antes de imprimir o aviso abaixo.
  user_id=$(echo "$response" | grep -o '"id":"[a-f0-9-]*"' | head -1 | cut -d'"' -f4 || true)

  if [ -z "$user_id" ]; then
    echo "AVISO: falha ao criar $email (talvez já exista). Resposta:"
    echo "$response"
    echo
    continue
  fi

  RESULT_KEYS+=("$key")
  RESULT_IDS+=("$user_id")
  echo "OK: $key -> $email -> $user_id"
done

echo
echo "== Resumo (guarde estes valores) =="
echo "Senha usada para todos: $PASSWORD"
echo
for i in "${!RESULT_KEYS[@]}"; do
  echo "${RESULT_KEYS[$i]} = ${RESULT_IDS[$i]}"
done

echo
echo "== Próximo passo =="
echo "1. Rode supabase/seed/dev_seed.sql (com os placeholders padrão) para criar os tenants Alpha/Beta."
echo "2. Consulte os tenant_id reais: SELECT slug, id FROM tenants WHERE slug IN ('empresa-alpha','beta-refrigeracao');"
echo "3. Rode ./scripts/apply_test_uuids.sh com os 7 UUIDs reais (5 usuários + 2 tenants) para gerar as"
echo "   cópias prontas para execução dos 12 testes de isolamento."
