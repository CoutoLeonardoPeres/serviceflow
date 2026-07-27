/// Depósito de estoque.
///
/// O banco garante no máximo um `isDefault` por tenant (índice parcial único
/// em `warehouses`, migration 0042).
class Warehouse {
  const Warehouse({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.isDefault,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String name;
  final bool isDefault;
  final bool isActive;
  final DateTime createdAt;
}

Warehouse warehouseFromRow(Map<String, dynamic> row) => Warehouse(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      name: row['name'] as String,
      isDefault: row['is_default'] as bool? ?? false,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
