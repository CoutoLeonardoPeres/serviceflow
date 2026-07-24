class TenantBillingEvent {
  const TenantBillingEvent({
    required this.id,
    required this.eventType,
    required this.planKey,
    required this.previousPlanKey,
    required this.billingStatus,
    required this.previousBillingStatus,
    required this.note,
    required this.actorUserId,
    required this.occurredAt,
  });

  final String id;
  final String eventType;
  final String? planKey;
  final String? previousPlanKey;
  final String? billingStatus;
  final String? previousBillingStatus;
  final String? note;
  final String? actorUserId;
  final DateTime occurredAt;

  factory TenantBillingEvent.fromMap(Map<String, dynamic> map) {
    return TenantBillingEvent(
      id: map['id'] as String,
      eventType: map['event_type'] as String? ?? '',
      planKey: map['plan_key'] as String?,
      previousPlanKey: map['previous_plan_key'] as String?,
      billingStatus: map['billing_status'] as String?,
      previousBillingStatus: map['previous_billing_status'] as String?,
      note: map['note'] as String?,
      actorUserId: map['actor_user_id'] as String?,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
    );
  }
}
