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

## Pendente Externo

- Publicar o pacote na Hostinger em `https://cliente.leonardoperescouto.com`.
- Rodar `./scripts/smoke_web.sh https://cliente.leonardoperescouto.com` contra a URL real.
- Executar os roteiros SQL de isolamento com usuários reais (ver `docs/FASE1_RUNBOOK_SEGURANCA_RLS.md`).
