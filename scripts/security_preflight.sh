#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_PATH="${1:-}"
REMOTE_CHECK="${2:---skip-remote}"

cd "$ROOT_DIR"

fail() {
  echo "FALHOU: $1"
  exit 1
}

echo "Security preflight ServiceFlow"

echo "1/6 Arquivos de ambiente ignorados"
git check-ignore -q dart_defines/dev.json ||
  fail "dart_defines/dev.json nao esta protegido pelo .gitignore"
git check-ignore -q dart_defines/staging.json ||
  fail "dart_defines/staging.json nao esta protegido pelo .gitignore"

echo "2/6 Busca de chaves administrativas"
if rg -n --hidden --glob '!build/**' --glob '!dist/**' --glob '!.git/**' --glob '!scripts/security_preflight.sh' \
  'SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY|sb_secret_[A-Za-z0-9_-]+|service_role\\s*[:=]\\s*["'\''][^"'\'']+' .; then
  fail "possivel segredo administrativo encontrado"
fi

echo "3/6 Bundle web sem arquivos de ambiente"
[[ -d build/web ]] || fail "build/web nao existe"
if find build/web -type f \( -name '*.env' -o -name '*staging*.json' -o -name '*dev*.json' \) | grep -q .; then
  fail "arquivo de ambiente encontrado em build/web"
fi

echo "4/6 Pacote de publicacao"
if [[ -n "$PACKAGE_PATH" ]]; then
  [[ -f "$PACKAGE_PATH" ]] || fail "pacote informado nao existe: $PACKAGE_PATH"
  ZIP_CONTENTS="$(zipinfo -1 "$PACKAGE_PATH")"
  if grep -E '(^|/)(dart_defines|\.env|.*dev\.json|.*staging\.json)$' <<<"$ZIP_CONTENTS" >/dev/null; then
    fail "pacote contem arquivo de ambiente"
  fi
  grep -q '^index.html$' <<<"$ZIP_CONTENTS" ||
    fail "pacote nao contem index.html na raiz"
  grep -q '^main.dart.js$' <<<"$ZIP_CONTENTS" ||
    fail "pacote nao contem main.dart.js na raiz"
  grep -q '^\.htaccess$' <<<"$ZIP_CONTENTS" ||
    fail "pacote nao contem .htaccess na raiz"
else
  echo "Pacote nao informado; pulando inspecao de zip."
fi

echo "5/6 Rollbacks para migrations novas"
for migration in supabase/migrations/*.sql; do
  version="$(basename "$migration" .sql)"
  [[ "$version" == "0001_foundation" || "$version" == "0002_customers" ]] && continue
  rollback="supabase/rollbacks/${version}_rollback.sql"
  [[ -f "$rollback" ]] || fail "rollback ausente: $rollback"
done

echo "6/6 Historico remoto de migrations"
if [[ "$REMOTE_CHECK" == "--remote" ]]; then
  supabase migration list | tee /tmp/serviceflow-migration-list.txt
  rg -q "0013\\s+\\|\\s+0013" /tmp/serviceflow-migration-list.txt ||
    fail "migration 0013 nao aparece alinhada no remoto"
else
  echo "Cheque remoto pulado. Use --remote para validar Supabase."
fi

echo "OK: security preflight concluido."
