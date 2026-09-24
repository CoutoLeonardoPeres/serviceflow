import '../../../core/plans/tenant_plan.dart';

class PlatformTenant {
  const PlatformTenant({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    required this.plan,
    required this.billingStatus,
    required this.trialEndsAt,
    required this.planSelectedAt,
    required this.createdAt,
    required this.activeUsers,
    required this.activeUnits,
  });

  final String id;
  final String name;
  final String slug;
  final String status;
  final TenantPlanDefinition plan;
  final String billingStatus;
  final DateTime? trialEndsAt;
  final DateTime? planSelectedAt;
  final DateTime? createdAt;
  final int activeUsers;
  final int activeUnits;

  bool get isActive => status == 'active';

  factory PlatformTenant.fromMap(Map<String, dynamic> map) {
    return PlatformTenant(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Empresa sem nome',
      slug: map['slug'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      plan: resolveTenantPlan(map['plan_key'] as String?),
      billingStatus: map['billing_status'] as String? ?? 'active',
      trialEndsAt: _date(map['trial_ends_at']),
      planSelectedAt: _date(map['plan_selected_at']),
      createdAt: _date(map['created_at']),
      activeUsers: _int(map['active_users']),
      activeUnits: _int(map['active_units']),
    );
  }

  static DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  static int _int(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
}
