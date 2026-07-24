import 'receipt.dart';

enum ReceivableStatus {
  open('open', 'Aberto'),
  partiallyPaid('partially_paid', 'Parcial'),
  paid('paid', 'Pago'),
  cancelled('cancelled', 'Cancelado');

  const ReceivableStatus(this.value, this.label);

  final String value;
  final String label;

  static ReceivableStatus fromValue(String value) {
    return ReceivableStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => ReceivableStatus.open,
    );
  }
}

class Receivable {
  const Receivable({
    required this.id,
    required this.tenantId,
    required this.customerId,
    required this.description,
    required this.amountCents,
    required this.balanceCents,
    required this.status,
    required this.dueDate,
    required this.createdAt,
    required this.updatedAt,
    this.workOrderId,
    this.customerName,
    this.workOrderNumber,
    this.latestReceipt,
  });

  final String id;
  final String tenantId;
  final String customerId;
  final String? workOrderId;
  final String description;
  final int amountCents;
  final int balanceCents;
  final ReceivableStatus status;
  final DateTime dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? customerName;
  final int? workOrderNumber;
  final Receipt? latestReceipt;

  bool get isOverdue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return balanceCents > 0 && dueDate.isBefore(today);
  }
}

Receivable receivableFromRow(Map<String, dynamic> row) {
  final receipts = row['receipts'] as List<dynamic>?;
  final latestReceipt = receipts == null || receipts.isEmpty
      ? null
      : receiptFromRow({
          ...receipts.first as Map<String, dynamic>,
          'customers': row['customers'],
          'receivables': {'description': row['description']},
        });

  return Receivable(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    customerId: row['customer_id'] as String,
    workOrderId: row['work_order_id'] as String?,
    description: row['description'] as String,
    amountCents: row['amount_cents'] as int,
    balanceCents: row['balance_cents'] as int,
    status: ReceivableStatus.fromValue(row['status'] as String),
    dueDate: DateTime.parse(row['due_date'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
    customerName:
        (row['customers'] as Map<String, dynamic>?)?['name'] as String?,
    workOrderNumber:
        ((row['work_orders'] as Map<String, dynamic>?)?['number'] as num?)
            ?.toInt(),
    latestReceipt: latestReceipt,
  );
}
