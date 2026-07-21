import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/error/app_error.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../../shared/providers/auth_provider.dart';

sealed class TenantActionState { const TenantActionState(); }
final class TenantActionIdle    extends TenantActionState { const TenantActionIdle(); }
final class TenantActionLoading extends TenantActionState { const TenantActionLoading(); }
final class TenantActionSuccess extends TenantActionState { const TenantActionSuccess(); }
final class TenantActionError   extends TenantActionState {
  const TenantActionError(this.error);
  final AppError error;
}

class TenantNotifier extends Notifier<TenantActionState> {
  @override
  TenantActionState build() => const TenantActionIdle();

  Future<void> createTenant({
    required String name,
    required String slug,
  }) async {
    state = const TenantActionLoading();
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      state = const TenantActionError(AuthError('Usuário não autenticado.'));
      return;
    }
    try {
      final client = ref.read(supabaseClientProvider);
      // Chama a função SQL que cria tenant + settings + membership em transação
      await client.rpc('create_tenant_with_owner', params: {
        'p_tenant_name': name,
        'p_tenant_slug': slug,
        'p_owner_id':    userId,
      });
      state = const TenantActionSuccess();
      // GoRouter detecta a nova membership via activeMembershipProvider e redireciona
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('unique') || msg.contains('duplicate') || msg.contains('already exists')) {
        state = const TenantActionError(
          BusinessRuleError('Este identificador já está em uso. Escolha outro.'),
        );
      } else if (msg.contains('invalid_parameter_value') || msg.contains('slug')) {
        state = const TenantActionError(
          ValidationError('Identificador inválido. Use apenas letras minúsculas, números e hífens.'),
        );
      } else {
        state = const TenantActionError(
          UnexpectedError('Não foi possível criar a empresa. Tente novamente.'),
        );
      }
    } catch (_) {
      state = const TenantActionError(
        UnexpectedError('Não foi possível criar a empresa. Tente novamente.'),
      );
    }
  }

  void resetState() => state = const TenantActionIdle();
}

final tenantNotifierProvider =
    NotifierProvider<TenantNotifier, TenantActionState>(TenantNotifier.new);
