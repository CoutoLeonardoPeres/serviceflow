import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/product.dart';
import '../domain/stock_balance.dart';
import '../domain/stock_count.dart';
import '../domain/stock_movement.dart';
import '../domain/stock_transfer.dart';
import '../domain/warehouse.dart';

/// Acesso ao razão de estoque.
///
/// Toda mutação de saldo passa por RPC `SECURITY DEFINER` (ADR-003). O cliente
/// nunca escreve em `stock_balances` nem em `stock_movements` — não há policy
/// que permita isso, então qualquer tentativa direta falharia de qualquer forma.
class StockRepository {
  StockRepository(this._db);

  final SupabaseClient _db;

  // ── Catálogo ───────────────────────────────────────────────────────────────

  Future<List<Product>> listProducts({
    bool activeOnly = true,
    bool trackStockOnly = false,
    String? search,
  }) async {
    try {
      // Filtros antes de order/limit: order retorna PostgrestTransformBuilder,
      // que não expõe .eq (postgrest-dart 2.x).
      var query = _db.from('products').select();

      if (activeOnly) query = query.eq('is_active', true);
      if (trackStockOnly) query = query.eq('track_stock', true);
      if (search != null && search.trim().isNotEmpty) {
        final term = '%${search.trim()}%';
        query = query.or('name.ilike.$term,sku.ilike.$term');
      }

      final rows = await query.order('name');
      return (rows as List).cast<Map<String, dynamic>>().map(productFromRow).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Product> createProduct({
    required String name,
    required ProductUnit unit,
    String? sku,
    String? description,
    bool trackStock = true,
    double minQuantity = 0,
    ProductTrackingType trackingType = ProductTrackingType.none,
  }) async {
    try {
      final row = await _db
          .from('products')
          .insert({
            'name': name.trim(),
            'sku': (sku == null || sku.trim().isEmpty) ? null : sku.trim(),
            'description': (description == null || description.trim().isEmpty)
                ? null
                : description.trim(),
            'unit': unit.value,
            'track_stock': trackStock,
            'min_quantity': minQuantity,
            'tracking_type': trackingType.value,
          })
          .select()
          .single();
      return productFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ValidationError('Já existe um produto com este SKU.');
      }
      throw _mapError(e);
    }
  }

  Future<Product> updateProduct({
    required String id,
    required String name,
    required ProductUnit unit,
    String? sku,
    String? description,
    required double minQuantity,
    required bool isActive,
    ProductTrackingType trackingType = ProductTrackingType.none,
  }) async {
    try {
      final row = await _db
          .from('products')
          .update({
            'name': name.trim(),
            'sku': (sku == null || sku.trim().isEmpty) ? null : sku.trim(),
            'description': (description == null || description.trim().isEmpty)
                ? null
                : description.trim(),
            'unit': unit.value,
            'min_quantity': minQuantity,
            'is_active': isActive,
            'tracking_type': trackingType.value,
          })
          .eq('id', id)
          .select()
          .single();
      return productFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ValidationError('Já existe um produto com este SKU.');
      }
      throw _mapError(e);
    }
  }

  // ── Depósitos ──────────────────────────────────────────────────────────────

  Future<List<Warehouse>> listWarehouses({bool activeOnly = true}) async {
    try {
      var query = _db.from('warehouses').select();
      if (activeOnly) query = query.eq('is_active', true);

      final rows = await query.order('is_default', ascending: false).order('name');
      return (rows as List).cast<Map<String, dynamic>>().map(warehouseFromRow).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Warehouse> createWarehouse({
    required String name,
    bool isDefault = false,
  }) async {
    try {
      final row = await _db
          .from('warehouses')
          .insert({'name': name.trim(), 'is_default': isDefault})
          .select()
          .single();
      return warehouseFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ValidationError(
          'Já existe um depósito com este nome, ou já há um depósito padrão.',
        );
      }
      throw _mapError(e);
    }
  }

  // ── Saldos ─────────────────────────────────────────────────────────────────

  Future<List<StockBalance>> listBalances({
    String? warehouseId,
    bool onlyBelowMinimum = false,
  }) async {
    try {
      final rows = await _db.rpc(
        'list_stock_balances',
        params: {
          'p_warehouse_id': warehouseId,
          'p_only_below_min': onlyBelowMinimum,
        },
      );
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(stockBalanceFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Extrato ────────────────────────────────────────────────────────────────

  Future<List<StockMovement>> listMovements({
    required String productId,
    String? warehouseId,
    int limit = 50,
  }) async {
    try {
      var query = _db
          .from('stock_movements')
          .select('*, products(name), warehouses(name), stock_lots(code)')
          .eq('product_id', productId);

      if (warehouseId != null) query = query.eq('warehouse_id', warehouseId);

      final rows = await query.order('created_at', ascending: false).limit(limit);

      return (rows as List).cast<Map<String, dynamic>>().map((row) {
        // Achata os relacionamentos para o formato que o domínio espera.
        final flat = Map<String, dynamic>.from(row);
        flat['product_name'] = (row['products'] as Map?)?['name'];
        flat['warehouse_name'] = (row['warehouses'] as Map?)?['name'];
        flat['lot_code'] = (row['stock_lots'] as Map?)?['code'];
        return stockMovementFromRow(flat);
      }).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Histórico de movimentos de um lote/série específico (ADR-024).
  Future<List<StockMovement>> getLotHistory(String lotId) async {
    try {
      final rows = await _db.rpc('get_lot_history', params: {'p_lot_id': lotId});
      return (rows as List).cast<Map<String, dynamic>>().map((row) {
        final flat = Map<String, dynamic>.from(row);
        flat['id'] = row['movement_id'];
        return stockMovementFromRow(flat);
      }).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Movimentação (sempre via RPC) ──────────────────────────────────────────

  /// Entrada de estoque. Recalcula o custo médio ponderado móvel no servidor.
  Future<StockMovementResult> recordEntry({
    required String productId,
    required String warehouseId,
    required double quantity,
    required int unitCostCents,
    String? reason,
    String? relatedEntity,
    String? relatedEntityId,
    String? lotCode,
  }) async {
    try {
      final res = await _db.rpc(
        'record_stock_entry',
        params: {
          'p_product_id': productId,
          'p_warehouse_id': warehouseId,
          'p_quantity': quantity,
          'p_unit_cost_cents': unitCostCents,
          'p_reason': reason,
          'p_related_entity': relatedEntity,
          'p_related_entity_id': relatedEntityId,
          'p_lot_code': lotCode,
        },
      );
      return stockMovementResultFromMap(res as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Saída de estoque. Rejeitada pelo servidor se o saldo não cobrir.
  Future<StockMovementResult> recordExit({
    required String productId,
    required String warehouseId,
    required double quantity,
    String? reason,
    String? relatedEntity,
    String? relatedEntityId,
    String? lotCode,
  }) async {
    try {
      final res = await _db.rpc(
        'record_stock_exit',
        params: {
          'p_product_id': productId,
          'p_warehouse_id': warehouseId,
          'p_quantity': quantity,
          'p_reason': reason,
          'p_related_entity': relatedEntity,
          'p_related_entity_id': relatedEntityId,
          'p_lot_code': lotCode,
        },
      );
      return stockMovementResultFromMap(res as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Ajuste de inventário: define a quantidade contada.
  ///
  /// Exige `stock.adjust`, permissão mais restrita que `stock.write`, porque
  /// sobrepõe o saldo calculado pelo sistema. Motivo é obrigatório.
  Future<StockMovementResult> recordAdjustment({
    required String productId,
    required String warehouseId,
    required double countedQuantity,
    required String reason,
    String? lotCode,
  }) async {
    try {
      final res = await _db.rpc(
        'record_stock_adjustment',
        params: {
          'p_product_id': productId,
          'p_warehouse_id': warehouseId,
          'p_new_quantity': countedQuantity,
          'p_reason': reason.trim(),
          'p_lot_code': lotCode,
        },
      );
      return stockMovementResultFromMap(res as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Transferências (F3-P4) ─────────────────────────────────────────────────

  Future<List<StockTransfer>> listTransfers({int limit = 50}) async {
    try {
      final rows = await _db
          .from('stock_transfers')
          .select(
            '*, from_wh:warehouses!stock_transfers_from_warehouse_id_fkey(name), '
            'to_wh:warehouses!stock_transfers_to_warehouse_id_fkey(name)',
          )
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List).cast<Map<String, dynamic>>().map((row) {
        final flat = Map<String, dynamic>.from(row);
        flat['from_warehouse_name'] = (row['from_wh'] as Map?)?['name'];
        flat['to_warehouse_name'] = (row['to_wh'] as Map?)?['name'];
        return stockTransferFromRow(flat);
      }).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Transfere itens entre depósitos.
  ///
  /// O servidor conserva o valor exato: o que sai da origem entra no destino.
  /// Se qualquer linha falhar por saldo, a transferência inteira volta atrás.
  Future<int> transfer({
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<StockTransferLine> lines,
    String? reason,
  }) async {
    try {
      final res = await _db.rpc(
        'transfer_stock',
        params: {
          'p_from_warehouse_id': fromWarehouseId,
          'p_to_warehouse_id': toWarehouseId,
          'p_items': lines.map((l) => l.toJson()).toList(),
          'p_reason': reason,
        },
      );
      return ((res as Map<String, dynamic>)['number'] as num).toInt();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Inventário cíclico (F3-P4) ─────────────────────────────────────────────

  Future<List<StockCount>> listCounts({int limit = 50}) async {
    try {
      final rows = await _db
          .from('stock_counts')
          .select('*, warehouses(name)')
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List).cast<Map<String, dynamic>>().map((row) {
        final flat = Map<String, dynamic>.from(row);
        flat['warehouse_name'] = (row['warehouses'] as Map?)?['name'];
        return stockCountFromRow(flat);
      }).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Abre uma contagem. Sem [productIds], entra tudo que tem saldo no depósito.
  Future<String> createCount({
    required String warehouseId,
    List<String>? productIds,
    String? notes,
  }) async {
    try {
      final res = await _db.rpc(
        'create_stock_count',
        params: {
          'p_warehouse_id': warehouseId,
          'p_product_ids': productIds,
          'p_notes': notes,
        },
      );
      return (res as Map<String, dynamic>)['id'] as String;
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<StockCountItem>> listCountItems(String countId) async {
    try {
      final rows = await _db.rpc(
        'list_stock_count_items',
        params: {'p_count_id': countId},
      );
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(stockCountItemFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> setCountQuantity({
    required String countItemId,
    required double? quantity,
  }) async {
    try {
      await _db.rpc(
        'set_stock_count_quantity',
        params: {'p_count_item_id': countItemId, 'p_quantity': quantity},
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Aplica a contagem, gerando um ajuste por item divergente.
  Future<StockCountApplyResult> applyCount(String countId) async {
    try {
      final res = await _db.rpc(
        'apply_stock_count',
        params: {'p_count_id': countId},
      );
      final map = res as Map<String, dynamic>;
      return StockCountApplyResult(
        adjusted: (map['adjusted'] as num?)?.toInt() ?? 0,
        unchanged: (map['unchanged'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> cancelCount(String countId, String reason) async {
    try {
      await _db.rpc(
        'cancel_stock_count',
        params: {'p_count_id': countId, 'p_reason': reason},
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  AppError _mapError(PostgrestException e) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Você não tem permissão para esta operação de estoque.',
      );
    }
    // Para violações de regra de negócio, a mensagem do servidor é mais útil
    // que uma genérica — "Saldo insuficiente: disponível 3, solicitado 10" diz
    // exatamente o que fazer. Essas mensagens são escritas em 0042 já pensando
    // no usuário final e não expõem schema.
    if (e.code == '23514' || e.code == 'P0001') {
      final msg = e.message.trim();
      return BusinessRuleError(
        msg.isEmpty ? 'Revise os dados do movimento de estoque.' : msg,
      );
    }
    return UnexpectedError(
      'Operação de estoque falhou. Tente novamente.',
      '${e.code}: ${e.message}',
    );
  }
}

/// Saldo resultante devolvido pelos RPCs de movimentação.
class StockMovementResult {
  const StockMovementResult({
    required this.movementId,
    required this.quantity,
    required this.totalValueCents,
    required this.averageUnitCostCents,
  });

  final String movementId;
  final double quantity;
  final int totalValueCents;
  final int averageUnitCostCents;
}

StockMovementResult stockMovementResultFromMap(Map<String, dynamic> map) =>
    StockMovementResult(
      movementId: map['movement_id'] as String,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      totalValueCents: (map['total_value_cents'] as num?)?.toInt() ?? 0,
      averageUnitCostCents:
          (map['average_unit_cost_cents'] as num?)?.toInt() ?? 0,
    );
