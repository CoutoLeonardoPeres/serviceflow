enum QuotationStatus {
  draft,
  underReview,
  sent,
  viewed,
  awaitingApproval,
  approved,
  rejected,
  changeRequested,
  expired,
  cancelled;

  String get value => switch (this) {
        QuotationStatus.draft => 'draft',
        QuotationStatus.underReview => 'under_review',
        QuotationStatus.sent => 'sent',
        QuotationStatus.viewed => 'viewed',
        QuotationStatus.awaitingApproval => 'awaiting_approval',
        QuotationStatus.approved => 'approved',
        QuotationStatus.rejected => 'rejected',
        QuotationStatus.changeRequested => 'change_requested',
        QuotationStatus.expired => 'expired',
        QuotationStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        QuotationStatus.draft => 'Rascunho',
        QuotationStatus.underReview => 'Em revisão',
        QuotationStatus.sent => 'Enviado',
        QuotationStatus.viewed => 'Visualizado',
        QuotationStatus.awaitingApproval => 'Aguardando aprovação',
        QuotationStatus.approved => 'Aprovado',
        QuotationStatus.rejected => 'Rejeitado',
        QuotationStatus.changeRequested => 'Solicitou alteração',
        QuotationStatus.expired => 'Expirado',
        QuotationStatus.cancelled => 'Cancelado',
      };

  bool get isTerminal =>
      this == QuotationStatus.approved ||
      this == QuotationStatus.rejected ||
      this == QuotationStatus.expired ||
      this == QuotationStatus.cancelled;

  static QuotationStatus fromValue(String value) => switch (value) {
        'draft' => QuotationStatus.draft,
        'under_review' => QuotationStatus.underReview,
        'sent' => QuotationStatus.sent,
        'viewed' => QuotationStatus.viewed,
        'awaiting_approval' => QuotationStatus.awaitingApproval,
        'approved' => QuotationStatus.approved,
        'rejected' => QuotationStatus.rejected,
        'change_requested' => QuotationStatus.changeRequested,
        'expired' => QuotationStatus.expired,
        'cancelled' => QuotationStatus.cancelled,
        _ => throw ArgumentError('QuotationStatus desconhecido: $value'),
      };
}

enum QuotationItemKind {
  service,
  laborHour,
  material,
  equipment,
  travel,
  tax,
  discount,
  other;

  String get value => switch (this) {
        QuotationItemKind.service => 'service',
        QuotationItemKind.laborHour => 'labor_hour',
        QuotationItemKind.material => 'material',
        QuotationItemKind.equipment => 'equipment',
        QuotationItemKind.travel => 'travel',
        QuotationItemKind.tax => 'tax',
        QuotationItemKind.discount => 'discount',
        QuotationItemKind.other => 'other',
      };

  String get label => switch (this) {
        QuotationItemKind.service => 'Serviço',
        QuotationItemKind.laborHour => 'Hora técnica',
        QuotationItemKind.material => 'Material',
        QuotationItemKind.equipment => 'Equipamento',
        QuotationItemKind.travel => 'Deslocamento',
        QuotationItemKind.tax => 'Imposto',
        QuotationItemKind.discount => 'Desconto',
        QuotationItemKind.other => 'Outro',
      };

  static QuotationItemKind fromValue(String value) => switch (value) {
        'service' => QuotationItemKind.service,
        'labor_hour' => QuotationItemKind.laborHour,
        'material' => QuotationItemKind.material,
        'equipment' => QuotationItemKind.equipment,
        'travel' => QuotationItemKind.travel,
        'tax' => QuotationItemKind.tax,
        'discount' => QuotationItemKind.discount,
        'other' => QuotationItemKind.other,
        _ => throw ArgumentError('QuotationItemKind desconhecido: $value'),
      };
}

enum QuotationPublicDecision {
  approved,
  rejected,
  changeRequested;

  String get value => switch (this) {
        QuotationPublicDecision.approved => 'approved',
        QuotationPublicDecision.rejected => 'rejected',
        QuotationPublicDecision.changeRequested => 'change_requested',
      };

  String get label => switch (this) {
        QuotationPublicDecision.approved => 'Aprovar',
        QuotationPublicDecision.rejected => 'Rejeitar',
        QuotationPublicDecision.changeRequested => 'Solicitar alteração',
      };

  static QuotationPublicDecision fromValue(String value) => switch (value) {
        'approved' => QuotationPublicDecision.approved,
        'rejected' => QuotationPublicDecision.rejected,
        'change_requested' => QuotationPublicDecision.changeRequested,
        _ =>
          throw ArgumentError('QuotationPublicDecision desconhecido: $value'),
      };
}

class Quotation {
  const Quotation({
    required this.id,
    required this.tenantId,
    required this.number,
    required this.customerId,
    required this.status,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.createdAt,
    required this.updatedAt,
    this.requestId,
    this.currentVersionId,
    this.validUntil,
    this.notes,
    this.terms,
    this.customerName,
    this.requestTitle,
    this.routeAddress,
    this.routeLatitude,
    this.routeLongitude,
  });

  final String id;
  final String tenantId;
  final int number;
  final String customerId;
  final String? requestId;
  final String? currentVersionId;
  final QuotationStatus status;
  final DateTime? validUntil;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final String? notes;
  final String? terms;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? customerName;
  final String? requestTitle;
  final String? routeAddress;
  final double? routeLatitude;
  final double? routeLongitude;

  String get displayNumber => '#${number.toString().padLeft(5, '0')}';

  Map<String, dynamic> toCreatePayload() => {
        'customer_id': customerId,
        if (requestId != null) 'request_id': requestId,
        if (validUntil != null) 'valid_until': validUntil!.toIso8601String(),
        if (notes != null) 'notes': notes,
        if (terms != null) 'terms': terms,
      };

  Quotation copyWith({
    String? id,
    String? tenantId,
    int? number,
    String? customerId,
    String? requestId,
    String? currentVersionId,
    QuotationStatus? status,
    DateTime? validUntil,
    int? subtotalCents,
    int? discountCents,
    int? taxCents,
    int? totalCents,
    String? notes,
    String? terms,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? customerName,
    String? requestTitle,
    String? routeAddress,
    double? routeLatitude,
    double? routeLongitude,
  }) =>
      Quotation(
        id: id ?? this.id,
        tenantId: tenantId ?? this.tenantId,
        number: number ?? this.number,
        customerId: customerId ?? this.customerId,
        requestId: requestId ?? this.requestId,
        currentVersionId: currentVersionId ?? this.currentVersionId,
        status: status ?? this.status,
        validUntil: validUntil ?? this.validUntil,
        subtotalCents: subtotalCents ?? this.subtotalCents,
        discountCents: discountCents ?? this.discountCents,
        taxCents: taxCents ?? this.taxCents,
        totalCents: totalCents ?? this.totalCents,
        notes: notes ?? this.notes,
        terms: terms ?? this.terms,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        customerName: customerName ?? this.customerName,
        requestTitle: requestTitle ?? this.requestTitle,
        routeAddress: routeAddress ?? this.routeAddress,
        routeLatitude: routeLatitude ?? this.routeLatitude,
        routeLongitude: routeLongitude ?? this.routeLongitude,
      );
}

class QuotationItem {
  const QuotationItem({
    required this.id,
    required this.quotationId,
    required this.versionId,
    required this.kind,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    required this.unitCostCents,
    required this.createdAt,
  });

  final String id;
  final String quotationId;
  final String versionId;
  final QuotationItemKind kind;
  final String description;
  final num quantity;
  final int unitPriceCents;
  final int unitCostCents;
  final DateTime createdAt;

  int get totalCents => (quantity * unitPriceCents).round();
  int get marginCents => totalCents - (quantity * unitCostCents).round();
}

class QuotationDraftItem {
  const QuotationDraftItem({
    required this.kind,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    required this.unitCostCents,
  });

  final QuotationItemKind kind;
  final String description;
  final num quantity;
  final int unitPriceCents;
  final int unitCostCents;

  int get totalCents => (quantity * unitPriceCents).round();

  Map<String, dynamic> toPayload() => {
        'kind': kind.value,
        'description': description.trim(),
        'quantity': quantity,
        'unit_price_cents': unitPriceCents,
        'unit_cost_cents': unitCostCents,
      };
}

Quotation quotationFromRow(Map<String, dynamic> row) {
  final customer = row['customers'];
  final request = row['service_requests'];
  final routeAddress = row['route_address'];
  return Quotation(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    number: (row['number'] as num).toInt(),
    customerId: row['customer_id'] as String,
    requestId: row['request_id'] as String?,
    currentVersionId: row['current_version_id'] as String?,
    status: QuotationStatus.fromValue(row['status'] as String),
    validUntil: row['valid_until'] == null
        ? null
        : DateTime.parse(row['valid_until'] as String),
    subtotalCents: (row['subtotal_cents'] as num).toInt(),
    discountCents: (row['discount_cents'] as num).toInt(),
    taxCents: (row['tax_cents'] as num).toInt(),
    totalCents: (row['total_cents'] as num).toInt(),
    notes: row['notes'] as String?,
    terms: row['terms'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
    customerName:
        customer is Map<String, dynamic> ? customer['name'] as String? : null,
    requestTitle:
        request is Map<String, dynamic> ? request['title'] as String? : null,
    routeAddress: routeAddress is Map<String, dynamic>
        ? _addressLabel(routeAddress)
        : null,
    routeLatitude: routeAddress is Map<String, dynamic>
        ? (routeAddress['latitude'] as num?)?.toDouble()
        : null,
    routeLongitude: routeAddress is Map<String, dynamic>
        ? (routeAddress['longitude'] as num?)?.toDouble()
        : null,
  );
}

String _addressLabel(Map<String, dynamic> row) {
  final street = row['street'] as String? ?? '';
  final number = row['number'] as String? ?? '';
  final complement = row['complement'] as String?;
  final district = row['district'] as String? ?? '';
  final city = row['city'] as String? ?? '';
  final state = row['state'] as String? ?? '';
  final cep = row['cep'] as String?;
  return [
    '$street, $number',
    if (complement != null && complement.trim().isNotEmpty) complement,
    district,
    '$city/$state',
    if (cep != null && cep.trim().isNotEmpty) 'CEP $cep',
  ].where((part) => part.trim().isNotEmpty && part != '/').join(' - ');
}
