class TenantRoleOption {
  const TenantRoleOption({
    required this.id,
    required this.key,
    required this.name,
  });

  final String id;
  final String key;
  final String name;

  factory TenantRoleOption.fromMap(Map<String, dynamic> map) {
    return TenantRoleOption(
      id: map['id'] as String,
      key: map['key'] as String? ?? '',
      name: map['name'] as String? ?? '',
    );
  }
}
