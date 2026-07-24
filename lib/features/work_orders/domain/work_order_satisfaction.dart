class WorkOrderSatisfaction {
  const WorkOrderSatisfaction({
    required this.id,
    required this.tenantId,
    required this.workOrderId,
    required this.customerId,
    required this.rating,
    required this.createdAt,
    required this.updatedAt,
    this.contactName,
    this.comment,
    this.createdBy,
  });

  final String id;
  final String tenantId;
  final String workOrderId;
  final String customerId;
  final int rating;
  final String? contactName;
  final String? comment;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  String get ratingLabel => switch (rating) {
        1 => 'Muito insatisfeito',
        2 => 'Insatisfeito',
        3 => 'Neutro',
        4 => 'Satisfeito',
        5 => 'Muito satisfeito',
        _ => 'Sem nota',
      };
}

WorkOrderSatisfaction workOrderSatisfactionFromRow(
  Map<String, dynamic> row,
) =>
    WorkOrderSatisfaction(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      workOrderId: row['work_order_id'] as String,
      customerId: row['customer_id'] as String,
      rating: (row['rating'] as num).toInt(),
      contactName: row['contact_name'] as String?,
      comment: row['comment'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      createdBy: row['created_by'] as String?,
    );
