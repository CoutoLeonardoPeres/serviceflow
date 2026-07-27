import 'product.dart';

/// Saldo de um produto em um depósito.
///
/// Corresponde a uma linha de `list_stock_balances` (migration 0042).
///
/// O custo médio vem pronto do servidor. **Não recalcule no cliente**: o
/// servidor guarda `totalValueCents` como fonte da verdade e deriva o médio a
/// partir dele (ADR-020). Recalcular a partir de um médio arredondado
/// introduziria divergência com o razão.
class StockBalance {
  const StockBalance({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.warehouseId,
    required this.warehouseName,
    required this.quantity,
    required this.minQuantity,
    required this.totalValueCents,
    required this.averageUnitCostCents,
    required this.belowMinimum,
    required this.updatedAt,
    this.sku,
  });

  final String productId;
  final String productName;
  final String? sku;
  final ProductUnit unit;
  final String warehouseId;
  final String warehouseName;
  final double quantity;
  final double minQuantity;
  final int totalValueCents;
  final int averageUnitCostCents;

  /// Calculado pelo servidor: `minQuantity > 0 AND quantity < minQuantity`.
  final bool belowMinimum;

  final DateTime updatedAt;

  bool get isEmpty => quantity <= 0;

  String get displayName =>
      (sku == null || sku!.isEmpty) ? productName : '$sku — $productName';

  /// Quantidade formatada sem casas decimais desnecessárias.
  ///
  /// O banco usa numeric(12,3); mostrar "10" é melhor que "10.000", mas
  /// "0.5" precisa manter a casa.
  String get quantityLabel {
    final asInt = quantity.truncate();
    if (quantity == asInt) return '$asInt ${unit.short}';
    return '${quantity.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} ${unit.short}';
  }
}

StockBalance stockBalanceFromRow(Map<String, dynamic> row) => StockBalance(
      productId: row['product_id'] as String,
      productName: row['product_name'] as String,
      sku: row['sku'] as String?,
      unit: productUnitFromString(row['unit'] as String? ?? 'un'),
      warehouseId: row['warehouse_id'] as String,
      warehouseName: row['warehouse_name'] as String,
      quantity: (row['quantity'] as num?)?.toDouble() ?? 0,
      minQuantity: (row['min_quantity'] as num?)?.toDouble() ?? 0,
      totalValueCents: (row['total_value_cents'] as num?)?.toInt() ?? 0,
      averageUnitCostCents:
          (row['average_unit_cost_cents'] as num?)?.toInt() ?? 0,
      belowMinimum: row['below_minimum'] as bool? ?? false,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
