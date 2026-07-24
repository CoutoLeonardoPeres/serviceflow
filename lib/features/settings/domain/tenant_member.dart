class TenantMember {
  const TenantMember({
    required this.id,
    required this.userId,
    required this.status,
    required this.fullName,
    required this.email,
    required this.roleKey,
    required this.roleName,
  });

  final String id;
  final String userId;
  final String status;
  final String fullName;
  final String email;
  final String roleKey;
  final String roleName;

  bool get isActive => status == 'active';
  bool get isOwner => roleKey == 'tenant_owner';

  factory TenantMember.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    final role = map['roles'] as Map<String, dynamic>?;
    final user = map['users'] as Map<String, dynamic>?;
    return TenantMember(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      status: map['status'] as String? ?? 'active',
      fullName: profile?['full_name'] as String? ?? 'Sem nome',
      email: user?['email'] as String? ?? '',
      roleKey: role?['key'] as String? ?? '',
      roleName: role?['name'] as String? ?? '',
    );
  }
}
