class TenantInvitation {
  const TenantInvitation({
    required this.id,
    required this.email,
    required this.roleKey,
    required this.roleName,
    required this.expiresAt,
    required this.createdAt,
    required this.isRevoked,
    required this.isAccepted,
  });

  final String id;
  final String email;
  final String roleKey;
  final String roleName;
  final DateTime expiresAt;
  final DateTime createdAt;
  final bool isRevoked;
  final bool isAccepted;

  bool get isPending =>
      !isRevoked && !isAccepted && expiresAt.isAfter(DateTime.now());

  factory TenantInvitation.fromMap(Map<String, dynamic> map) {
    final role = map['roles'] as Map<String, dynamic>?;
    return TenantInvitation(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      roleKey: role?['key'] as String? ?? '',
      roleName: role?['name'] as String? ?? '',
      expiresAt: DateTime.parse(map['expires_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      isRevoked: map['revoked_at'] != null,
      isAccepted: map['accepted_at'] != null,
    );
  }
}
