/// Status do pedido de compra.
///
/// Ciclo permitido pela migration 0044:
///   draft → sent → partiallyReceived → received
///   draft/sent → cancelled
///
/// Recebido não volta atrás: correção se faz por ajuste de inventário, que
/// exige `stock.adjust` e motivo. Assim o razão continua append-only.
enum PurchaseOrderStatus {
  draft,
  sent,
  partiallyReceived,
  received,
  cancelled;

  String get value => switch (this) {
        PurchaseOrderStatus.draft => 'draft',
        PurchaseOrderStatus.sent => 'sent',
        PurchaseOrderStatus.partiallyReceived => 'partially_received',
        PurchaseOrderStatus.received => 'received',
        PurchaseOrderStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        PurchaseOrderStatus.draft => 'Rascunho',
        PurchaseOrderStatus.sent => 'Enviado',
        PurchaseOrderStatus.partiallyReceived => 'Recebido em parte',
        PurchaseOrderStatus.received => 'Recebido',
        PurchaseOrderStatus.cancelled => 'Cancelado',
      };

  /// Só pedido enviado ou parcialmente recebido aceita recebimento.
  bool get canReceive =>
      this == PurchaseOrderStatus.sent ||
      this == PurchaseOrderStatus.partiallyReceived;

  bool get canSend => this == PurchaseOrderStatus.draft;

  /// Depois que mercadoria entrou, cancelar apagaria o rastro de algo que
  /// existe fisicamente.
  bool get canCancel =>
      this == PurchaseOrderStatus.draft || this == PurchaseOrderStatus.sent;

  bool get isTerminal =>
      this == PurchaseOrderStatus.received ||
      this == PurchaseOrderStatus.cancelled;
}

PurchaseOrderStatus purchaseOrderStatusFromString(String value) =>
    switch (value) {
      'draft' => PurchaseOrderStatus.draft,
      'sent' => PurchaseOrderStatus.sent,
      'partially_received' => PurchaseOrderStatus.partiallyReceived,
      'received' => PurchaseOrderStatus.received,
      'cancelled' => PurchaseOrderStatus.cancelled,
      _ => PurchaseOrderStatus.draft,
    };

/// Pedido de compra.
///
/// O pedido não movimenta estoque. Só o recebimento gera entrada, com o custo
/// real da nota (F3-P3).
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.number,
    required this.supplierId,
    required this.warehouseId,
    required this.status,
    required this.totalCents,
    required this.createdAt,
    this.supplierName,
    this.warehouseName,
    this.expectedAt,
    this.notes,
    this.receivedAt,
    this.cancellationReason,
  });

  final String id;
  final int number;
  final String supplierId;
  final String warehouseId;
  final PurchaseOrderStatus status;
  final int totalCents;
  final String? supplierName;
  final String? warehouseName;
  final DateTime? expectedAt;
  final String? notes;
  final DateTime? receivedAt;
  final String? cancellationReason;
  final DateTime createdAt;

  String get displayNumber => '#$number';

  /// Pedido aberto: já enviado, ainda não fechado. É o que interessa saber
  /// para não comprar duas vezes o mesmo item.
  bool get isOpen =>
      status == PurchaseOrderStatus.sent ||
      status == PurchaseOrderStatus.partiallyReceived;

  bool get isLate {
    if (!isOpen || expectedAt == null) return false;
    return expectedAt!.isBefore(DateTime.now());
  }
}

PurchaseOrder purchaseOrderFromRow(Map<String, dynamic> row) => PurchaseOrder(
      id: row['id'] as String,
      number: (row['number'] as num).toInt(),
      supplierId: row['supplier_id'] as String,
      warehouseId: row['warehouse_id'] as String,
      status: purchaseOrderStatusFromString(row['status'] as String),
      totalCents: (row['total_cents'] as num?)?.toInt() ?? 0,
      supplierName: row['supplier_name'] as String?,
      warehouseName: row['warehouse_name'] as String?,
      expectedAt: row['expected_at'] == null
          ? null
          : DateTime.parse(row['expected_at'] as String),
      notes: row['notes'] as String?,
      receivedAt: row['received_at'] == null
          ? null
          : DateTime.parse(row['received_at'] as String),
      cancellationReason: row['cancellation_reason'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

/// Item do pedido, com o quanto já foi recebido.
class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantityOrdered,
    required this.quantityReceived,
    required this.unitCostCents,
    required this.totalCostCents,
    this.sku,
  });

  final String id;
  final String productId;
  final String productName;
  final String? sku;
  final String unit;
  final double quantityOrdered;
  final double quantityReceived;
  final int unitCostCents;
  final int totalCostCents;

  double get quantityPending => quantityOrdered - quantityReceived;

  bool get isFullyReceived => quantityReceived >= quantityOrdered;

  String get displayName =>
      (sku == null || sku!.isEmpty) ? productName : '$sku — $productName';
}

PurchaseOrderItem purchaseOrderItemFromRow(Map<String, dynamic> row) =>
    PurchaseOrderItem(
      id: row['id'] as String,
      productId: row['product_id'] as String,
      productName: row['product_name'] as String,
      sku: row['sku'] as String?,
      unit: row['unit'] as String? ?? 'un',
      quantityOrdered: (row['quantity_ordered'] as num?)?.toDouble() ?? 0,
      quantityReceived: (row['quantity_received'] as num?)?.toDouble() ?? 0,
      unitCostCents: (row['unit_cost_cents'] as num?)?.toInt() ?? 0,
      totalCostCents: (row['total_cost_cents'] as num?)?.toInt() ?? 0,
    );

/// Linha a receber, montada na tela de recebimento.
class PurchaseReceiptLine {
  const PurchaseReceiptLine({
    required this.itemId,
    required this.quantity,
    this.unitCostCents,
  });

  final String itemId;
  final double quantity;

  /// Preço da nota, quando diferente do cotado. Null mantém o do pedido.
  final int? unitCostCents;

  Map<String, dynamic> toJson() => {
        'item_id': itemId,
        'quantity': quantity,
        if (unitCostCents != null) 'unit_cost_cents': unitCostCents,
      };
}
