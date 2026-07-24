# ServiceFlow — Deploy Staging

## Pré-requisitos

- Supabase remoto com migrations `0001` a `0013` aplicadas.
- `dart_defines/staging.json` criado a partir de `dart_defines/staging.example.json`.
- URL de staging definida, por exemplo `https://staging.seudominio.com`.

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
./scripts/smoke_web.sh https://staging.seudominio.com
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
4. Rodar `./scripts/smoke_web.sh <url-staging>`.

As migrations de banco têm rollbacks em `supabase/rollbacks/`, mas rollback de produção deve ser decidido caso a caso para não perder dados operacionais.
