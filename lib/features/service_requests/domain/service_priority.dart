class ServicePriority {
  const ServicePriority({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.level,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.slaHours,
    this.createdBy,
  });

  final String id;
  final String tenantId;
  final String name;
  final int level;
  final int? slaHours;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
}

ServicePriority servicePriorityFromRow(Map<String, dynamic> row) =>
    ServicePriority(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      name: row['name'] as String,
      level: (row['level'] as num).toInt(),
      slaHours: (row['sla_hours'] as num?)?.toInt(),
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      createdBy: row['created_by'] as String?,
    );
