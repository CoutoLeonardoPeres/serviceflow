import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/error/app_error.dart';
import '../../../core/config/env_config.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../../shared/providers/tenant_provider.dart';

/// Estado do notifier de auth.
sealed class AuthActionState {
  const AuthActionState();
}

final class AuthActionIdle extends AuthActionState {
  const AuthActionIdle();
}

final class AuthActionLoading extends AuthActionState {
  const AuthActionLoading();
}

final class AuthActionSuccess extends AuthActionState {
  const AuthActionSuccess([this.message]);
  final String? message;
}

final class AuthActionError extends AuthActionState {
  const AuthActionError(this.error);
  final AppError error;
}

/// Notifier para ações de auth (login, logout, recuperação de senha).
/// O estado de sessão vivo vem de [authStateProvider] — este notifier
/// apenas gerencia o estado das ações assíncronas.
class AuthNotifier extends Notifier<AuthActionState> {
  @override
  AuthActionState build() => const AuthActionIdle();

  SupabaseClient get _client => ref.read(supabaseClientProvider);

  /// Login com e-mail e senha.
  Future<void> signInWithEmail(
    String email,
    String password, {
    String? inviteToken,
  }) async {
    state = const AuthActionLoading();
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (inviteToken != null && inviteToken.trim().isNotEmpty) {
        try {
          await _client.rpc(
            'accept_tenant_invitation',
            params: {'p_token': inviteToken.trim()},
          );
        } on PostgrestException catch (e) {
          await _client.auth.signOut();
          ref
            ..invalidate(authStateProvider)
            ..invalidate(activeMembershipProvider);
          state = AuthActionError(_mapInviteException(e));
          return;
        }
      }
      ref
        ..invalidate(authStateProvider)
        ..invalidate(activeMembershipProvider);
      state = AuthActionSuccess(
        inviteToken != null && inviteToken.trim().isNotEmpty
            ? 'Convite aceito com sucesso.'
            : null,
      );
    } on AuthException catch (e) {
      state = AuthActionError(_mapAuthException(e));
    } catch (_) {
      state = const AuthActionError(
        UnexpectedError('Não foi possível conectar. Tente novamente.'),
      );
    }
  }

  Future<void> signUpFromInvitation({
    required String fullName,
    required String email,
    required String password,
    required String inviteToken,
  }) async {
    state = const AuthActionLoading();
    try {
      final signUpResult = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
      );

      if (signUpResult.session == null) {
        await _client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
      }

      await _client.rpc(
        'accept_tenant_invitation',
        params: {'p_token': inviteToken.trim()},
      );

      ref
        ..invalidate(authStateProvider)
        ..invalidate(activeMembershipProvider);
      state =
          const AuthActionSuccess('Conta criada e convite aceito com sucesso.');
    } on AuthException catch (e) {
      state = AuthActionError(_mapSignUpException(e));
    } on PostgrestException catch (e) {
      state = AuthActionError(_mapInviteException(e));
    } catch (_) {
      state = const AuthActionError(
        UnexpectedError('Não foi possível concluir o primeiro acesso.'),
      );
    }
  }

  /// Enviar e-mail de recuperação de senha.
  Future<void> sendPasswordReset(String email) async {
    state = const AuthActionLoading();
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: EnvConfig.publicUrl(AppRoutes.resetPassword),
      );
      // Mensagem genérica: não revela se o e-mail existe ou não.
      state = const AuthActionSuccess(
        'Se este e-mail estiver cadastrado, você receberá as instruções em breve.',
      );
    } catch (_) {
      // Mesmo em erro interno, retornamos sucesso para não revelar se o e-mail existe.
      state = const AuthActionSuccess(
        'Se este e-mail estiver cadastrado, você receberá as instruções em breve.',
      );
    }
  }

  /// Redefinir senha com o novo valor (após link de reset).
  Future<void> updatePassword(String newPassword) async {
    state = const AuthActionLoading();
    try {
      await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      // A sessão criada pelo link de recuperação não deve permanecer ativa.
      // Assim, o usuário confirma o novo segredo no fluxo normal de login.
      await _client.auth.signOut();
      ref
        ..invalidate(authStateProvider)
        ..invalidate(activeMembershipProvider);
      state = const AuthActionSuccess('Senha atualizada com sucesso.');
    } on AuthException catch (e) {
      state = AuthActionError(_mapAuthException(e));
    } catch (_) {
      state = const AuthActionError(
        UnexpectedError('Não foi possível atualizar a senha.'),
      );
    }
  }

  /// Logout — revoga a sessão atual.
  Future<void> signOut() async {
    state = const AuthActionLoading();
    try {
      await _client.auth.signOut();
      ref
        ..invalidate(authStateProvider)
        ..invalidate(activeMembershipProvider);
      state = const AuthActionIdle();
    } catch (_) {
      state = const AuthActionIdle(); // logout falhou mas limpamos estado local
    }
  }

  /// Limpa o estado após o UI processar o resultado.
  void resetState() => state = const AuthActionIdle();

  // ── Mapeamento de erros do Supabase Auth ──────────────────────────────────
  // Mensagens genéricas para não revelar existência de usuários.
  AppError _mapAuthException(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login') ||
        msg.contains('invalid credentials') ||
        msg.contains('email not confirmed')) {
      return const AuthError('E-mail ou senha inválidos.');
    }
    if (msg.contains('too many requests') || msg.contains('rate limit')) {
      return const AuthError(
        'Muitas tentativas. Aguarde alguns minutos e tente novamente.',
      );
    }
    if (msg.contains('user not found') || msg.contains('user banned')) {
      // Não revela que o usuário não existe — mesma mensagem genérica
      return const AuthError('E-mail ou senha inválidos.');
    }
    return const AuthError('Erro de autenticação. Tente novamente.');
  }

  AppError _mapInviteException(PostgrestException e) {
    if (e.code == '22023') {
      return const ValidationError('Convite inválido.');
    }
    if (e.code == 'P0001' || e.code == 'P0002') {
      return BusinessRuleError(e.message);
    }
    return const AuthError(
      'Não foi possível aceitar o convite com este login.',
    );
  }

  AppError _mapSignUpException(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('already registered') ||
        msg.contains('already been registered') ||
        msg.contains('user already registered')) {
      return const AuthError(
        'Este e-mail já possui conta. Entre com sua senha para aceitar o convite.',
      );
    }
    if (msg.contains('password')) {
      return const ValidationError('Senha inválida.');
    }
    return const AuthError('Não foi possível criar a conta.');
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthActionState>(AuthNotifier.new);
