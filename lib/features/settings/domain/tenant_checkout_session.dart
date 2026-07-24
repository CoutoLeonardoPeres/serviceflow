class TenantCheckoutSession {
  const TenantCheckoutSession({
    required this.id,
    required this.planKey,
    required this.source,
    required this.status,
    required this.provider,
    required this.providerReference,
    required this.returnUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.returnedAt,
    required this.confirmedAt,
    required this.canceledAt,
    required this.expiresAt,
  });

  final String id;
  final String planKey;
  final String source;
  final String status;
  final String? provider;
  final String? providerReference;
  final String? returnUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? returnedAt;
  final DateTime? confirmedAt;
  final DateTime? canceledAt;
  final DateTime? expiresAt;

  factory TenantCheckoutSession.fromMap(Map<String, dynamic> map) {
    DateTime? parseNullable(String key) {
      final raw = map[key] as String?;
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    return TenantCheckoutSession(
      id: map['id'] as String,
      planKey: map['plan_key'] as String? ?? '',
      source: map['source'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      provider: map['provider'] as String?,
      providerReference: map['provider_reference'] as String?,
      returnUrl: map['return_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      returnedAt: parseNullable('returned_at'),
      confirmedAt: parseNullable('confirmed_at'),
      canceledAt: parseNullable('canceled_at'),
      expiresAt: parseNullable('expires_at'),
    );
  }
}
