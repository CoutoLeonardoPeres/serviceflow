# ServiceFlow — Release Check MVP

## Comando

```bash
./scripts/release_check.sh dart_defines/dev.json 8091
```

## O que valida

1. Dependências Flutter.
2. Análise estática.
3. Testes críticos:
   - dashboard;
   - financeiro;
   - recibo PDF;
   - detalhe da OS;
   - detalhe do orçamento;
   - redirecionamento do router.
4. Build web otimizado.
5. Inclusão do `.htaccess` no build.
6. Smoke test HTTP local.
7. Preflight de segurança:
   - arquivos de ambiente ignorados;
   - busca de chaves administrativas;
   - bundle sem arquivos de ambiente;
   - pacote sem segredos e com arquivos principais;
   - rollbacks de migrations;
   - alinhamento remoto opcional de migrations.

## Último Resultado

Executado em 2026-07-22 com sucesso contra:

```text
http://127.0.0.1:8091
```

Resultado:

```text
OK: release check concluido para http://127.0.0.1:8091
```

Também executado com sucesso:

```bash
./scripts/security_preflight.sh dist/serviceflow-staging-dry-run.zip --remote
```

## Backup/Restore — Validação

Script: `scripts/validate_backup.sh`

### Pré-requisitos

```bash
export SUPABASE_DB_URL="postgresql://postgres:<senha>@db.<projeto>.supabase.co:5432/postgres"
```

### Executar apenas dump (validação rápida)

```bash
./scripts/validate_backup.sh
```

Verifica: pg_dump bem-sucedido, tabelas críticas presentes, ausência de segredos no dump, SHA-256 no manifesto.

### Executar com restore em banco de destino (validação completa)

```bash
export RESTORE_DB_URL="postgresql://postgres:<senha>@localhost:5432/serviceflow_restore"
./scripts/validate_backup.sh --restore
```

Verifica: restore sem erros, contagens de tenants/customers/audit_logs pós-restore.

### Artefatos gerados

- `dist/backup-<data>.sql` — dump completo do schema `public`
- `dist/backup-<data>.manifest.txt` — SHA-256, tamanho, tabelas verificadas e contagens pós-restore

### Cadência recomendada para MVP

| Fase | Frequência | Responsável |
|---|---|---|
| Pré-deploy | Manual, antes de qualquer release | Dev/ops |
| Produção | Backup automático via Supabase Dashboard (Point-in-time recovery) | Supabase |
| Validação do restore | Mensal ou antes de migrações estruturais | Dev/ops |

> **Nota**: O Supabase Pro habilita Point-in-Time Recovery (PITR) com retenção de 7 dias. No plano gratuito, use o Scheduled Backup manual via SQL Editor ou pg_dump agendado com cron.

## Pendente Externo

- Publicar o pacote na Hostinger em `https://serviceflow.leonardoperescouto.com`.
- Rodar `./scripts/smoke_web.sh https://serviceflow.leonardoperescouto.com` contra a URL real.
- Executar os roteiros SQL de isolamento com usuários reais (ver `docs/FASE1_RUNBOOK_SEGURANCA_RLS.md`).
- Executar `./scripts/validate_backup.sh` com `SUPABASE_DB_URL` real antes do go-live.
