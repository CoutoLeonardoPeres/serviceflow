enum WorkOrderStatus {
  draft,
  opened,
  scheduled,
  inProgress,
  awaitingCustomer,
  paused,
  done,
  cancelled;

  String get value => switch (this) {
        WorkOrderStatus.draft => 'draft',
        WorkOrderStatus.opened => 'opened',
        WorkOrderStatus.scheduled => 'scheduled',
        WorkOrderStatus.inProgress => 'in_progress',
        WorkOrderStatus.awaitingCustomer => 'awaiting_customer',
        WorkOrderStatus.paused => 'paused',
        WorkOrderStatus.done => 'done',
        WorkOrderStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        WorkOrderStatus.draft => 'Rascunho',
        WorkOrderStatus.opened => 'Aberta',
        WorkOrderStatus.scheduled => 'Agendada',
        WorkOrderStatus.inProgress => 'Em execução',
        WorkOrderStatus.awaitingCustomer => 'Aguardando cliente',
        WorkOrderStatus.paused => 'Pausada',
        WorkOrderStatus.done => 'Concluída',
        WorkOrderStatus.cancelled => 'Cancelada',
      };

  static WorkOrderStatus fromValue(String value) => switch (value) {
        'draft' => WorkOrderStatus.draft,
        'opened' => WorkOrderStatus.opened,
        'scheduled' => WorkOrderStatus.scheduled,
        'in_progress' => WorkOrderStatus.inProgress,
        'awaiting_customer' => WorkOrderStatus.awaitingCustomer,
        'paused' => WorkOrderStatus.paused,
        'done' => WorkOrderStatus.done,
        'cancelled' => WorkOrderStatus.cancelled,
        _ => throw ArgumentError('WorkOrderStatus desconhecido: $value'),
      };
}

enum WorkOrderItemKind {
  service,
  laborHour,
  material,
  equipment,
  travel,
  extra,
  other;

  String get value => switch (this) {
        WorkOrderItemKind.service => 'service',
        WorkOrderItemKind.laborHour => 'labor_hour',
        WorkOrderItemKind.material => 'material',
        WorkOrderItemKind.equipment => 'equipment',
        WorkOrderItemKind.travel => 'travel',
        WorkOrderItemKind.extra => 'extra',
        WorkOrderItemKind.other => 'other',
      };

  String get label => switch (this) {
        WorkOrderItemKind.service => 'Serviço',
        WorkOrderItemKind.laborHour => 'Hora técnica',
        WorkOrderItemKind.material => 'Material',
        WorkOrderItemKind.equipment => 'Equipamento',
        WorkOrderItemKind.travel => 'Deslocamento',
        WorkOrderItemKind.extra => 'Extra',
        WorkOrderItemKind.other => 'Outro',
      };
}

class WorkOrder {
  const WorkOrder({
    required this.id,
    required this.tenantId,
    required this.number,
    required this.customerId,
    required this.status,
    required this.title,
    required this.description,
    required this.totalCents,
    required this.createdAt,
    required this.updatedAt,
    this.requestId,
    this.quotationId,
    this.addressId,
    this.scheduledStart,
    this.scheduledEnd,
    this.completedAt,
    this.customerName,
    this.requestTitle,
    this.quotationNumber,
    this.routeAddress,
    this.routeLatitude,
    this.routeLongitude,
  });

  final String id;
  final String tenantId;
  final int number;
  final String customerId;
  final String? requestId;
  final String? quotationId;
  final String? addressId;
  final WorkOrderStatus status;
  final String title;
  final String description;
  final int totalCents;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? customerName;
  final String? requestTitle;
  final int? quotationNumber;
  final String? routeAddress;
  final double? routeLatitude;
  final double? routeLongitude;

  String get displayNumber => '#${number.toString().padLeft(5, '0')}';

  Map<String, dynamic> toInsertPayload() => {
        'customer_id': customerId,
        if (requestId != null) 'request_id': requestId,
        if (quotationId != null) 'quotation_id': quotationId,
        if (addressId != null) 'address_id': addressId,
        'status': status.value,
        'title': title,
        'description': description,
        'total_cents': totalCents,
        if (scheduledStart != null)
          'scheduled_start': scheduledStart!.toUtc().toIso8601String(),
        if (scheduledEnd != null)
          'scheduled_end': scheduledEnd!.toUtc().toIso8601String(),
      };
}

class WorkOrderItem {
  const WorkOrderItem({
    required this.id,
    required this.workOrderId,
    required this.kind,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
    required this.createdAt,
  });

  final String id;
  final String workOrderId;
  final String kind;
  final String description;
  final num quantity;
  final int unitPriceCents;
  final int totalCents;
  final DateTime createdAt;
}

class WorkOrderDraftItem {
  const WorkOrderDraftItem({
    required this.kind,
    required this.description,
    required this.quantity,
    required this.unitPriceCents,
  });

  final WorkOrderItemKind kind;
  final String description;
  final num quantity;
  final int unitPriceCents;

  int get totalCents => (quantity * unitPriceCents).round();

  Map<String, dynamic> toInsertPayload(String workOrderId) => {
        'work_order_id': workOrderId,
        'kind': kind.value,
        'description': description.trim(),
        'quantity': quantity,
        'unit_price_cents': unitPriceCents,
        'total_cents': totalCents,
      };
}

WorkOrderItem workOrderItemFromRow(Map<String, dynamic> row) => WorkOrderItem(
      id: row['id'] as String,
      workOrderId: row['work_order_id'] as String,
      kind: row['kind'] as String,
      description: row['description'] as String,
      quantity: row['quantity'] as num,
      unitPriceCents: (row['unit_price_cents'] as num).toInt(),
      totalCents: (row['total_cents'] as num).toInt(),
      createdAt: DateTime.parse(row['created_at'] as String),
    );

WorkOrder workOrderFromRow(Map<String, dynamic> row) {
  final customer = row['customers'];
  final request = row['service_requests'];
  final quotation = row['quotations'];
  final routeAddress = row['route_address'];

  DateTime? parseNullableDate(String key) {
    final value = row[key];
    return value is String ? DateTime.parse(value) : null;
  }

  return WorkOrder(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    number: (row['number'] as num).toInt(),
    customerId: row['customer_id'] as String,
    requestId: row['request_id'] as String?,
    quotationId: row['quotation_id'] as String?,
    addressId: row['address_id'] as String?,
    status: WorkOrderStatus.fromValue(row['status'] as String),
    title: row['title'] as String,
    description: row['description'] as String,
    totalCents: (row['total_cents'] as num).toInt(),
    scheduledStart: parseNullableDate('scheduled_start'),
    scheduledEnd: parseNullableDate('scheduled_end'),
    completedAt: parseNullableDate('completed_at'),
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
    customerName:
        customer is Map<String, dynamic> ? customer['name'] as String? : null,
    requestTitle:
        request is Map<String, dynamic> ? request['title'] as String? : null,
    quotationNumber: quotation is Map<String, dynamic>
        ? (quotation['number'] as num?)?.toInt()
        : null,
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
