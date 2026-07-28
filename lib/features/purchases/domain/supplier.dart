/// Fornecedor.
///
/// Tabela própria, não reaproveita `customers`: o cadastro unificado de
/// parceiros está previsto para F5, e acoplar os dois módulos agora amarraria
/// coisas que ainda vão mudar.
///
/// Endereço, prazo, condição de pagamento e pedido mínimo vieram na 0059 — sem
/// eles não dava para responder "de quem eu compro isso, por quanto e em
/// quantos dias".
class Supplier {
  const Supplier({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.isActive,
    required this.createdAt,
    this.tradeName,
    this.document,
    this.stateRegistration,
    this.email,
    this.phone,
    this.whatsapp,
    this.website,
    this.contactName,
    this.notes,
    this.zipCode,
    this.street,
    this.number,
    this.complement,
    this.district,
    this.city,
    this.state,
    this.leadTimeDays,
    this.paymentTerms,
    this.minOrderCents = 0,
    this.delivers = true,
    this.categoryIds = const [],
  });

  final String id;
  final String tenantId;
  final String name;
  final String? tradeName;
  final String? document;
  final String? stateRegistration;
  final String? email;
  final String? phone;
  final String? whatsapp;
  final String? website;
  final String? contactName;
  final String? notes;

  final String? zipCode;
  final String? street;
  final String? number;
  final String? complement;
  final String? district;
  final String? city;
  final String? state;

  /// Prazo médio de entrega em dias corridos.
  final int? leadTimeDays;

  /// Condição de pagamento em texto livre ("28 dd", "à vista", "30/60/90").
  /// Texto livre de propósito: o mercado não tem lista fechada, e forçar uma
  /// travaria o cadastro na primeira exceção.
  final String? paymentTerms;

  /// Pedido mínimo em centavos. Zero = sem mínimo.
  final int minOrderCents;

  final bool delivers;
  final bool isActive;
  final DateTime createdAt;

  /// Categorias de material que este fornecedor atende.
  final List<String> categoryIds;

  String get displayName =>
      (tradeName == null || tradeName!.isEmpty) ? name : tradeName!;

  /// Cidade/UF para listagem. Vazio quando não há endereço.
  String get location {
    if (city == null || city!.isEmpty) return '';
    if (state == null || state!.isEmpty) return city!;
    return '$city/$state';
  }

  String get leadTimeLabel {
    final days = leadTimeDays;
    if (days == null) return 'Prazo não informado';
    if (days == 0) return 'Pronta entrega';
    return days == 1 ? '1 dia' : '$days dias';
  }

  /// Documento, telefone e CEP vão sem pontuação.
  ///
  /// A máscara é da digitação; guardar "11.222.333/0001-44" faria ele nunca
  /// casar com "11222333000144" numa busca ou numa importação, e o UNIQUE de
  /// documento por empresa deixaria passar duplicata só pela formatação.
  Map<String, dynamic> toPayload() => {
        'name': name,
        'trade_name': _orNull(tradeName),
        'document': _digitsOrNull(document),
        'state_registration': _digitsOrNull(stateRegistration),
        'email': _orNull(email),
        'phone': _digitsOrNull(phone),
        'whatsapp': _digitsOrNull(whatsapp),
        'website': _orNull(website),
        'contact_name': _orNull(contactName),
        'notes': _orNull(notes),
        'zip_code': _digitsOrNull(zipCode),
        'street': _orNull(street),
        'number': _orNull(number),
        'complement': _orNull(complement),
        'district': _orNull(district),
        'city': _orNull(city),
        'state': _orNull(state),
        'lead_time_days': leadTimeDays,
        'payment_terms': _orNull(paymentTerms),
        'min_order_cents': minOrderCents,
        'delivers': delivers,
        'is_active': isActive,
      };

  Supplier copyWith({
    String? name,
    String? tradeName,
    String? document,
    String? stateRegistration,
    String? email,
    String? phone,
    String? whatsapp,
    String? website,
    String? contactName,
    String? notes,
    String? zipCode,
    String? street,
    String? number,
    String? complement,
    String? district,
    String? city,
    String? state,
    int? leadTimeDays,
    String? paymentTerms,
    int? minOrderCents,
    bool? delivers,
    bool? isActive,
    List<String>? categoryIds,
  }) =>
      Supplier(
        id: id,
        tenantId: tenantId,
        name: name ?? this.name,
        tradeName: tradeName ?? this.tradeName,
        document: document ?? this.document,
        stateRegistration: stateRegistration ?? this.stateRegistration,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        whatsapp: whatsapp ?? this.whatsapp,
        website: website ?? this.website,
        contactName: contactName ?? this.contactName,
        notes: notes ?? this.notes,
        zipCode: zipCode ?? this.zipCode,
        street: street ?? this.street,
        number: number ?? this.number,
        complement: complement ?? this.complement,
        district: district ?? this.district,
        city: city ?? this.city,
        state: state ?? this.state,
        leadTimeDays: leadTimeDays ?? this.leadTimeDays,
        paymentTerms: paymentTerms ?? this.paymentTerms,
        minOrderCents: minOrderCents ?? this.minOrderCents,
        delivers: delivers ?? this.delivers,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        categoryIds: categoryIds ?? this.categoryIds,
      );
}

String? _orNull(String? value) =>
    (value == null || value.trim().isEmpty) ? null : value.trim();

String? _digitsOrNull(String? value) {
  if (value == null) return null;
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : digits;
}

Supplier supplierFromRow(Map<String, dynamic> row) {
  final categories = row['supplier_categories'];
  return Supplier(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    name: row['name'] as String,
    tradeName: row['trade_name'] as String?,
    document: row['document'] as String?,
    stateRegistration: row['state_registration'] as String?,
    email: row['email'] as String?,
    phone: row['phone'] as String?,
    whatsapp: row['whatsapp'] as String?,
    website: row['website'] as String?,
    contactName: row['contact_name'] as String?,
    notes: row['notes'] as String?,
    zipCode: row['zip_code'] as String?,
    street: row['street'] as String?,
    number: row['number'] as String?,
    complement: row['complement'] as String?,
    district: row['district'] as String?,
    city: row['city'] as String?,
    state: row['state'] as String?,
    leadTimeDays: (row['lead_time_days'] as num?)?.toInt(),
    paymentTerms: row['payment_terms'] as String?,
    minOrderCents: (row['min_order_cents'] as num?)?.toInt() ?? 0,
    delivers: row['delivers'] as bool? ?? true,
    isActive: row['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(row['created_at'] as String),
    categoryIds: categories is List
        ? categories
            .map((e) => (e as Map)['category_id'] as String)
            .toList(growable: false)
        : const [],
  );
}
