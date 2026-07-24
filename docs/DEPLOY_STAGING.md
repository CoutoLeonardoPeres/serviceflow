# ServiceFlow — Deploy Staging

## Pré-requisitos

- Supabase remoto `Service_Saas` (`pkbluscdssiiumrppmwa`) com migrations `0001` a `0035` aplicadas — **mesmo projeto usado em desenvolvimento** (decisão registrada em 2026-07-24: staging reaproveita o Service_Saas em vez de um projeto Supabase isolado; ver `docs/PROJECT_STATE.md`).
- `dart_defines/staging.json` já criado nesta sessão a partir de `dart_defines/staging.example.json`, reaproveitando a mesma `SUPABASE_URL`/`SUPABASE_ANON_KEY` do `dev.json` (a anon key não é segredo administrativo — é protegida por RLS).
- URL de staging: **`https://cliente.leonardoperescouto.com`**.
- **Antes de publicar**: rode a Fase 1 (`docs/FASE1_RUNBOOK_SEGURANCA_RLS.md`) até o fim. Como staging usa o mesmo banco de dev, os testes de isolamento validam o mesmo ambiente que ficará exposto publicamente.

## Build

```bash
./scripts/build_staging.sh
```

O pacote será criado em:

```text
dist/serviceflow-staging.zip
dist/serviceflow-staging.manifest.txt
```

## Publicação na Hostinger

1. Abra o Gerenciador de Arquivos da Hostinger.
2. Entre na pasta do subdomínio de staging, normalmente `public_html` ou pasta equivalente do subdomínio.
3. Remova arquivos antigos do staging.
4. Envie `dist/serviceflow-staging.zip`.
5. Extraia o `.zip` diretamente dentro da pasta pública.
6. Confirme que `index.html`, `main.dart.js`, `flutter_bootstrap.js`, `assets/` e `.htaccess` ficaram na raiz pública.
7. Guarde `dist/serviceflow-staging.manifest.txt` junto do registro de publicação.

## Smoke Test

Depois de publicar:

```bash
./scripts/smoke_web.sh https://cliente.leonardoperescouto.com
```

Para validar localmente:

```bash
./scripts/smoke_web.sh http://127.0.0.1:8091
```

## Checklist Manual

- Login por e-mail/senha abre normalmente.
- Usuário com empresa ativa entra no dashboard.
- Menu mostra Clientes, Chamados, Agenda, Orçamentos, OS e Financeiro.
- Dashboard mostra resumo financeiro.
- Tela Financeiro abre sem erro.
- OS permite gerar cobrança.
- Recebível permite baixa manual e visualizar recibo.
- Link público de orçamento continua abrindo sem login.

## Rollback

1. Reenviar o `.zip` anterior conhecido como estável.
2. Conferir o SHA-256 pelo manifesto do pacote.
3. Extrair na pasta pública substituindo os arquivos atuais.
4. Rodar `./scripts/smoke_web.sh https://cliente.leonardoperescouto.com`.

As migrations de banco têm rollbacks em `supabase/rollbacks/`, mas rollback de produção deve ser decidido caso a caso para não perder dados operacionais.
