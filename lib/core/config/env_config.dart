// ignore_for_file: do_not_use_environment
// Razão: é a única forma correta de ler --dart-define em Flutter.
// Valores vêm de dart_defines/dev.json (nunca do código).

enum AppEnvironment { development, staging, production }

class EnvConfig {
  EnvConfig._();

  static const String _devSupabaseUrl =
      'https://pkbluscdssiiumrppmwa.supabase.co';
  static const String _devSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrYmx1c2Nkc3NpaXVtcnBwbXdhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2NDEyMzIsImV4cCI6MjEwMDIxNzIzMn0.twkw2ZsDOc6kmQ97OdsCi2AFXjUOPZKTx8PJACTVYxI';

  // ── Supabase ────────────────────────────────────────────────────────────────
  /// URL pública do projeto Supabase (ex: https://abcd.supabase.co).
  static const String _supabaseUrlFromEnv =
      String.fromEnvironment('SUPABASE_URL');
  static String get supabaseUrl =>
      _supabaseUrlFromEnv.isNotEmpty ? _supabaseUrlFromEnv : _devSupabaseUrl;

  /// Anon/publishable key — segura para uso no cliente. NÃO é a service_role.
  static const String _supabaseAnonKeyFromEnv =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static String get supabaseAnonKey => _supabaseAnonKeyFromEnv.isNotEmpty
      ? _supabaseAnonKeyFromEnv
      : _devSupabaseAnonKey;

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

  static bool get isDevelopment => environment == AppEnvironment.development;
  static bool get isProduction => environment == AppEnvironment.production;

  // ── Cobrança / Checkout ────────────────────────────────────────────────────
  static const String _billingPortalUrlFromEnv =
      String.fromEnvironment('BILLING_PORTAL_URL');
  static String? get billingPortalUrl => _billingPortalUrlFromEnv.trim().isEmpty
      ? null
      : _billingPortalUrlFromEnv.trim();

  static const String _starterCheckoutUrlFromEnv =
      String.fromEnvironment('CHECKOUT_STARTER_URL');
  static const String _professionalCheckoutUrlFromEnv =
      String.fromEnvironment('CHECKOUT_PROFESSIONAL_URL');
  static const String _businessCheckoutUrlFromEnv =
      String.fromEnvironment('CHECKOUT_BUSINESS_URL');
  static const String _enterpriseCheckoutUrlFromEnv =
      String.fromEnvironment('CHECKOUT_ENTERPRISE_URL');

  static String? checkoutUrlForPlan(String planKey) {
    final raw = switch (planKey) {
      'starter' => _starterCheckoutUrlFromEnv,
      'professional' => _professionalCheckoutUrlFromEnv,
      'business' => _businessCheckoutUrlFromEnv,
      'enterprise' => _enterpriseCheckoutUrlFromEnv,
      _ => '',
    }
        .trim();
    return raw.isEmpty ? null : raw;
  }

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

  // ── Links compartilhados com terceiros ─────────────────────────────────────
  /// Base dos links que saem do sistema (orcamento publico, pesquisa de
  /// satisfacao, convite). NAO pode sair de `Uri.base`: em localhost isso gera
  /// `http://localhost:PORT`, que so abre na maquina de quem gerou o link — o
  /// cliente que recebe no WhatsApp nunca consegue abrir. Em build desktop
  /// `Uri.base.origin` ainda por cima lanca StateError (esquema `file:`).
  static const String _publicBaseUrlFromEnv =
      String.fromEnvironment('APP_PUBLIC_BASE_URL');
  static const String _defaultPublicBaseUrl =
      'https://serviceflow.leonardoperescouto.com';

  static String get publicBaseUrl {
    final configured = _publicBaseUrlFromEnv.trim();
    if (configured.isNotEmpty) {
      return configured.endsWith('/')
          ? configured.substring(0, configured.length - 1)
          : configured;
    }
    // Servido de um dominio real: usa o proprio. localhost/127.0.0.1 nao serve
    // para link externo, entao cai no dominio de publicacao.
    final base = Uri.base;
    if ((base.scheme == 'https' || base.scheme == 'http') &&
        base.host.isNotEmpty &&
        base.host != 'localhost' &&
        base.host != '127.0.0.1') {
      return base.origin;
    }
    return _defaultPublicBaseUrl;
  }

  /// Monta um link publico completo a partir de uma rota do app.
  static String publicUrl(String routePath) => '$publicBaseUrl/#$routePath';
}
