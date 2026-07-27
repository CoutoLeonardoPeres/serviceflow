/// Status de uma sessão de inventário.
enum StockCountStatus {
  open,
  applied,
  cancelled;

  String get value => name;

  String get label => switch (this) {
        StockCountStatus.open => 'Em contagem',
        StockCountStatus.applied => 'Aplicado',
        StockCountStatus.cancelled => 'Cancelado',
      };

  bool get isOpen => this == StockCountStatus.open;
}

StockCountStatus stockCountStatusFromString(String value) => switch (value) {
      'open' => StockCountStatus.open,
      'applied' => StockCountStatus.applied,
      'cancelled' => StockCountStatus.cancelled,
      _ => StockCountStatus.open,
    };

/// Sessão de inventário cíclico.
///
/// Persistida em vez de ajuste em lote direto: a contagem real se estende no
/// tempo, e o registro de quem contou o quê é a justificativa auditável do
/// ajuste que vem depois.
class StockCount {
  const StockCount({
    required this.id,
    required this.number,
    required this.warehouseId,
    required this.status,
    required this.createdAt,
    this.warehouseName,
    this.notes,
    this.appliedAt,
  });

  final String id;
  final int number;
  final String warehouseId;
  final String? warehouseName;
  final StockCountStatus status;
  final String? notes;
  final DateTime? appliedAt;
  final DateTime createdAt;

  String get displayNumber => '#$number';
}

StockCount stockCountFromRow(Map<String, dynamic> row) => StockCount(
      id: row['id'] as String,
      number: (row['number'] as num).toInt(),
      warehouseId: row['warehouse_id'] as String,
      warehouseName: row['warehouse_name'] as String?,
      status: stockCountStatusFromString(row['status'] as String),
      notes: row['notes'] as String?,
      appliedAt: row['applied_at'] == null
          ? null
          : DateTime.parse(row['applied_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );

/// Item de uma contagem.
///
/// `systemQuantity` é o saldo no momento em que a contagem foi aberta. Na
/// aplicação o servidor relê o saldo atual, porque ele pode ter mudado desde
/// então — por isso a diferença mostrada aqui é indicativa, não definitiva.
class StockCountItem {
  const StockCountItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.systemQuantity,
    this.sku,
    this.countedQuantity,
    this.difference,
  });

  final String id;
  final String productId;
  final String productName;
  final String? sku;
  final String unit;
  final double systemQuantity;

  /// Null enquanto o item não foi contado.
  final double? countedQuantity;

  final double? difference;

  bool get isCounted => countedQuantity != null;

  bool get hasDivergence =>
      countedQuantity != null && countedQuantity != systemQuantity;

  String get displayName =>
      (sku == null || sku!.isEmpty) ? productName : '$sku — $productName';
}

StockCountItem stockCountItemFromRow(Map<String, dynamic> row) =>
    StockCountItem(
      id: row['id'] as String,
      productId: row['product_id'] as String,
      productName: row['product_name'] as String,
      sku: row['sku'] as String?,
      unit: row['unit'] as String? ?? 'un',
      systemQuantity: (row['system_quantity'] as num?)?.toDouble() ?? 0,
      countedQuantity: (row['counted_quantity'] as num?)?.toDouble(),
      difference: (row['difference'] as num?)?.toDouble(),
    );

/// Resultado da aplicação de uma contagem.
class StockCountApplyResult {
  const StockCountApplyResult({
    required this.adjusted,
    required this.unchanged,
  });

  /// Itens que geraram ajuste por divergirem do saldo.
  final int adjusted;

  /// Itens conferidos que batiam com o sistema.
  final int unchanged;
}
