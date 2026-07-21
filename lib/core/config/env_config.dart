// ignore_for_file: do_not_use_environment
// Razão: é a única forma correta de ler --dart-define em Flutter.
// Valores vêm de dart_defines/dev.json (nunca do código).

enum AppEnvironment { development, staging, production }

class EnvConfig {
  EnvConfig._();

  // ── Supabase ────────────────────────────────────────────────────────────────
  /// URL pública do projeto Supabase (ex: https://abcd.supabase.co).
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Anon/publishable key — segura para uso no cliente. NÃO é a service_role.
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  // ── Ambiente ────────────────────────────────────────────────────────────────
  static const String _envString =
      String.fromEnvironment('APP_ENV', defaultValue: 'development');

  static AppEnvironment get environment {
    switch (_envString) {
      case 'production':
        return AppEnvironment.production;
      case 'staging':
        return AppEnvironment.staging;
      default:
        return AppEnvironment.development;
    }
  }

  static bool get isDevelopment =>
      environment == AppEnvironment.development;
  static bool get isProduction =>
      environment == AppEnvironment.production;

  // ── Validação na inicialização ──────────────────────────────────────────────
  static void validate() {
    final errors = <String>[];
    if (supabaseUrl.isEmpty) {
      errors.add('SUPABASE_URL não configurada.');
    }
    if (supabaseAnonKey.isEmpty) {
      errors.add('SUPABASE_ANON_KEY não configurada.');
    }
    if (!supabaseUrl.startsWith('https://') && !isDevelopment) {
      errors.add('SUPABASE_URL deve usar HTTPS em não-development.');
    }
    if (errors.isNotEmpty) {
      throw StateError(
        'Configuração de ambiente inválida:\n${errors.join('\n')}\n\n'
        'Execute com: flutter run --dart-define-from-file=dart_defines/dev.json',
      );
    }
  }
}
