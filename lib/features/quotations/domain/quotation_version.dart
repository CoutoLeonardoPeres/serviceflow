/// Versão de um orçamento — snapshot de preços e itens em um momento.
class QuotationVersion {
  const QuotationVersion({
    required this.id,
    required this.versionNumber,
    required this.totalCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.isCurrent,
    required this.createdAt,
  });

  final String id;
  final int versionNumber;
  final int totalCents;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final bool isCurrent;
  final DateTime createdAt;

  String get label => 'Versão $versionNumber${isCurrent ? ' (atual)' : ''}';
}

QuotationVersion quotationVersionFromRow(Map<String, dynamic> row) =>
    QuotationVersion(
      id: row['id'] as String,
      versionNumber: (row['version_number'] as num).toInt(),
      totalCents: (row['total_cents'] as num).toInt(),
      subtotalCents: (row['subtotal_cents'] as num).toInt(),
      discountCents: (row['discount_cents'] as num).toInt(),
      taxCents: (row['tax_cents'] as num).toInt(),
      isCurrent: row['is_current'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

/// Evento do histórico de status de um orçamento.
class QuotationStatusEvent {
  const QuotationStatusEvent({
    required this.id,
    required this.status,
    required this.changedAt,
    this.notes,
  });

  final String id;
  final String status;
  final String? notes;
  final DateTime changedAt;
}

QuotationStatusEvent quotationStatusEventFromRow(Map<String, dynamic> row) =>
    QuotationStatusEvent(
      id: row['id'] as String,
      status: row['status'] as String,
      notes: row['notes'] as String?,
      changedAt: DateTime.parse(row['changed_at'] as String),
    );
