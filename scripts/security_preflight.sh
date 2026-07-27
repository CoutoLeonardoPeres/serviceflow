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
# rg (ripgrep) nem sempre esta instalado — se o comando nao existir, "if rg
# ..." falha com "command not found" e o if trata isso como "nao achou nada",
# pulando a varredura inteira em silencio e ainda reportando OK. grep -r e
# universal no macOS/Linux, sem depender de instalar nada.
#
# O regex casa o FORMATO de uma chave real (JWT de tres blocos, ou o prefixo
# novo sb_secret_), nao o NOME da variavel. .dart_tool e cache de build local
# (gitignored, nao e o que vai publicado — o bundle publicado e checado a
# parte no passo 3/6) e so gera ruido aqui.
#
# JWT sozinho nao basta: a anon key TAMBEM e um JWT de tres blocos, e ela e
# pública por design (protegida por RLS, e para isso que existe). Só a
# service_role e o segredo de verdade. Decodifica o payload de cada match e
# só falha se o claim "role" for service_role.
JWT_HITS="$(grep -rnoE --exclude-dir=build --exclude-dir=dist --exclude-dir=.git \
  --exclude-dir=.dart_tool --exclude=security_preflight.sh \
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' . 2>/dev/null || true)"
SB_SECRET_HITS="$(grep -rnE --exclude-dir=build --exclude-dir=dist --exclude-dir=.git \
  --exclude-dir=.dart_tool --exclude=security_preflight.sh \
  'sb_secret_[A-Za-z0-9_-]{10,}' . 2>/dev/null || true)"

FOUND_SECRET=0
if [[ -n "$JWT_HITS" ]]; then
  while IFS=: read -r file line jwt; do
    payload_b64="$(cut -d. -f2 <<<"$jwt" | tr '_-' '/+')"
    pad=$(( (4 - ${#payload_b64} % 4) % 4 ))
    payload="$(printf '%s%*s' "$payload_b64" "$pad" '' | tr ' ' '=' | openssl base64 -d -A 2>/dev/null || true)"
    if grep -qE '"role"[[:space:]]*:[[:space:]]*"service_role"' <<<"$payload"; then
      echo "$file:$line: JWT com role service_role"
      FOUND_SECRET=1
    fi
  done <<<"$JWT_HITS"
fi
if [[ -n "$SB_SECRET_HITS" ]]; then
  echo "$SB_SECRET_HITS"
  FOUND_SECRET=1
fi
[[ "$FOUND_SECRET" == "1" ]] && fail "possivel segredo administrativo encontrado"

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
  grep -qE "0013[[:space:]]+\\|[[:space:]]+0013" /tmp/serviceflow-migration-list.txt ||
    fail "migration 0013 nao aparece alinhada no remoto"
else
  echo "Cheque remoto pulado. Use --remote para validar Supabase."
fi

echo "OK: security preflight concluido."
