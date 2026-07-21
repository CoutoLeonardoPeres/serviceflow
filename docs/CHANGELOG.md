# Changelog

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
