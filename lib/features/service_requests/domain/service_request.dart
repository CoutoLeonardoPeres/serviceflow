enum ServiceRequestStatus {
  draft,
  opened,
  triage,
  awaitingCustomer,
  scheduled,
  convertedToQuote,
  convertedToWorkOrder,
  cancelled,
  closed;

  String get value => switch (this) {
        ServiceRequestStatus.draft => 'draft',
        ServiceRequestStatus.opened => 'opened',
        ServiceRequestStatus.triage => 'triage',
        ServiceRequestStatus.awaitingCustomer => 'awaiting_customer',
        ServiceRequestStatus.scheduled => 'scheduled',
        ServiceRequestStatus.convertedToQuote => 'converted_to_quote',
        ServiceRequestStatus.convertedToWorkOrder => 'converted_to_work_order',
        ServiceRequestStatus.cancelled => 'cancelled',
        ServiceRequestStatus.closed => 'closed',
      };

  String get label => switch (this) {
        ServiceRequestStatus.draft => 'Rascunho',
        ServiceRequestStatus.opened => 'Aberto',
        ServiceRequestStatus.triage => 'Triagem',
        ServiceRequestStatus.awaitingCustomer => 'Aguardando cliente',
        ServiceRequestStatus.scheduled => 'Agendado',
        ServiceRequestStatus.convertedToQuote => 'Virou orçamento',
        ServiceRequestStatus.convertedToWorkOrder => 'Virou OS',
        ServiceRequestStatus.cancelled => 'Cancelado',
        ServiceRequestStatus.closed => 'Fechado',
      };

  bool get isTerminal =>
      this == ServiceRequestStatus.cancelled ||
      this == ServiceRequestStatus.closed;

  static ServiceRequestStatus fromValue(String value) => switch (value) {
        'draft' => ServiceRequestStatus.draft,
        'opened' => ServiceRequestStatus.opened,
        'triage' => ServiceRequestStatus.triage,
        'awaiting_customer' => ServiceRequestStatus.awaitingCustomer,
        'scheduled' => ServiceRequestStatus.scheduled,
        'converted_to_quote' => ServiceRequestStatus.convertedToQuote,
        'converted_to_work_order' => ServiceRequestStatus.convertedToWorkOrder,
        'cancelled' => ServiceRequestStatus.cancelled,
        'closed' => ServiceRequestStatus.closed,
        _ => throw ArgumentError('ServiceRequestStatus desconhecido: $value'),
      };
}

enum ServiceRequestChannel {
  phone,
  whatsapp,
  email,
  form,
  inPerson;

  String get value => switch (this) {
        ServiceRequestChannel.phone => 'phone',
        ServiceRequestChannel.whatsapp => 'whatsapp',
        ServiceRequestChannel.email => 'email',
        ServiceRequestChannel.form => 'form',
        ServiceRequestChannel.inPerson => 'in_person',
      };

  String get label => switch (this) {
        ServiceRequestChannel.phone => 'Telefone',
        ServiceRequestChannel.whatsapp => 'WhatsApp',
        ServiceRequestChannel.email => 'E-mail',
        ServiceRequestChannel.form => 'Formulário',
        ServiceRequestChannel.inPerson => 'Presencial',
      };

  static ServiceRequestChannel fromValue(String value) => switch (value) {
        'phone' => ServiceRequestChannel.phone,
        'whatsapp' => ServiceRequestChannel.whatsapp,
        'email' => ServiceRequestChannel.email,
        'form' => ServiceRequestChannel.form,
        'in_person' => ServiceRequestChannel.inPerson,
        _ => throw ArgumentError('ServiceRequestChannel desconhecido: $value'),
      };
}

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.tenantId,
    required this.number,
    required this.customerId,
    required this.title,
    required this.description,
    required this.channel,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.requesterContactId,
    this.addressId,
    this.categoryId,
    this.priorityId,
    this.availabilityNotes,
    this.assignedTo,
    this.createdBy,
    this.updatedBy,
    this.customerName,
    this.categoryName,
    this.priorityName,
    this.priorityLevel,
    this.routeAddress,
    this.routeLatitude,
    this.routeLongitude,
  });

  final String id;
  final String tenantId;
  final int number;
  final String customerId;
  final String? requesterContactId;
  final String? addressId;
  final String? categoryId;
  final String? priorityId;
  final String title;
  final String description;
  final String? availabilityNotes;
  final ServiceRequestChannel channel;
  final ServiceRequestStatus status;
  final String? assignedTo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;
  final String? customerName;
  final String? categoryName;
  final String? priorityName;
  final int? priorityLevel;
  final String? routeAddress;
  final double? routeLatitude;
  final double? routeLongitude;

  String get displayNumber => '#${number.toString().padLeft(5, '0')}';

  Map<String, dynamic> toInsertPayload() => {
        'customer_id': customerId,
        if (requesterContactId != null)
          'requester_contact_id': requesterContactId,
        if (addressId != null) 'address_id': addressId,
        if (categoryId != null) 'category_id': categoryId,
        if (priorityId != null) 'priority_id': priorityId,
        'title': title,
        'description': description,
        if (availabilityNotes != null) 'availability_notes': availabilityNotes,
        'channel': channel.value,
        'status': status.value,
        if (assignedTo != null) 'assigned_to': assignedTo,
      };

  ServiceRequest copyWith({
    String? id,
    String? tenantId,
    int? number,
    String? customerId,
    String? requesterContactId,
    String? addressId,
    String? categoryId,
    String? priorityId,
    String? title,
    String? description,
    String? availabilityNotes,
    ServiceRequestChannel? channel,
    ServiceRequestStatus? status,
    String? assignedTo,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
    String? customerName,
    String? categoryName,
    String? priorityName,
    int? priorityLevel,
    String? routeAddress,
    double? routeLatitude,
    double? routeLongitude,
  }) =>
      ServiceRequest(
        id: id ?? this.id,
        tenantId: tenantId ?? this.tenantId,
        number: number ?? this.number,
        customerId: customerId ?? this.customerId,
        requesterContactId: requesterContactId ?? this.requesterContactId,
        addressId: addressId ?? this.addressId,
        categoryId: categoryId ?? this.categoryId,
        priorityId: priorityId ?? this.priorityId,
        title: title ?? this.title,
        description: description ?? this.description,
        availabilityNotes: availabilityNotes ?? this.availabilityNotes,
        channel: channel ?? this.channel,
        status: status ?? this.status,
        assignedTo: assignedTo ?? this.assignedTo,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        createdBy: createdBy ?? this.createdBy,
        updatedBy: updatedBy ?? this.updatedBy,
        customerName: customerName ?? this.customerName,
        categoryName: categoryName ?? this.categoryName,
        priorityName: priorityName ?? this.priorityName,
        priorityLevel: priorityLevel ?? this.priorityLevel,
        routeAddress: routeAddress ?? this.routeAddress,
        routeLatitude: routeLatitude ?? this.routeLatitude,
        routeLongitude: routeLongitude ?? this.routeLongitude,
      );
}

ServiceRequest serviceRequestFromRow(Map<String, dynamic> row) {
  final customer = row['customers'];
  final category = row['service_categories'];
  final priority = row['service_priorities'];
  final routeAddress = row['route_address'];

  return ServiceRequest(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    number: (row['number'] as num).toInt(),
    customerId: row['customer_id'] as String,
    requesterContactId: row['requester_contact_id'] as String?,
    addressId: row['address_id'] as String?,
    categoryId: row['category_id'] as String?,
    priorityId: row['priority_id'] as String?,
    title: row['title'] as String,
    description: row['description'] as String,
    availabilityNotes: row['availability_notes'] as String?,
    channel: ServiceRequestChannel.fromValue(row['channel'] as String),
    status: ServiceRequestStatus.fromValue(row['status'] as String),
    assignedTo: row['assigned_to'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
    createdBy: row['created_by'] as String?,
    updatedBy: row['updated_by'] as String?,
    customerName:
        customer is Map<String, dynamic> ? customer['name'] as String? : null,
    categoryName:
        category is Map<String, dynamic> ? category['name'] as String? : null,
    priorityName:
        priority is Map<String, dynamic> ? priority['name'] as String? : null,
    priorityLevel: priority is Map<String, dynamic>
        ? (priority['level'] as num?)?.toInt()
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
