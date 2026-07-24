class InvitationPreview {
  const InvitationPreview({
    required this.email,
    required this.tenantName,
    required this.tenantSlug,
    required this.roleKey,
    required this.roleName,
    required this.expiresAt,
    required this.isValid,
  });

  final String email;
  final String tenantName;
  final String tenantSlug;
  final String roleKey;
  final String roleName;
  final DateTime expiresAt;
  final bool isValid;

  factory InvitationPreview.fromMap(Map<String, dynamic> map) {
    return InvitationPreview(
      email: map['email'] as String? ?? '',
      tenantName: map['tenant_name'] as String? ?? '',
      tenantSlug: map['tenant_slug'] as String? ?? '',
      roleKey: map['role_key'] as String? ?? '',
      roleName: map['role_name'] as String? ?? '',
      expiresAt: DateTime.parse(map['expires_at'] as String),
      isValid: map['is_valid'] as bool? ?? false,
    );
  }
}
