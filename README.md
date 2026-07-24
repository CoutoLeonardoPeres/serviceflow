# ServiceFlow

SaaS Flutter/Supabase para gestão de serviços técnicos em campo: clientes, chamados, agenda, orçamentos, OS, execução, evidências, financeiro mínimo e recibos.

## Rodar Localmente

```bash
flutter pub get
flutter build web --dart-define-from-file=dart_defines/dev.json --no-source-maps --no-wasm-dry-run --pwa-strategy=none
python3 -m http.server 8091 --bind 127.0.0.1 --directory build/web
```

Acesse:

```text
http://127.0.0.1:8091/
```

## Testes

```bash
flutter analyze
flutter test test/dashboard/dashboard_screen_test.dart test/financials/financial_list_screen_test.dart test/financials/receipt_pdf_generator_test.dart
./scripts/smoke_web.sh http://127.0.0.1:8091
```

## Release Check Local

```bash
./scripts/release_check.sh dart_defines/dev.json 8091
```

Esse comando roda análise, testes críticos, build web, smoke test local e preflight de segurança.

## Segurança Pré-Deploy

```bash
./scripts/security_preflight.sh dist/serviceflow-staging.zip --remote
```

Use `--remote` quando quiser confirmar o alinhamento das migrations no Supabase conectado.

## Build Staging

Crie `dart_defines/staging.json` a partir de `dart_defines/staging.example.json` e rode:

```bash
./scripts/build_staging.sh
```

O pacote será gerado em:

```text
dist/serviceflow-staging.zip
dist/serviceflow-staging.manifest.txt
```

Guia completo: `docs/DEPLOY_STAGING.md`.
Notas de release: `docs/RELEASE_NOTES_MVP.md`.

## Documentacao Principal

- `docs/DOCS_INDEX.md` — indice de documentacao.
- `docs/SYSTEM_MANUAL.md` — manual funcional e operacional do sistema.
- `docs/SQL_MANUAL.md` — manual SQL/Supabase para recriar banco, RLS, Storage e validacoes.
- `docs/RECREATE_PROMPT.md` — prompt mestre para recriar o ServiceFlow do zero.
- `docs/PROJECT_STATE.md` — estado atual, entregas, pendencias e estrutura.

## Supabase

Migrations aplicadas no remoto `Service_Saas`: `0001` a `0013`.

Scripts SQL manuais de isolamento ficam em `test/isolation/` e exigem usuários/UUIDs reais antes da execução.
