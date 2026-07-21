/// Erro de aplicação com mensagem amigável.
/// NÃO expõe stack trace, SQL, schema ou tokens ao usuário.
sealed class AppError implements Exception {
  const AppError(this.userMessage);

  /// Mensagem segura para exibir ao usuário final.
  final String userMessage;

  @override
  String toString() => userMessage;
}

/// Erro de autenticação (credenciais, sessão expirada, etc.).
final class AuthError extends AppError {
  const AuthError([super.userMessage = 'Erro de autenticação. Tente novamente.']);
}

/// Erro de autorização (sem permissão para a ação).
final class PermissionError extends AppError {
  const PermissionError([super.userMessage = 'Você não tem permissão para esta ação.']);
}

/// Recurso não encontrado.
final class NotFoundError extends AppError {
  const NotFoundError([super.userMessage = 'Registro não encontrado.']);
}

/// Violação de regra de negócio.
final class BusinessRuleError extends AppError {
  const BusinessRuleError(super.userMessage);
}

/// Erro de conectividade ou timeout.
final class NetworkError extends AppError {
  const NetworkError([super.userMessage = 'Sem conexão. Verifique sua internet e tente novamente.']);
}

/// Erro de validação (formulário, dados).
final class ValidationError extends AppError {
  const ValidationError(super.userMessage);
}

/// Erro inesperado — log interno, mensagem genérica ao usuário.
final class UnexpectedError extends AppError {
  const UnexpectedError([
    super.userMessage = 'Ocorreu um erro inesperado. Tente novamente.',
    this.internalDetail,
  ]);

  /// Detalhe técnico para log interno — NUNCA exibir ao usuário.
  final String? internalDetail;
}
