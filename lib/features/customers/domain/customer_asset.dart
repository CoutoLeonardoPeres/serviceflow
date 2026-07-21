import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer_asset.freezed.dart';
part 'customer_asset.g.dart';

@freezed
class CustomerAsset with _$CustomerAsset {
  const factory CustomerAsset({
    required String id,
    required String tenantId,
    required String customerId,
    String? addressId,
    required String name,
    String? brand,
    String? model,
    String? serialNumber,
    String? notes,
    required bool isActive,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? createdBy,
  }) = _CustomerAsset;

  factory CustomerAsset.fromJson(Map<String, dynamic> json) =>
      _$CustomerAssetFromJson(json);
}

/// Constrói um [CustomerAsset] a partir de uma linha do banco.
CustomerAsset customerAssetFromRow(Map<String, dynamic> row) => CustomerAsset(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      customerId: row['customer_id'] as String,
      addressId: row['address_id'] as String?,
      name: row['name'] as String,
      brand: row['brand'] as String?,
      model: row['model'] as String?,
      serialNumber: row['serial_number'] as String?,
      notes: row['notes'] as String?,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      createdBy: row['created_by'] as String?,
    );

extension CustomerAssetJsonExt on CustomerAsset {
  Map<String, dynamic> toInsertPayload() => {
        'customer_id': customerId,
        if (addressId != null) 'address_id': addressId,
        'name': name,
        if (brand != null) 'brand': brand,
        if (model != null) 'model': model,
        if (serialNumber != null) 'serial_number': serialNumber,
        if (notes != null) 'notes': notes,
        'is_active': isActive,
      };

  String get displayName {
    final details = [brand, model]
        .where((s) => s != null && s!.isNotEmpty)
        .join(' ');
    return details.isEmpty ? name : '$name — $details';
  }
}
