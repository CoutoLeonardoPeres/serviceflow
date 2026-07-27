/// Fornecedor.
///
/// Tabela própria, não reaproveita `customers`: o cadastro unificado de
/// parceiros está previsto para F5, e acoplar os dois módulos agora amarraria
/// coisas que ainda vão mudar.
class Supplier {
  const Supplier({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    this.tradeName,
    this.document,
    this.email,
    this.phone,
    this.notes,
  });

  final String id;
  final String tenantId;
  final String name;
  final String? tradeName;
  final String? document;
  final String? email;
  final String? phone;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;

  String get displayName =>
      (tradeName == null || tradeName!.isEmpty) ? name : tradeName!;
}

Supplier supplierFromRow(Map<String, dynamic> row) => Supplier(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      name: row['name'] as String,
      tradeName: row['trade_name'] as String?,
      document: row['document'] as String?,
      email: row['email'] as String?,
      phone: row['phone'] as String?,
      notes: row['notes'] as String?,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
