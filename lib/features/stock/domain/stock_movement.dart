/// Tipo de movimento do razão de estoque.
///
/// A direção vem daqui, não do sinal da quantidade: `quantity` é sempre
/// positiva no banco (migration 0042).
enum StockMovementKind {
  entry,
  exit,
  adjustment;

  /// Valor gravado em `stock_movements.kind`.
  String get value => switch (this) {
        StockMovementKind.entry => 'in',
        StockMovementKind.exit => 'out',
        StockMovementKind.adjustment => 'adjustment',
      };

  String get label => switch (this) {
        StockMovementKind.entry => 'Entrada',
        StockMovementKind.exit => 'Saída',
        StockMovementKind.adjustment => 'Ajuste',
      };

  /// Sinal para exibição da quantidade na UI.
  ///
  /// Ajuste não tem sinal fixo — o movimento registra o módulo da diferença, e
  /// o saldo resultante é que diz se subiu ou desceu.
  String get sign => switch (this) {
        StockMovementKind.entry => '+',
        StockMovementKind.exit => '−',
        StockMovementKind.adjustment => '±',
      };
}

StockMovementKind stockMovementKindFromString(String value) => switch (value) {
      'in' => StockMovementKind.entry,
      'out' => StockMovementKind.exit,
      'adjustment' => StockMovementKind.adjustment,
      _ => StockMovementKind.adjustment,
    };

/// Lançamento do razão de estoque.
///
/// Append-only: não existe edição nem exclusão. Correção se faz com movimento
/// contrário. Cada lançamento carrega o saldo resultante (`quantityAfter`,
/// `valueAfterCents`) para que o extrato seja reconstruível sem recalcular.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.kind,
    required this.quantity,
    required this.unitCostCents,
    required this.totalCostCents,
    required this.quantityAfter,
    required this.valueAfterCents,
    required this.createdAt,
    this.reason,
    this.relatedEntity,
    this.relatedEntityId,
    this.productName,
    this.warehouseName,
    this.lotId,
    this.lotCode,
  });

  final String id;
  final StockMovementKind kind;
  final double quantity;

  /// Custo unitário do movimento. Na saída, é o custo médio vigente no momento.
  final int unitCostCents;
  final int totalCostCents;

  /// Saldo resultante logo após este movimento.
  final double quantityAfter;
  final int valueAfterCents;

  final String? reason;
  final String? relatedEntity;
  final String? relatedEntityId;
  final String? productName;
  final String? warehouseName;
  final DateTime createdAt;

  /// Lote/série do movimento (ADR-024, migration 0047). Null = sem rastreio.
  final String? lotId;
  final String? lotCode;

  /// Custo médio do saldo depois deste movimento.
  int get averageCostAfterCents =>
      quantityAfter <= 0 ? 0 : (valueAfterCents / quantityAfter).round();
}

StockMovement stockMovementFromRow(Map<String, dynamic> row) => StockMovement(
      id: row['id'] as String,
      kind: stockMovementKindFromString(row['kind'] as String),
      quantity: (row['quantity'] as num).toDouble(),
      unitCostCents: (row['unit_cost_cents'] as num?)?.toInt() ?? 0,
      totalCostCents: (row['total_cost_cents'] as num?)?.toInt() ?? 0,
      quantityAfter: (row['quantity_after'] as num?)?.toDouble() ?? 0,
      valueAfterCents: (row['value_after_cents'] as num?)?.toInt() ?? 0,
      reason: row['reason'] as String?,
      relatedEntity: row['related_entity'] as String?,
      relatedEntityId: row['related_entity_id'] as String?,
      productName: row['product_name'] as String?,
      warehouseName: row['warehouse_name'] as String?,
      lotId: row['lot_id'] as String?,
      lotCode: row['lot_code'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
