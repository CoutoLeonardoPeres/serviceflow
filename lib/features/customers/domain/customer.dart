import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer.freezed.dart';
part 'customer.g.dart';

// ── Tipo de cliente ────────────────────────────────────────────────────────────
enum CustomerType {
  person,
  company,
  condominium,
  publicEntity;

  String get value => switch (this) {
        CustomerType.person => 'person',
        CustomerType.company => 'company',
        CustomerType.condominium => 'condominium',
        CustomerType.publicEntity => 'public_entity',
      };

  String get label => switch (this) {
        CustomerType.person => 'Pessoa Física',
        CustomerType.company => 'Empresa',
        CustomerType.condominium => 'Condomínio',
        CustomerType.publicEntity => 'Entidade Pública',
      };

  /// Retorna se o tipo usa CPF (true) ou CNPJ (false).
  bool get usesCpf => this == CustomerType.person;

  static CustomerType fromValue(String value) => switch (value) {
        'person' => CustomerType.person,
        'company' => CustomerType.company,
        'condominium' => CustomerType.condominium,
        'public_entity' => CustomerType.publicEntity,
        _ => throw ArgumentError('CustomerType desconhecido: $value'),
      };
}

// ── Entidade Customer ─────────────────────────────────────────────────────────
@freezed
class Customer with _$Customer {
  const factory Customer({
    required String id,
    required String tenantId,
    required CustomerType type,
    required String name,
    String? tradeName,
    /// CPF (11 dígitos) ou CNPJ (14 dígitos) — somente dígitos no armazenamento.
    String? document,
    String? email,
    String? phone,
    String? notes,
    required bool isActive,
    String? payerCustomerId,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? createdBy,
    String? updatedBy,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}

// Conversores customizados para o banco (snake_case → camelCase + enums)
extension CustomerJsonExt on Customer {
  /// Monta o payload para INSERT/UPDATE no Supabase.
  /// tenant_id é omitido — o servidor derive da membership (trigger).
  Map<String, dynamic> toInsertPayload() => {
        'type': type.value,
        'name': name,
        if (tradeName != null) 'trade_name': tradeName,
        if (document != null) 'document': document,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (notes != null) 'notes': notes,
        'is_active': isActive,
        if (payerCustomerId != null) 'payer_customer_id': payerCustomerId,
      };
}

/// Constrói um [Customer] a partir de uma linha do banco (snake_case).
Customer customerFromRow(Map<String, dynamic> row) => Customer(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      type: CustomerType.fromValue(row['type'] as String),
      name: row['name'] as String,
      tradeName: row['trade_name'] as String?,
      document: row['document'] as String?,
      email: row['email'] as String?,
      phone: row['phone'] as String?,
      notes: row['notes'] as String?,
      isActive: row['is_active'] as bool? ?? true,
      payerCustomerId: row['payer_customer_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      createdBy: row['created_by'] as String?,
      updatedBy: row['updated_by'] as String?,
    );
