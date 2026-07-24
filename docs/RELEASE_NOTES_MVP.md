# ServiceFlow — Release Notes MVP

## Versão

- Data: 2026-07-22
- Pacote local validado: `dist/serviceflow-staging-dry-run.zip`
- Manifesto: `dist/serviceflow-staging-dry-run.manifest.txt`
- Supabase remoto: `Service_Saas` (`pkbluscdssiiumrppmwa`) — mesmo projeto usado em desenvolvimento e staging
- Migrations aplicadas: `0001` a `0035`
- URL de staging: `https://cliente.leonardoperescouto.com`

## Funcionalidades Entregues

- Autenticação por e-mail e senha.
- Criação de empresa/tenant.
- Dashboard com resumo financeiro mínimo.
- Clientes, contatos, endereços e equipamentos.
- Chamados com categorias, prioridades, histórico e anexos.
- Agenda mensal com popup de agendamento.
- Orçamentos com cálculo server-side, PDF e link público de aprovação.
- OS com conversão de orçamento aprovado, execução, horas, materiais, despesas, evidências, assinatura e aceite.
- Financeiro mínimo com geração de cobrança por OS, baixa manual, recibos numerados e PDF de recibo.
- Tema neomórfico aplicado nas telas e popups principais.

## Validações Locais

- `flutter analyze`
- Testes críticos de dashboard, financeiro, recibo PDF, OS, orçamento e router.
- Build web otimizado.
- Smoke test local em `http://127.0.0.1:8091`.
- Manifesto SHA-256 do pacote gerado.

## Arquivos de Publicação

- `dist/serviceflow-staging-dry-run.zip`
- `dist/serviceflow-staging-dry-run.manifest.txt`

Para gerar o pacote definitivo com credenciais de staging:

```bash
./scripts/build_staging.sh
./scripts/write_release_manifest.sh dist/serviceflow-staging.zip
```

## Pendências Antes de Considerar MVP Aceito

- `dart_defines/staging.json` já criado em 2026-07-24 com credenciais reais de staging.
- Publicar `dist/serviceflow-staging.zip` na Hostinger em `https://cliente.leonardoperescouto.com`.
- Rodar `./scripts/smoke_web.sh https://cliente.leonardoperescouto.com`.
- Executar roteiros SQL de isolamento com usuários reais (ver `docs/FASE1_RUNBOOK_SEGURANCA_RLS.md`).
- Fazer validação manual ponta a ponta: cliente → chamado → agenda → orçamento → link público → aprovação → OS → execução → cobrança → pagamento → recibo.

## Rollback

- Reenviar o último `.zip` estável para a pasta pública da Hostinger.
- Conferir checksum pelo manifesto.
- Rodar smoke test na URL publicada.
