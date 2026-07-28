enum AppointmentKind {
  visit,
  workOrder;

  String get value => switch (this) {
        AppointmentKind.visit => 'visit',
        AppointmentKind.workOrder => 'work_order',
      };

  String get label => switch (this) {
        AppointmentKind.visit => 'Visita técnica',
        AppointmentKind.workOrder => 'Ordem de serviço',
      };

  static AppointmentKind fromValue(String value) => switch (value) {
        'visit' => AppointmentKind.visit,
        'work_order' => AppointmentKind.workOrder,
        _ => throw ArgumentError('AppointmentKind desconhecido: $value'),
      };
}

enum AppointmentStatus {
  scheduled,
  confirmed,
  done,
  cancelled,
  noShow;

  String get value => switch (this) {
        AppointmentStatus.scheduled => 'scheduled',
        AppointmentStatus.confirmed => 'confirmed',
        AppointmentStatus.done => 'done',
        AppointmentStatus.cancelled => 'cancelled',
        AppointmentStatus.noShow => 'no_show',
      };

  String get label => switch (this) {
        AppointmentStatus.scheduled => 'Agendado',
        AppointmentStatus.confirmed => 'Confirmado',
        AppointmentStatus.done => 'Realizado',
        AppointmentStatus.cancelled => 'Cancelado',
        AppointmentStatus.noShow => 'Não compareceu',
      };

  bool get isTerminal =>
      this == AppointmentStatus.done ||
      this == AppointmentStatus.cancelled ||
      this == AppointmentStatus.noShow;

  static AppointmentStatus fromValue(String value) => switch (value) {
        'scheduled' => AppointmentStatus.scheduled,
        'confirmed' => AppointmentStatus.confirmed,
        'done' => AppointmentStatus.done,
        'cancelled' => AppointmentStatus.cancelled,
        'no_show' => AppointmentStatus.noShow,
        _ => throw ArgumentError('AppointmentStatus desconhecido: $value'),
      };
}

class Appointment {
  Appointment({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.referenceId,
    required this.customerId,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.addressId,
    this.notes,
    this.createdBy,
    this.updatedBy,
    this.customerName,
    this.serviceRequestTitle,
    this.technicianUserId,
    this.technicianName,
    this.technicians = const [],
  }) {
    if (!scheduledEnd.isAfter(scheduledStart)) {
      throw ArgumentError('Agendamento deve ter termino apos o inicio.');
    }
  }

  final String id;
  final String tenantId;
  final AppointmentKind kind;
  final String referenceId;
  final String customerId;
  final String? addressId;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final AppointmentStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;
  final String? customerName;
  final String? serviceRequestTitle;
  /// Primeiro atribuído — usado onde a UI precisa de um só profissional.
  final String? technicianUserId;
  final String? technicianName;

  /// Todos os profissionais ativos no atendimento, em ordem de atribuição.
  final List<AppointmentTechnician> technicians;

  Duration get duration => scheduledEnd.difference(scheduledStart);

  /// [professionalId] é o que manda: parceiro externo sem login do sistema
  /// não tem [technicianUserId], mas continua agendável.
  Map<String, dynamic> toScheduleParams({
    required String professionalId,
    String? technicianUserId,
  }) =>
      {
        'p_kind': kind.value,
        'p_reference_id': referenceId,
        'p_customer_id': customerId,
        'p_address_id': addressId,
        'p_scheduled_start': scheduledStart.toUtc().toIso8601String(),
        'p_scheduled_end': scheduledEnd.toUtc().toIso8601String(),
        'p_technician_user_id': technicianUserId,
        'p_professional_id': professionalId,
        'p_notes': notes,
      };
}

class AppointmentTechnician {
  const AppointmentTechnician({
    required this.professionalId,
    this.userId,
    this.name,
  });

  /// Sempre presente: é por ele que a agenda identifica o profissional.
  final String professionalId;

  /// Só existe para quem tem login no sistema — parceiro externo não tem.
  final String? userId;
  final String? name;

  String get label => name ?? 'Profissional';
}

Appointment appointmentFromRow(Map<String, dynamic> row) {
  final customer = row['customers'];
  final serviceRequest = row['service_requests'];
  final assignments = row['appointment_assignments'];

  final technicians = <AppointmentTechnician>[
    if (assignments is List)
      for (final entry in assignments)
        if (entry is Map &&
            entry['revoked_at'] == null &&
            entry['professional_id'] is String)
          AppointmentTechnician(
            professionalId: entry['professional_id'] as String,
            userId: entry['technician_user_id'] as String?,
            name: entry['profiles'] is Map
                ? (entry['profiles'] as Map)['full_name'] as String?
                : null,
          ),
  ];

  final assignment = assignments is List && assignments.isNotEmpty
      ? assignments.first as Map<String, dynamic>
      : null;
  final profile = assignment?['profiles'];

  return Appointment(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    kind: AppointmentKind.fromValue(row['kind'] as String),
    referenceId: row['reference_id'] as String,
    customerId: row['customer_id'] as String,
    addressId: row['address_id'] as String?,
    scheduledStart: DateTime.parse(row['scheduled_start'] as String),
    scheduledEnd: DateTime.parse(row['scheduled_end'] as String),
    status: AppointmentStatus.fromValue(row['status'] as String),
    notes: row['notes'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
    createdBy: row['created_by'] as String?,
    updatedBy: row['updated_by'] as String?,
    customerName:
        customer is Map<String, dynamic> ? customer['name'] as String? : null,
    serviceRequestTitle: serviceRequest is Map<String, dynamic>
        ? serviceRequest['title'] as String?
        : null,
    technicianUserId: technicians.isNotEmpty
        ? technicians.first.userId
        : assignment?['technician_user_id'] as String?,
    technicianName: technicians.isNotEmpty
        ? technicians.first.name
        : profile is Map<String, dynamic>
            ? profile['full_name'] as String?
            : null,
    technicians: technicians,
  );
}
