/// Historico de um agendamento — alimenta relatorios de produtividade e
/// custo. Gravado por trigger no banco, nunca pela aplicacao.
enum AppointmentEventType {
  scheduled,
  rescheduled,
  cancelled,
  statusChanged;

  String get value => switch (this) {
        AppointmentEventType.scheduled => 'scheduled',
        AppointmentEventType.rescheduled => 'rescheduled',
        AppointmentEventType.cancelled => 'cancelled',
        AppointmentEventType.statusChanged => 'status_changed',
      };

  String get label => switch (this) {
        AppointmentEventType.scheduled => 'Agendado',
        AppointmentEventType.rescheduled => 'Reagendado',
        AppointmentEventType.cancelled => 'Cancelado',
        AppointmentEventType.statusChanged => 'Status alterado',
      };

  static AppointmentEventType fromValue(String value) => switch (value) {
        'scheduled' => AppointmentEventType.scheduled,
        'rescheduled' => AppointmentEventType.rescheduled,
        'cancelled' => AppointmentEventType.cancelled,
        'status_changed' => AppointmentEventType.statusChanged,
        _ => throw ArgumentError('AppointmentEventType desconhecido: $value'),
      };
}

class AppointmentEvent {
  const AppointmentEvent({
    required this.id,
    required this.appointmentId,
    required this.type,
    required this.kind,
    required this.referenceId,
    required this.customerId,
    required this.createdAt,
    this.technicianUserId,
    this.technicianName,
    this.previousStatus,
    this.newStatus,
    this.previousStart,
    this.newStart,
    this.reason,
  });

  final String id;
  final String appointmentId;
  final AppointmentEventType type;
  final String kind;
  final String referenceId;
  final String customerId;
  final DateTime createdAt;
  final String? technicianUserId;
  final String? technicianName;
  final String? previousStatus;
  final String? newStatus;
  final DateTime? previousStart;
  final DateTime? newStart;
  final String? reason;
}

AppointmentEvent appointmentEventFromRow(Map<String, dynamic> row) {
  final profile = row['profiles'];

  DateTime? parseNullable(String key) {
    final value = row[key];
    return value is String ? DateTime.parse(value) : null;
  }

  return AppointmentEvent(
    id: row['id'] as String,
    appointmentId: row['appointment_id'] as String,
    type: AppointmentEventType.fromValue(row['event_type'] as String),
    kind: row['kind'] as String,
    referenceId: row['reference_id'] as String,
    customerId: row['customer_id'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    technicianUserId: row['technician_user_id'] as String?,
    technicianName: profile is Map<String, dynamic>
        ? profile['full_name'] as String?
        : null,
    previousStatus: row['previous_status'] as String?,
    newStatus: row['new_status'] as String?,
    previousStart: parseNullable('previous_start'),
    newStart: parseNullable('new_start'),
    reason: row['reason'] as String?,
  );
}
