/// Transferência entre depósitos.
///
/// Transferir não cria nem destrói valor: o que sai da origem entra no destino,
/// até o último centavo. O servidor calcula esse valor uma única vez e grava
/// idêntico nas duas pontas (migration 0045).
class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.number,
    required this.fromWarehouseId,
    required this.toWarehouseId,
    required this.totalValueCents,
    required this.createdAt,
    this.fromWarehouseName,
    this.toWarehouseName,
    this.reason,
  });

  final String id;
  final int number;
  final String fromWarehouseId;
  final String toWarehouseId;
  final String? fromWarehouseName;
  final String? toWarehouseName;
  final String? reason;
  final int totalValueCents;
  final DateTime createdAt;

  String get displayNumber => '#$number';

  String get route =>
      '${fromWarehouseName ?? 'Origem'} → ${toWarehouseName ?? 'Destino'}';
}

StockTransfer stockTransferFromRow(Map<String, dynamic> row) => StockTransfer(
      id: row['id'] as String,
      number: (row['number'] as num).toInt(),
      fromWarehouseId: row['from_warehouse_id'] as String,
      toWarehouseId: row['to_warehouse_id'] as String,
      fromWarehouseName: row['from_warehouse_name'] as String?,
      toWarehouseName: row['to_warehouse_name'] as String?,
      reason: row['reason'] as String?,
      totalValueCents: (row['total_value_cents'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

/// Linha de uma transferência a ser enviada ao servidor.
class StockTransferLine {
  const StockTransferLine({required this.productId, required this.quantity});

  final String productId;
  final double quantity;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'quantity': quantity,
      };
}
