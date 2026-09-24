# ServiceFlow — Indice de Documentacao

Ultima atualizacao: 2026-07-22

Este indice aponta os documentos que devem ser usados para entender, manter, publicar ou reconstruir o ServiceFlow.

## Reconstrucao do sistema

- `docs/RECREATE_PROMPT.md` — prompt mestre para recriar o produto inteiro com outro agente/Codex.
- `docs/SYSTEM_MANUAL.md` — manual funcional e operacional do sistema.
- `docs/SQL_MANUAL.md` — manual de banco, Supabase, migrations, RLS, Storage e validacoes SQL.
- `docs/PROJECT_STATE.md` — estado atual do projeto, entregas implementadas e pendencias.

## Produto e arquitetura

- `docs/DELIVERY_1.md` — visao, escopo do MVP, personas, backlog, criterios de aceite e plano de entregas.
- `docs/VISION.md` — visao geral do produto.
- `docs/ARCHITECTURE.md` — arquitetura tecnica.
- `docs/DATA_MODEL.md` — modelo de dados de referencia.
- `docs/DECISIONS.md` — ADRs e decisoes tecnicas.
- `docs/ROADMAP.md` — entregas planejadas e status.

## Seguranca

- `docs/SECURITY.md` — principios e controles de seguranca.
- `docs/THREAT_MODEL.md` — modelo de ameacas.
- `docs/SQL_MANUAL.md` — detalhes praticos de RLS, isolamento multi-tenant e politicas de Storage.

## Deploy e release

- `docs/DEPLOY_STAGING.md` — passo a passo de publicacao em staging/Hostinger.
- `docs/MVP_RELEASE_CHECK.md` — checklist do release MVP.
- `docs/RELEASE_NOTES_MVP.md` — notas de release do MVP.
- `docs/CHANGELOG.md` — historico de entregas.

## Integracoes operacionais

- `docs/EMAIL_SMTP_SETUP.md` — remetente de recuperacao de senha, Hostinger, Supabase e teste de aceite.

## Regra de manutencao

Sempre que uma nova tela, tabela, migration, regra de negocio, permissao, script de deploy ou fluxo principal for alterado, atualize tambem:

1. `docs/PROJECT_STATE.md`
2. `docs/SYSTEM_MANUAL.md`
3. `docs/SQL_MANUAL.md`, quando houver mudanca no banco
4. `docs/RECREATE_PROMPT.md`, quando a mudanca for necessaria para recriar o sistema
5. `docs/CHANGELOG.md`
