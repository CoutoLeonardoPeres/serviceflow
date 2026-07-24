class TenantUnit {
  const TenantUnit({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.city,
    required this.state,
    required this.isPrimary,
    required this.isActive,
  });

  final String id;
  final String tenantId;
  final String name;
  final String? city;
  final String? state;
  final bool isPrimary;
  final bool isActive;

  factory TenantUnit.fromMap(Map<String, dynamic> map) {
    return TenantUnit(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String,
      name: map['name'] as String? ?? '',
      city: map['city'] as String?,
      state: map['state'] as String?,
      isPrimary: map['is_primary'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertMap(String tenantId) {
    return {
      'tenant_id': tenantId,
      'name': name,
      'city': city,
      'state': state,
      'is_primary': isPrimary,
      'is_active': isActive,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'name': name,
      'city': city,
      'state': state,
      'is_primary': isPrimary,
      'is_active': isActive,
    };
  }

  TenantUnit copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? city,
    String? state,
    bool? isPrimary,
    bool? isActive,
  }) {
    return TenantUnit(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      city: city ?? this.city,
      state: state ?? this.state,
      isPrimary: isPrimary ?? this.isPrimary,
      isActive: isActive ?? this.isActive,
    );
  }
}
