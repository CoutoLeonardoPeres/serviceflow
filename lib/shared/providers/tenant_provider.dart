import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_provider.dart';
import 'auth_provider.dart';

/// Membership ativa do usuário corrente.
/// Retorna null se não logado ou sem membership ativa.
final activeMembershipProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final client = ref.watch(supabaseClientProvider);

  final result = await client
      .from('tenant_memberships')
      .select('''
        id, tenant_id, role_id, status,
        tenants ( id, name, slug, timezone ),
        roles ( id, key, name )
      ''')
      .eq('user_id', userId)
      .eq('status', 'active')
      .maybeSingle();

  return result;
});

/// tenant_id do tenant ativo do usuário.
final currentTenantIdProvider = Provider.autoDispose<String?>((ref) {
  return ref
      .watch(activeMembershipProvider)
      .whenOrNull(data: (m) => m?['tenant_id'] as String?);
});

/// Dados do tenant ativo (nome, slug, etc.).
final currentTenantProvider = Provider.autoDispose<Map<String, dynamic>?>((ref) {
  return ref.watch(activeMembershipProvider).whenOrNull(
        data: (m) => m?['tenants'] as Map<String, dynamic>?,
      );
});

/// Chave do role do usuário (ex: 'technician', 'analyst').
final currentRoleKeyProvider = Provider.autoDispose<String?>((ref) {
  return ref.watch(activeMembershipProvider).whenOrNull(
        data: (m) {
          final role = m?['roles'] as Map<String, dynamic>?;
          return role?['key'] as String?;
        },
      );
});

/// true se o usuário tem um tenant ativo configurado.
final hasTenantProvider = Provider.autoDispose<bool>((ref) {
  final membership = ref.watch(activeMembershipProvider);
  return membership.whenOrNull(data: (m) => m != null) ?? false;
});
