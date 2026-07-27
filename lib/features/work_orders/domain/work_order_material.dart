/// Material lançado em uma OS.
///
/// Corresponde a uma linha de `list_work_order_materials` (migration 0043).
///
/// `fromStock` distingue os dois caminhos permitidos pelo ADR-016 / F3-P2:
/// lançamento vinculado ao catálogo, que baixou saldo, e lançamento em texto
/// livre, que apenas registrou custo. Ambos são válidos — mostrar a diferença
/// permite auditar o quanto do consumo ficou fora do controle de estoque.
class WorkOrderMaterial {
  const WorkOrderMaterial({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitCostCents,
    required this.unitPriceCents,
    required this.totalCostCents,
    required this.totalPriceCents,
    required this.fromStock,
    required this.createdAt,
    this.productId,
    this.productName,
  });

  final String id;
  final String description;
  final double quantity;
  final int unitCostCents;
  final int unitPriceCents;
  final int totalCostCents;
  final int totalPriceCents;

  /// True quando o lançamento gerou movimento de estoque.
  final bool fromStock;

  final String? productId;
  final String? productName;
  final DateTime createdAt;

  /// Produto do catálogo sem controle de saldo: vinculado, mas sem baixa.
  bool get isCatalogWithoutStock => productId != null && !fromStock;

  String get originLabel {
    if (fromStock) return 'Baixado do estoque';
    if (isCatalogWithoutStock) return 'Catálogo, sem controle de saldo';
    return 'Fora do catálogo';
  }
}

WorkOrderMaterial workOrderMaterialFromRow(Map<String, dynamic> row) =>
    WorkOrderMaterial(
      id: row['id'] as String,
      description: row['description'] as String,
      quantity: (row['quantity'] as num).toDouble(),
      unitCostCents: (row['unit_cost_cents'] as num?)?.toInt() ?? 0,
      unitPriceCents: (row['unit_price_cents'] as num?)?.toInt() ?? 0,
      totalCostCents: (row['total_cost_cents'] as num?)?.toInt() ?? 0,
      totalPriceCents: (row['total_price_cents'] as num?)?.toInt() ?? 0,
      fromStock: row['from_stock'] as bool? ?? false,
      productId: row['product_id'] as String?,
      productName: row['product_name'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

/// Retorno do RPC `add_work_order_material`.
class WorkOrderMaterialResult {
  const WorkOrderMaterialResult({
    required this.id,
    required this.totalPriceCents,
    required this.unitCostCents,
    required this.fromStock,
    this.stockMovementId,
  });

  final String id;
  final int totalPriceCents;

  /// Quando veio do estoque, é o custo médio aplicado pelo servidor — que pode
  /// diferir do que foi digitado no formulário.
  final int unitCostCents;

  final bool fromStock;
  final String? stockMovementId;
}

WorkOrderMaterialResult workOrderMaterialResultFromMap(
  Map<String, dynamic> map,
) =>
    WorkOrderMaterialResult(
      id: map['id'] as String,
      totalPriceCents: (map['total_price_cents'] as num?)?.toInt() ?? 0,
      unitCostCents: (map['unit_cost_cents'] as num?)?.toInt() ?? 0,
      fromStock: map['from_stock'] as bool? ?? false,
      stockMovementId: map['stock_movement_id'] as String?,
    );
