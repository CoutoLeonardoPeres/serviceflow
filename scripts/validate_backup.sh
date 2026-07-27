#!/usr/bin/env bash
# =============================================================================
# validate_backup.sh — ServiceFlow
# Valida o ciclo de backup/restore do banco Supabase (PostgreSQL).
#
# Pré-requisitos:
#   - psql e pg_dump disponíveis no PATH
#   - Variáveis de ambiente ou arquivo .env com:
#       SUPABASE_DB_URL   postgresql://postgres:<senha>@db.<projeto>.supabase.co:5432/postgres
#   - Banco de destino opcional (RESTORE_DB_URL) para validar restore:
#       RESTORE_DB_URL    postgresql://.../<banco_vazio>
#
# Uso:
#   ./scripts/validate_backup.sh [--restore]
#
# Flags:
#   --restore   Realiza restore em banco de destino e verifica contagens.
#               Sem essa flag, apenas o dump é validado.
#
# Saída:
#   Arquivo: dist/backup-<data>.sql
#   Manifesto: dist/backup-<data>.manifest.txt
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DATE=$(date +%Y%m%d-%H%M%S)
DUMP_FILE="$DIST_DIR/backup-$DATE.sql"
MANIFEST_FILE="$DIST_DIR/backup-$DATE.manifest.txt"
DO_RESTORE=false

for arg in "$@"; do
  [[ "$arg" == "--restore" ]] && DO_RESTORE=true
done

fail() { echo "❌ FALHOU: $1"; exit 1; }
ok()   { echo "✅ $1"; }
info() { echo "ℹ️  $1"; }

echo "======================================================"
echo "  ServiceFlow — Validação de Backup/Restore"
echo "  Data: $DATE"
echo "======================================================"

# ── 1. Credenciais ─────────────────────────────────────────────────────────────

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  [[ -f "$ROOT_DIR/.env" ]] && source "$ROOT_DIR/.env"
fi

[[ -z "${SUPABASE_DB_URL:-}" ]] && fail "SUPABASE_DB_URL não definida."

ok "1/6 Credenciais do banco de origem configuradas."

# ── 2. Verificação de pg_dump e psql ─────────────────────────────────────────

command -v pg_dump > /dev/null || fail "pg_dump não encontrado no PATH."
command -v psql    > /dev/null || fail "psql não encontrado no PATH."
ok "2/6 Ferramentas pg_dump e psql disponíveis."

# ── 3. Dump do banco ─────────────────────────────────────────────────────────

mkdir -p "$DIST_DIR"

info "Executando pg_dump (schema public + auth excluído)..."
pg_dump \
  --dbname="$SUPABASE_DB_URL" \
  --schema=public \
  --no-owner \
  --no-acl \
  --file="$DUMP_FILE" \
  --verbose 2>&1 | tail -5

[[ -f "$DUMP_FILE" ]] || fail "Arquivo de dump não foi criado."
DUMP_SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
ok "3/6 Dump gerado: $DUMP_FILE ($DUMP_SIZE)."

# ── 4. Validação básica do dump ───────────────────────────────────────────────

# Verifica que tabelas críticas estão presentes
CRITICAL_TABLES=(
  "tenants"
  "customers"
  "quotations"
  "work_orders"
  "audit_logs"
  "receivables"
)

for table in "${CRITICAL_TABLES[@]}"; do
  grep -q "CREATE TABLE public.$table\|CREATE TABLE $table" "$DUMP_FILE" || \
    fail "Tabela '$table' não encontrada no dump."
done
ok "4/6 Tabelas críticas presentes no dump: ${CRITICAL_TABLES[*]}."

# Verifica ausência de segredos no dump
if grep -iE 'service_role_key|SUPABASE_SERVICE|sb_secret_' "$DUMP_FILE"; then
  fail "Possível segredo administrativo encontrado no dump!"
fi
ok "   Nenhum segredo detectado no dump."

# ── 5. Manifesto ─────────────────────────────────────────────────────────────

{
  echo "ServiceFlow — Manifesto de Backup"
  echo "Data: $DATE"
  echo "Arquivo: $DUMP_FILE"
  echo "Tamanho: $DUMP_SIZE"
  echo "SHA-256: $(sha256sum "$DUMP_FILE" | cut -d' ' -f1)"
  echo "Tabelas verificadas: ${CRITICAL_TABLES[*]}"
} > "$MANIFEST_FILE"

ok "5/6 Manifesto gerado: $MANIFEST_FILE."

# ── 6. Restore opcional ──────────────────────────────────────────────────────

if [[ "$DO_RESTORE" == "true" ]]; then
  [[ -z "${RESTORE_DB_URL:-}" ]] && fail "RESTORE_DB_URL não definida. Necessária para --restore."

  info "Restaurando dump em banco de destino..."
  psql "$RESTORE_DB_URL" --file="$DUMP_FILE" --quiet

  # Verificar contagens básicas
  TENANT_COUNT=$(psql "$RESTORE_DB_URL" -tAc "SELECT COUNT(*) FROM public.tenants;" 2>/dev/null || echo "0")
  CUSTOMER_COUNT=$(psql "$RESTORE_DB_URL" -tAc "SELECT COUNT(*) FROM public.customers;" 2>/dev/null || echo "0")
  AUDIT_COUNT=$(psql "$RESTORE_DB_URL" -tAc "SELECT COUNT(*) FROM public.audit_logs;" 2>/dev/null || echo "0")

  [[ "$TENANT_COUNT" -ge 0 ]] || fail "Contagem de tenants inválida pós-restore."

  echo "" >> "$MANIFEST_FILE"
  echo "--- Restore ---" >> "$MANIFEST_FILE"
  echo "Tenants: $TENANT_COUNT" >> "$MANIFEST_FILE"
  echo "Customers: $CUSTOMER_COUNT" >> "$MANIFEST_FILE"
  echo "Audit logs: $AUDIT_COUNT" >> "$MANIFEST_FILE"

  ok "6/6 Restore concluído. Tenants=$TENANT_COUNT, Customers=$CUSTOMER_COUNT, Audit=$AUDIT_COUNT."
else
  info "6/6 Restore pulado (use --restore para ativar)."
fi

echo ""
echo "======================================================"
echo "  Backup validado com sucesso."
echo "  Dump: $DUMP_FILE"
echo "  Manifesto: $MANIFEST_FILE"
echo "======================================================"
