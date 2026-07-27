/// Evento do histórico de uma OS.
class WorkOrderEvent {
  const WorkOrderEvent({
    required this.id,
    required this.eventType,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String eventType;
  final String? notes;
  final DateTime createdAt;

  String get label => switch (eventType) {
        'created' => 'Criada',
        'converted_from_quotation' => 'Criada a partir de orçamento',
        'started' => 'Execução iniciada',
        'paused' => 'Pausada',
        'resumed' => 'Retomada',
        'completed' => 'Concluída',
        'cancelled' => 'Cancelada',
        'note' => 'Nota',
        'return_created' => 'Retorno criado',
        _ => eventType,
      };
}

WorkOrderEvent workOrderEventFromRow(Map<String, dynamic> row) =>
    WorkOrderEvent(
      id: row['id'] as String,
      eventType: row['event_type'] as String,
      notes: row['notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
