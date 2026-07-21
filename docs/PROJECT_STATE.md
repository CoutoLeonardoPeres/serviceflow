# ServiceFlow — Estado do Projeto

**Última atualização:** 2026-07-21 · **Entrega atual concluída:** 2 (Fundação Técnica)

## Status

| Item | Estado |
|---|---|
| Fase | 0 — fundação concluída |
| Código Flutter | ✅ Estrutura feature-first criada |
| Migrations | ✅ 0001_foundation aplicável |
| Ambientes | ⏳ Requer `dart_defines/dev.json` com credenciais reais |
| Testes Flutter | ✅ validators_test.dart, login_screen_test.dart |
| Testes SQL | ✅ rls_isolation_test.sql (rodar após seed) |
| Git | ⏳ Commit pendente (index.lock macOS — rodar do terminal) |
| Deploy | ⏳ Staging não configurado ainda (Entrega 8) |

## Estrutura do repositório

```
serviceflow/
  lib/
    main.dart                        — entry point, EnvConfig + Supabase.initialize
    core/config/env_config.dart      — lê SUPABASE_URL e SUPABASE_ANON_KEY via dart-define
    core/theme/                      — Material 3, AppColors
    core/router/app_router.dart      — GoRouter + guard auth/tenant
    core/widgets/                    — responsive_shell, app_loading, error_view
    core/error/app_error.dart        — AppError sealed class
    core/utils/validators.dart       — CPF, CNPJ, CEP, e-mail, senha, slug, fone
    features/auth/                   — login, forgot_password, reset_password + AuthNotifier
    features/tenant/                 — create_tenant_screen + TenantNotifier
    features/dashboard/              — DashboardScreen (placeholder)
    shared/providers/                — supabase, auth, tenant providers (Riverpod)
  supabase/
    migrations/0001_foundation.sql   — 11 tabelas, RLS, funções, seed de roles/permissions
    migrations/0001_foundation_rollback.sql
    seed/dev_seed.sql                — 2 tenants fictícios (substituir UUIDs)
    config.toml                      — config Supabase CLI
  dart_defines/
    dev.example.json                 — template (copiar para dev.json e preencher)
    staging.example.json
  docs/                              — 9 documentos de arquitetura
  test/
    auth/validators_test.dart
    auth/auth_notifier_test.dart
    isolation/rls_isolation_test.sql
    widgets/login_screen_test.dart
```

## Próximos passos obrigatórios (antes de iniciar Entrega 3)

1. **Credenciais**: copiar `dart_defines/dev.example.json` → `dart_defines/dev.json` e preencher com URL e anon key do seu projeto Supabase.
2. **Migration**: aplicar `supabase/migrations/0001_foundation.sql` no Supabase (SQL editor ou `supabase db push`).
3. **Seed**: criar 3 usuários de teste no Supabase Auth; atualizar UUIDs em `supabase/seed/dev_seed.sql`; executar seed.
4. **`flutter pub get`**: rodar na pasta do projeto para gerar o novo `pubspec.lock` (dependências foram limpas).
5. **Commit**: resolver o `index.lock` e commitar (ou `rm .git/index.lock` no terminal Mac).
6. **Testes Flutter**: `flutter test` — deve passar validators e login_screen tests.
7. **Testes SQL**: executar `test/isolation/rls_isolation_test.sql` via psql/Supabase CLI.
8. **⚠️ SEGURANÇA**: se o `main.dart` antigo (com credenciais hardcoded) foi versionado em algum outro repo, rotacione imediatamente a anon key no painel Supabase.

## Próxima entrega (E3) — Clientes

Cadastro de clientes (PF/PJ/condomínio), contatos, endereços. RBAC aplicado por role. Auditoria de criação/edição. Validações BR (CPF/CNPJ/CEP). Interface com listagem/filtros server-side e formulário em steps.

## Premissas e ADRs ativos

Ver VISION.md §8 e DECISIONS.md. ADR-017 (decimal) e ADR-018 (testes RLS) permanecem em aberto — ambos podem ser decididos ao iniciar a E3.
