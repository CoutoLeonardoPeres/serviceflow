class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.createdBy,
  });

  final String id;
  final String tenantId;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
}

ServiceCategory serviceCategoryFromRow(Map<String, dynamic> row) =>
    ServiceCategory(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      createdBy: row['created_by'] as String?,
    );
