import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer_address.freezed.dart';
part 'customer_address.g.dart';

/// UF válidas do Brasil.
const kBrazilianStates = [
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
];

@freezed
class CustomerAddress with _$CustomerAddress {
  const factory CustomerAddress({
    required String id,
    required String tenantId,
    required String customerId,
    required String label,
    required String cep,
    required String street,
    required String number,
    String? complement,
    required String district,
    required String city,
    required String state,
    String? reference,
    double? latitude,
    double? longitude,
    required bool isDefault,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? createdBy,
  }) = _CustomerAddress;

  factory CustomerAddress.fromJson(Map<String, dynamic> json) =>
      _$CustomerAddressFromJson(json);
}

/// Constrói um [CustomerAddress] a partir de uma linha do banco.
CustomerAddress customerAddressFromRow(Map<String, dynamic> row) =>
    CustomerAddress(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      customerId: row['customer_id'] as String,
      label: row['label'] as String? ?? 'Principal',
      cep: row['cep'] as String,
      street: row['street'] as String,
      number: row['number'] as String,
      complement: row['complement'] as String?,
      district: row['district'] as String,
      city: row['city'] as String,
      state: row['state'] as String,
      reference: row['reference'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      isDefault: row['is_default'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      createdBy: row['created_by'] as String?,
    );

extension CustomerAddressJsonExt on CustomerAddress {
  Map<String, dynamic> toInsertPayload() => {
        'customer_id': customerId,
        'label': label,
        'cep': cep,
        'street': street,
        'number': number,
        if (complement != null) 'complement': complement,
        'district': district,
        'city': city,
        'state': state,
        if (reference != null) 'reference': reference,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'is_default': isDefault,
      };

  /// Endereço formatado em uma linha.
  String get oneLineAddress =>
      '$street, $number${complement != null ? ', $complement' : ''} — $district, $city/$state — CEP $cep';
}
