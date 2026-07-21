# Changelog

## [Entrega 3] — 2026-07-21

### Segurança
- `tenant_id` **nunca aceito do cliente**: trigger `_sf_set_customer_meta()` SECURITY DEFINER força `tenant_id = current_tenant_id()` em INSERT/UPDATE na tabela `customers`, sobrescrevendo qualquer valor enviado pelo Flutter.
- Tabelas filhas (contacts, addresses, assets): trigger `_sf_set_child_customer_meta()` SECURITY INVOKER faz `SELECT tenant_id FROM customers WHERE id = NEW.customer_id` — se RLS da tabela pai negar acesso, a inserção falha automaticamente (isolamento em cascade).
- RLS habilitado em todas as 4 novas tabelas; deny-by-default; políticas explícitas via `has_permission('customers.read')` / `has_permission('customers.write')`.
- `customers`: sem política DELETE — soft-delete apenas (`is_active = false`).
- Auditoria LGPD: `_sf_audit_customer_change()` SECURITY DEFINER registra eventos `customer.created`/`customer.updated` **sem logar** `document` (CPF/CNPJ) nem `email`.
- ADR-017 decidido: valores monetários em `int` (centavos), sem biblioteca externa no MVP.
- ADR-018 decidido: testes de RLS via arquivos SQL em `test/isolation/` contra instância local Supabase CLI.

### Adicionado

**Supabase / Banco:**
- `supabase/migrations/0002_customers.sql` — tabelas `customers`, `customer_contacts`, `customer_addresses`, `customer_assets`; validação de CPF/CNPJ (regex); validação de 27 UFs brasileiras; índices únicos parciais (document×tenant, is_primary, is_default); triggers de meta + auditoria; RLS completo.
- `supabase/migrations/0002_customers_rollback.sql`.

**Domínio Flutter (`lib/features/customers/domain/`):**
- `customer.dart` — `Customer` (Freezed), `CustomerType` enum (person/company/condominium/publicEntity), `customerFromRow()`, `toInsertPayload()` (omite tenant_id).
- `customer_contact.dart` — `CustomerContact` (Freezed), builders e payload.
- `customer_address.dart` — `CustomerAddress` (Freezed), `kBrazilianStates` (27 UFs), `oneLineAddress`.
- `customer_asset.dart` — `CustomerAsset` (Freezed), `displayName` (corretamente verifica string vazia antes de concatenar).

**Dados Flutter (`lib/features/customers/data/`):**
- `customer_repository.dart` — `CustomerFilter`, `CustomerRepository.listPaged()` (paginação 20/página, heurística de total), `get`, `create`, `update`, `deactivate`, `reactivate`; CRUD completo para contatos, endereços e ativos; `_mapError()` mapeia 23505/42501.

**Aplicação Flutter (`lib/features/customers/application/`):**
- `customer_list_notifier.dart` — `CustomerListState` (items, filter, page, totalCount, isLoading, isLoadingMore, hasMore, isEmpty); `CustomerListNotifier` (load, loadMore, applyFilter, refresh, removeFromList, updateInList); providers `customerListProvider`, `customerDetailProvider`, `customerContactsProvider` (`List<CustomerContact>`), `customerAddressesProvider` (`List<CustomerAddress>`), `customerAssetsProvider` (`List<CustomerAsset>`), `customerRepositoryProvider`.
- `customer_form_notifier.dart` — sealed `CustomerFormState` (Idle/Loading/Success/Error); `CustomerFormNotifier` (createCustomer, updateCustomer, deactivateCustomer, reset); `CustomerContactFormNotifier`; `CustomerAddressFormNotifier`; strip de não-dígitos antes de persistir CPF/CNPJ/fone.

**Apresentação Flutter (`lib/features/customers/presentation/`):**
- `customer_list_screen.dart` — `ConsumerStatefulWidget`, SearchBar, FilterChips por tipo e ativo/inativo, `ListView.separated` com `_CustomerCard`, infinite scroll (ScrollController 200px do fundo → `loadMore()`), FAB → `/clientes/novo`.
- `customer_detail_screen.dart` — `TabController` 3 abas (Dados / Contatos / Endereços); AppBar com PopupMenu (editar / desativar / reativar); `_DataTab` formata CPF/CNPJ/fone; `_ContactsTab` com bottom-sheet de edição; `_AddressesTab` com tela fullscreen de endereço.
- `customer_form_screen.dart` — modo criar/editar (parâmetro `Customer?`); `SegmentedButton<CustomerType>`; campo tradeName visível somente para não-PF; validação CPF ou CNPJ conforme tipo.
- `widgets/customer_type_chip.dart` — `CustomerTypeChip` com cor e ícone por tipo via switch expression.

**Router / Shell:**
- `lib/core/router/app_router.dart` — rotas `/clientes`, `/clientes/novo`, `/clientes/:id`, `/clientes/:id/editar` (extra type-checked: `extra is Customer`).
- `lib/core/widgets/responsive_shell.dart` — destino "Clientes" adicionado à NavigationRail/Bar.

**Testes:**
- `test/customers/customer_form_notifier_test.dart` — 7 casos: estado inicial idle, create success, PermissionError, BusinessRuleError (CPF/CNPJ duplicado), update success, deactivate success, reset; testes de `CustomerType` (usesCpf, fromValue/value, unknown→ArgumentError).
- `test/isolation/0002_rls_customers_test.sql` — 12 testes SQL (T1–T12): isolamento cross-tenant, restrições por role (técnico read-only, viewer read-only), segurança de tabela filha (beta não insere contato em customer do alpha), unicidade de document, is_primary, is_default; geração de audit_log.

### Notas de migração para a E4
- `flutter pub run build_runner build` — obrigatório (gera `.freezed.dart`, `.g.dart`, `.mocks.dart`).
- Aplicar `0002_customers.sql` no Supabase (SQL Editor ou `supabase db push`).
- Substituir UUIDs placeholder em `test/isolation/0002_rls_customers_test.sql` pelos UUIDs reais do seed.
- `flutter test` para validar todos os testes (validators, auth, customers).

---

## [Entrega 2] — 2026-07-21

### Segurança
- `main.dart` reescrito: credenciais hardcoded removidas, substituídas por `EnvConfig` com `--dart-define-from-file`.
- `.gitignore` atualizado: protege `dart_defines/*.json`, `*.env`, arquivos gerados.
- Migration com RLS `ENABLE ROW LEVEL SECURITY` em 11 tabelas; `deny by default`; políticas explícitas mínimas.
- Funções `SECURITY DEFINER` com `SET search_path = public` fixo.
- `audit_logs` com policies que bloqueiam UPDATE e DELETE.
- `AuthNotifier.sendPasswordReset`: mensagem genérica anti-enumeração de usuários.
- `AuthNotifier._mapAuthException`: mapeamento de erros Supabase sem revelar existência de usuário.

### Adicionado
**Flutter:**
- `lib/core/config/env_config.dart` — leitura segura de variáveis via `String.fromEnvironment`.
- `lib/core/theme/` — Material 3 completo (light/dark), AppColors.
- `lib/core/router/app_router.dart` — GoRouter com guard de auth e redirect para criação de empresa.
- `lib/core/widgets/responsive_shell.dart` — NavigationRail (≥600px) e NavigationBar (<600px).
- `lib/core/widgets/app_loading.dart` — SplashScreen e AppLoading.
- `lib/core/widgets/error_view.dart` — ErrorView e EmptyView.
- `lib/core/error/app_error.dart` — AppError sealed class (Auth, Permission, NotFound, Business, Network, Validation, Unexpected).
- `lib/core/utils/validators.dart` — CPF, CNPJ, CEP, e-mail, senha, telefone, slug.
- `lib/features/auth/` — AuthNotifier (Riverpod), LoginScreen, ForgotPasswordScreen, ResetPasswordScreen.
- `lib/features/tenant/` — TenantNotifier, CreateTenantScreen (chama `create_tenant_with_owner`).
- `lib/features/dashboard/` — DashboardScreen placeholder.
- `lib/shared/providers/` — supabase_provider, auth_provider (stream + user + isAuthenticated), tenant_provider (membership, tenant, role).
- `lib/main.dart` — ProviderScope + MaterialApp.router + pt-BR localizations.

**Supabase / Banco:**
- `supabase/migrations/0001_foundation.sql` — 11 tabelas, 4 triggers, 5 funções helper, RLS policies, seed de 12 roles e 24 permissions.
- `supabase/migrations/0001_foundation_rollback.sql`.
- `supabase/seed/dev_seed.sql` — 2 tenants fictícios para testes de isolamento.
- `supabase/config.toml`.

**Testes:**
- `test/auth/validators_test.dart` — 18 casos: email, senha, CPF, CNPJ, slug, CEP, telefone.
- `test/auth/auth_notifier_test.dart` — estado inicial e resetState.
- `test/widgets/login_screen_test.dart` — estrutura, validação de campos, botão desabilitado em loading.
- `test/isolation/rls_isolation_test.sql` — 6 testes de isolamento entre tenants.

**Config:**
- `dart_defines/dev.example.json`, `dart_defines/staging.example.json`.

### Alterado
- `pubspec.yaml` — removido Firebase, auto_route, get_it, injectable, provider, flutter_bloc, easy_localization, flutter_gen_runner, flutter_native_splash, flutter_launcher_icons; adicionado go_router.
- `.gitignore` — adicionada proteção de segredos (dart_defines, .env).
- `lib/app/domain/` e `lib/app/infra/` — marcados como deprecados (substituídos pela estrutura feature-first).

### Notas de migração para a E3
- Rodar `flutter pub get` para regenerar `pubspec.lock`.
- Aplicar `0001_foundation.sql` no Supabase antes de qualquer teste.
- Executar seed após criar usuários de teste no Supabase Auth.

---

## [Entrega 1] — 2026-07-21

### Adicionado
- Documentação de fundação: VISION.md, ARCHITECTURE.md, THREAT_MODEL.md, DATA_MODEL.md, SECURITY.md, ROADMAP.md, DECISIONS.md (ADR-001..016), PROJECT_STATE.md.

Sem código, migrations ou infraestrutura nesta entrega.
