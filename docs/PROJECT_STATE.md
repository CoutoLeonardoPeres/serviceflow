# ServiceFlow — Estado do Projeto

**Última atualização:** 2026-07-21 · **Entrega atual concluída:** 3 (Clientes)

## Status

| Item | Estado |
|---|---|
| Fase | F1 — Clientes implementado |
| Código Flutter | ✅ features/customers completo (list, detail, form, contatos, endereços, ativos) |
| Migrations | ✅ 0001_foundation + 0002_customers disponíveis |
| Ambientes | ⏳ Requer `dart_defines/dev.json` com credenciais reais |
| Build runner | ⏳ `flutter pub run build_runner build` obrigatório antes de compilar (Freezed) |
| Testes Flutter | ✅ validators_test, login_screen_test, customer_form_notifier_test |
| Testes SQL | ✅ rls_isolation_test.sql + 0002_rls_customers_test.sql |
| Git | ⏳ Commit pendente (`rm .git/index.lock` no terminal, depois `git add -A && git commit`) |
| Deploy | ⏳ Staging não configurado ainda (Entrega 8) |

## Estrutura do repositório

```
serviceflow/
  lib/
    main.dart
    core/
      config/env_config.dart
      theme/                         — Material 3, AppColors
      router/app_router.dart         — GoRouter + rotas /clientes/**
      widgets/                       — responsive_shell (+ nav Clientes), app_loading, error_view
      error/app_error.dart
      utils/validators.dart          — CPF, CNPJ, CEP, e-mail, senha, slug, fone
    features/
      auth/                          — login, forgot_password, reset_password + AuthNotifier
      tenant/                        — create_tenant_screen + TenantNotifier
      dashboard/                     — DashboardScreen (placeholder)
      customers/
        domain/
          customer.dart              — Customer (Freezed) + CustomerType enum
          customer_contact.dart      — CustomerContact (Freezed)
          customer_address.dart      — CustomerAddress (Freezed) + kBrazilianStates
          customer_asset.dart        — CustomerAsset (Freezed)
        data/
          customer_repository.dart   — CRUD + listPaged + getContacts/getAddresses/getAssets
        application/
          customer_list_notifier.dart  — CustomerListNotifier + providers (detail, contacts, addresses, assets)
          customer_form_notifier.dart  — CustomerFormNotifier + ContactFormNotifier + AddressFormNotifier
        presentation/
          customer_list_screen.dart    — lista com busca + filtros tipo/ativo + infinite scroll
          customer_detail_screen.dart  — tabs: Dados | Contatos | Endereços
          customer_form_screen.dart    — criar/editar cliente
          widgets/customer_type_chip.dart
    shared/providers/                — supabase, auth, tenant providers (Riverpod)
  supabase/
    migrations/
      0001_foundation.sql            — 11 tabelas identidade/tenancy, RLS, funções, seed roles/permissions
      0001_foundation_rollback.sql
      0002_customers.sql             — customers, contacts, addresses, assets; triggers; auditoria; RLS
      0002_customers_rollback.sql
    seed/dev_seed.sql                — 2 tenants fictícios (substituir UUIDs reais)
    config.toml
  dart_defines/
    dev.example.json
    staging.example.json
  docs/                              — 9 documentos de arquitetura
  test/
    auth/validators_test.dart
    auth/auth_notifier_test.dart
    customers/customer_form_notifier_test.dart
    isolation/rls_isolation_test.sql
    isolation/0002_rls_customers_test.sql
    widgets/login_screen_test.dart
```

## Próximos passos obrigatórios (antes de iniciar Entrega 4)

1. **Credenciais**: copiar `dart_defines/dev.example.json` → `dart_defines/dev.json` e preencher.
2. **Migrations**: aplicar `0001_foundation.sql` e `0002_customers.sql` no Supabase (SQL editor ou `supabase db push`).
3. **Seed**: criar usuários de teste no Supabase Auth; atualizar UUIDs em `dev_seed.sql`; executar seed.
4. **`flutter pub get`**: gera `pubspec.lock` atualizado.
5. **`flutter pub run build_runner build`**: gera `*.freezed.dart` e `*.g.dart` para os modelos de domínio.
6. **Commit**: `rm .git/index.lock` (terminal Mac) → `git add -A && git commit -m "feat: E3 — módulo clientes"`.
7. **Testes Flutter**: `flutter test` — deve passar todos os testes (validators, auth, customers).
8. **Testes SQL isolamento**: `psql $DB_URL -f test/isolation/0002_rls_customers_test.sql` (substituir UUIDs antes).
9. **Verificação manual**: criar um cliente PF e um PJ, adicionar contato e endereço, verificar auditoria em `audit_logs`.

## Próxima entrega (E4) — Chamados

`service_requests`, `service_categories`, `service_priorities`, histórico de status, anexos (Storage + policies), atribuição, filtros server-side, testes. Depende do módulo Clientes.

## ADRs ativos

ADR-001..018 registrados (ver DECISIONS.md). ADR-017 (decimal): usar `int` em centavos no MVP, reavaliar em E6. ADR-018 (testes RLS): SQL local via Supabase CLI. ADR-019 e ADR-020 pendentes para E6/F3.
