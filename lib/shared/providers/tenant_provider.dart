import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/plans/tenant_plan.dart';
import '../../core/error/app_error.dart';
import 'supabase_provider.dart';
import 'auth_provider.dart';

/// Membership ativa do usuário corrente.
/// Retorna null se não logado ou sem membership ativa.
final activeMembershipProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final client = ref.watch(supabaseClientProvider);
  try {
    final rows = await client.from('tenant_memberships').select('''
        id, tenant_id, role_id, status,
        tenants ( * ),
        roles ( id, key, name )
      ''').eq('user_id', userId).eq('status', 'active').limit(1).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw const NetworkError(
            'A verificação da empresa demorou demais. Recarregue a página.',
          ),
        );

    return pickActiveMembership((rows as List<dynamic>).cast());
  } on NetworkError {
    rethrow;
  }
});

Map<String, dynamic>? pickActiveMembership(List<dynamic> rows) {
  if (rows.isEmpty) return null;
  return rows.first as Map<String, dynamic>;
}

/// tenant_id do tenant ativo do usuário.
final currentTenantIdProvider = Provider.autoDispose<String?>((ref) {
  return ref
      .watch(activeMembershipProvider)
      .whenOrNull(data: (m) => m?['tenant_id'] as String?);
});

/// Dados do tenant ativo (nome, slug, etc.).
final currentTenantProvider =
    Provider.autoDispose<Map<String, dynamic>?>((ref) {
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

final currentTenantPlanProvider =
    Provider.autoDispose<TenantPlanSnapshot>((ref) {
  final tenant = ref.watch(currentTenantProvider);
  final plan = resolveTenantPlan(tenant?['plan_key'] as String?);
  final billingStatus = tenant?['billing_status'] as String? ?? 'active';
  final trialEndsAtRaw = tenant?['trial_ends_at'] as String?;

  return TenantPlanSnapshot(
    plan: plan,
    billingStatus: billingStatus,
    trialEndsAt:
        trialEndsAtRaw == null ? null : DateTime.tryParse(trialEndsAtRaw),
    planSelectedAt: tenant?['plan_selected_at'] == null
        ? null
        : DateTime.tryParse(tenant?['plan_selected_at'] as String),
  );
});

final activeTenantMemberCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) return 0;

  final client = ref.watch(supabaseClientProvider);
  try {
    final rows = await client
        .from('tenant_memberships')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('status', 'active');
    return (rows as List).length;
  } catch (e) {
    throw UnexpectedError(
      'Não foi possível contar os usuários ativos.',
      e.toString(),
    );
  }
});

final activeTenantUnitCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) return 0;

  final client = ref.watch(supabaseClientProvider);
  try {
    final rows = await client
        .from('tenant_units')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('is_active', true);
    return (rows as List).length;
  } catch (e) {
    throw UnexpectedError(
      'Não foi possível contar as unidades ativas.',
      e.toString(),
    );
  }
});

final currentPlanFeatureSetProvider =
    Provider.autoDispose<Set<TenantFeature>>((ref) {
  return ref.watch(currentTenantPlanProvider).plan.features;
});

final isPlanAccessBlockedProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(currentTenantPlanProvider).hasCommercialBlock;
});

final requiresInitialPlanSelectionProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(currentTenantPlanProvider).requiresPlanSelection;
});

final planAccessBlockReasonProvider = Provider.autoDispose<String?>((ref) {
  final snapshot = ref.watch(currentTenantPlanProvider);
  if (snapshot.isTrialExpired) {
    return 'O período de trial terminou.';
  }
  switch (snapshot.billingStatus) {
    case 'past_due':
      return 'A assinatura está com pagamento pendente.';
    case 'canceled':
      return 'A assinatura está cancelada.';
    default:
      return null;
  }
});

final hasPlanFeatureProvider =
    Provider.autoDispose.family<bool, TenantFeature>((ref, feature) {
  return ref.watch(currentPlanFeatureSetProvider).contains(feature);
});

/// true se o usuário tem um tenant ativo configurado.
final hasTenantProvider = Provider.autoDispose<bool>((ref) {
  final membership = ref.watch(activeMembershipProvider);
  return membership.whenOrNull(data: (m) => m != null) ?? false;
});
