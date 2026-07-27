import 'receivable.dart' show ReceivableStatus;

/// Conta a pagar (F4-P1, ADR-025).
///
/// Nasce automaticamente no recebimento do pedido de compra — não há
/// inserção manual nesta entrega. `status` reaproveita [ReceivableStatus]:
/// o vocabulário (aberto/parcial/pago/cancelado) é idêntico ao de
/// `receivables`, então duplicar o enum só para o nome mudar seria
/// redundância sem ganho.
class Payable {
  const Payable({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseOrderId,
    required this.purchaseOrderNumber,
    required this.description,
    required this.dueDate,
    required this.amountCents,
    required this.balanceCents,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String purchaseOrderId;
  final int purchaseOrderNumber;
  final String description;
  final DateTime dueDate;
  final int amountCents;
  final int balanceCents;
  final ReceivableStatus status;
  final DateTime createdAt;

  bool get isOverdue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return balanceCents > 0 && dueDate.isBefore(today);
  }
}

Payable payableFromRow(Map<String, dynamic> row) => Payable(
      id: row['id'] as String,
      supplierId: row['supplier_id'] as String,
      supplierName: row['supplier_name'] as String,
      purchaseOrderId: row['purchase_order_id'] as String,
      purchaseOrderNumber: (row['purchase_order_number'] as num).toInt(),
      description: row['description'] as String,
      dueDate: DateTime.parse(row['due_date'] as String),
      amountCents: (row['amount_cents'] as num).toInt(),
      balanceCents: (row['balance_cents'] as num).toInt(),
      status: ReceivableStatus.fromValue(row['status'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
