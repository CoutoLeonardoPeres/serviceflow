import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer_contact.freezed.dart';
part 'customer_contact.g.dart';

@freezed
class CustomerContact with _$CustomerContact {
  const factory CustomerContact({
    required String id,
    required String tenantId,
    required String customerId,
    required String name,
    String? role,
    String? phone,
    String? whatsapp,
    String? email,
    required bool isPrimary,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? createdBy,
  }) = _CustomerContact;

  factory CustomerContact.fromJson(Map<String, dynamic> json) =>
      _$CustomerContactFromJson(json);
}

/// Constrói um [CustomerContact] a partir de uma linha do banco.
CustomerContact customerContactFromRow(Map<String, dynamic> row) =>
    CustomerContact(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      customerId: row['customer_id'] as String,
      name: row['name'] as String,
      role: row['role'] as String?,
      phone: row['phone'] as String?,
      whatsapp: row['whatsapp'] as String?,
      email: row['email'] as String?,
      isPrimary: row['is_primary'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      createdBy: row['created_by'] as String?,
    );

extension CustomerContactJsonExt on CustomerContact {
  Map<String, dynamic> toInsertPayload() => {
        'customer_id': customerId,
        'name': name,
        if (role != null) 'role': role,
        if (phone != null) 'phone': phone,
        if (whatsapp != null) 'whatsapp': whatsapp,
        if (email != null) 'email': email,
        'is_primary': isPrimary,
      };
}
