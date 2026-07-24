# Fase 2 — Runbook de Publicação em Staging

**Preparado em:** 2026-07-24 · **Objetivo:** publicar o MVP em `https://cliente.leonardoperescouto.com`, rodar smoke test contra a URL real e confirmar que o app funciona em ambiente candidato a produção.

**Dependência:** Fase 1 (`docs/FASE1_RUNBOOK_SEGURANCA_RLS.md`) concluída — isolamento entre tenants validado. Como o staging reaproveita o mesmo projeto Supabase `Service_Saas` usado em desenvolvimento (decisão registrada nesta sessão), qualquer falha de isolamento na Fase 1 afeta diretamente o que ficará exposto publicamente aqui. **Não pule essa dependência.**

Assim como na Fase 1, este runbook foi preparado sem poder ser executado no sandbox de análise: falta Flutter SDK, e o processo de publicação na Hostinger é manual (Gerenciador de Arquivos via navegador), fora do alcance de qualquer terminal.

---

## Decisões registradas nesta sessão

| Decisão | Valor |
|---|---|
| Projeto Supabase de staging | Mesmo projeto de dev: `Service_Saas` (`pkbluscdssiiumrppmwa`) |
| URL de staging | `https://cliente.leonardoperescouto.com` |
| `dart_defines/staging.json` | Já criado nesta sessão (gitignored), com a mesma `SUPABASE_URL`/`SUPABASE_ANON_KEY` do `dev.json` e `APP_ENV=staging` |

---

## T2.1 — Credenciais de staging ✅ já preparado

`dart_defines/staging.json` já existe no repositório (não commitado, protegido pelo `.gitignore`). Nenhuma ação necessária, a menos que você queira usar um domínio de checkout/billing diferente — nesse caso, edite os campos `CHECKOUT_*_URL` e `BILLING_PORTAL_URL` antes do build.

Confirme que o arquivo está correto:

```bash
cat dart_defines/staging.json
```

---

## T2.2 — Build staging

Na sua máquina local (com Flutter instalado):

```bash
flutter pub get
flutter pub run build_runner build
./scripts/build_staging.sh
```

Isso gera:

```text
dist/serviceflow-staging.zip
dist/serviceflow-staging.manifest.txt
```

Confirme o conteúdo do pacote antes de publicar:

```bash
unzip -l dist/serviceflow-staging.zip | grep -E "index.html|main.dart.js|flutter_bootstrap.js|.htaccess"
```

Os 4 arquivos devem aparecer na raiz do zip (não dentro de subpasta).

---

## T2.3 — Publicar na Hostinger

Processo manual via Gerenciador de Arquivos (não há FTP/SSH automatizado neste fluxo):

1. Acesse o painel da Hostinger → **Gerenciador de Arquivos**.
2. Entre na pasta pública do subdomínio `cliente.leonardoperescouto.com` (geralmente `public_html/cliente` ou uma pasta dedicada ao subdomínio — confira em **Domínios > Subdomínios** qual é o diretório raiz configurado).
3. **Antes de sobrescrever**: se já houver uma versão anterior publicada, baixe/backup a pasta atual (zip) por segurança, ou anote a versão/manifesto anterior.
4. Remova os arquivos antigos da pasta pública (mantendo eventuais arquivos de configuração do provedor, se houver).
5. Faça upload de `dist/serviceflow-staging.zip`.
6. Extraia o `.zip` diretamente dentro da pasta pública (não dentro de uma subpasta `serviceflow-staging/`).
7. Confirme que ficaram na raiz pública: `index.html`, `main.dart.js`, `flutter_bootstrap.js`, `assets/`, `.htaccess`.
8. Guarde `dist/serviceflow-staging.manifest.txt` (checksum SHA-256) junto do registro de publicação — ele é a referência para rollback.

---

## T2.4 — Smoke test remoto

Após a publicação, rode da sua máquina local:

```bash
./scripts/smoke_web.sh https://cliente.leonardoperescouto.com
```

O script confirma: homepage retorna 200, contém "ServiceFlow", referencia `flutter_bootstrap.js`, os assets principais (`main.dart.js`, `FontManifest.json`, `manifest.json`) carregam, e a rota `/#/login` responde 200.

Saída esperada: `OK: app web responde e assets principais carregam.`

Se algo falhar, verifique primeiro se o `.htaccess` foi realmente publicado (ele é o que garante que `/#/login` e outras rotas do Flutter Router funcionem sem erro 404 — SPA routing).

---

## T2.5 — Backup do banco e checklist DNS/HTTPS

### Backup do banco (antes de expor publicamente)

```bash
supabase link --project-ref pkbluscdssiiumrppmwa
supabase db dump -f "staging_db_backup_$(date +%Y%m%d_%H%M%S).sql"
```

Guarde esse dump em local seguro fora do repositório (ele pode conter dados reais de clientes se você já estiver usando o projeto em produção informal — **não commitar**).

### Checklist DNS/HTTPS

- [ ] `https://cliente.leonardoperescouto.com` resolve para o IP da Hostinger (`dig cliente.leonardoperescouto.com` ou `nslookup`)
- [ ] Certificado HTTPS válido (cadeado no navegador, sem aviso de certificado)
- [ ] Redirect automático de `http://` para `https://` está ativo
- [ ] Subdomínio não está listado como "em construção" ou com página padrão da Hostinger

---

## Checklist manual funcional (após publicar)

Reaproveitado de `docs/DEPLOY_STAGING.md`:

- [ ] Login por e-mail/senha abre normalmente
- [ ] Usuário com empresa ativa entra no dashboard
- [ ] Menu mostra Clientes, Chamados, Agenda, Orçamentos, OS e Financeiro
- [ ] Dashboard mostra resumo financeiro
- [ ] Tela Financeiro abre sem erro
- [ ] OS permite gerar cobrança
- [ ] Recebível permite baixa manual e visualizar recibo
- [ ] Link público de orçamento continua abrindo sem login

---

## Checklist de saída da Fase 2

- [ ] `dart_defines/staging.json` confirmado
- [ ] Build staging gerado (`dist/serviceflow-staging.zip` + manifesto)
- [ ] Pacote publicado em `https://cliente.leonardoperescouto.com`
- [ ] `smoke_web.sh` retornou OK contra a URL real
- [ ] Backup do banco realizado e guardado fora do repositório
- [ ] DNS/HTTPS confirmados
- [ ] Checklist manual funcional passou

Quando todos os itens acima estiverem ✅, a Fase 2 está concluída e o projeto pode avançar para a **Fase 3 (validação comercial ponta a ponta)**.

## Rollback

1. Reenviar o `.zip` anterior conhecido como estável (backup feito no passo 3 de T2.3).
2. Conferir o SHA-256 pelo manifesto do pacote.
3. Extrair na pasta pública substituindo os arquivos atuais.
4. Rodar `./scripts/smoke_web.sh https://cliente.leonardoperescouto.com`.

As migrations de banco têm rollbacks em `supabase/rollbacks/`, mas como staging usa o mesmo projeto Supabase de dev, qualquer rollback de banco deve ser decidido com cautela para não perder dados operacionais reais.
