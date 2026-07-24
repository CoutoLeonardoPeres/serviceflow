class Receipt {
  const Receipt({
    required this.id,
    required this.tenantId,
    required this.number,
    required this.receivableId,
    required this.paymentId,
    required this.customerId,
    required this.amountCents,
    required this.issuedAt,
    this.workOrderId,
    this.pdfPath,
    this.customerName,
    this.receivableDescription,
    this.paymentMethod,
    this.paymentReference,
  });

  final String id;
  final String tenantId;
  final int number;
  final String receivableId;
  final String paymentId;
  final String? workOrderId;
  final String customerId;
  final int amountCents;
  final String? pdfPath;
  final DateTime issuedAt;
  final String? customerName;
  final String? receivableDescription;
  final String? paymentMethod;
  final String? paymentReference;

  String get displayNumber => '#${number.toString().padLeft(5, '0')}';
}

Receipt receiptFromRow(Map<String, dynamic> row) {
  final payment = row['payment_records'] as Map<String, dynamic>?;
  final receivable = row['receivables'] as Map<String, dynamic>?;
  return Receipt(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    number: (row['number'] as num).toInt(),
    receivableId: row['receivable_id'] as String,
    paymentId: row['payment_id'] as String,
    workOrderId: row['work_order_id'] as String?,
    customerId: row['customer_id'] as String,
    amountCents: row['amount_cents'] as int,
    pdfPath: row['pdf_path'] as String?,
    issuedAt: DateTime.parse(row['issued_at'] as String),
    customerName:
        (row['customers'] as Map<String, dynamic>?)?['name'] as String?,
    receivableDescription: receivable?['description'] as String?,
    paymentMethod: payment?['method'] as String?,
    paymentReference: payment?['reference'] as String?,
  );
}
