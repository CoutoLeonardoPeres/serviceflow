import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/purchase_order.dart';
import '../domain/supplier.dart';

/// Acesso a fornecedores e pedidos de compra.
///
/// Pedidos e itens só são mutados por RPC — não há policy que permita escrita
/// direta. Isso garante que o ciclo de status e a entrada de estoque não podem
/// ser burlados pelo cliente.
class PurchaseRepository {
  PurchaseRepository(this._db);

  final SupabaseClient _db;

  // ── Fornecedores ───────────────────────────────────────────────────────────

  Future<List<Supplier>> listSuppliers({
    bool activeOnly = true,
    String? search,
  }) async {
    try {
      var query = _db.from('suppliers').select();
      if (activeOnly) query = query.eq('is_active', true);
      if (search != null && search.trim().isNotEmpty) {
        final term = '%${search.trim()}%';
        query = query.or('name.ilike.$term,trade_name.ilike.$term');
      }

      final rows = await query.order('name');
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(supplierFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Supplier> createSupplier({
    required String name,
    String? tradeName,
    String? document,
    String? email,
    String? phone,
    String? notes,
  }) async {
    try {
      final row = await _db
          .from('suppliers')
          .insert({
            'name': name.trim(),
            'trade_name': _nullIfEmpty(tradeName),
            'document': _nullIfEmpty(document),
            'email': _nullIfEmpty(email),
            'phone': _nullIfEmpty(phone),
            'notes': _nullIfEmpty(notes),
          })
          .select()
          .single();
      return supplierFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ValidationError(
          'Já existe um fornecedor com este documento.',
        );
      }
      throw _mapError(e);
    }
  }

  Future<Supplier> updateSupplier({
    required String id,
    required String name,
    required bool isActive,
    String? tradeName,
    String? document,
    String? email,
    String? phone,
    String? notes,
  }) async {
    try {
      final row = await _db
          .from('suppliers')
          .update({
            'name': name.trim(),
            'trade_name': _nullIfEmpty(tradeName),
            'document': _nullIfEmpty(document),
            'email': _nullIfEmpty(email),
            'phone': _nullIfEmpty(phone),
            'notes': _nullIfEmpty(notes),
            'is_active': isActive,
          })
          .eq('id', id)
          .select()
          .single();
      return supplierFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ValidationError(
          'Já existe um fornecedor com este documento.',
        );
      }
      throw _mapError(e);
    }
  }

  // ── Pedidos ────────────────────────────────────────────────────────────────

  Future<List<PurchaseOrder>> listOrders({
    PurchaseOrderStatus? status,
    bool openOnly = false,
    int limit = 50,
  }) async {
    try {
      var query = _db
          .from('purchase_orders')
          .select('*, suppliers(name), warehouses(name)');

      if (status != null) {
        query = query.eq('status', status.value);
      } else if (openOnly) {
        query = query.inFilter('status', ['sent', 'partially_received']);
      }

      final rows = await query.order('created_at', ascending: false).limit(limit);

      return (rows as List).cast<Map<String, dynamic>>().map((row) {
        final flat = Map<String, dynamic>.from(row);
        flat['supplier_name'] = (row['suppliers'] as Map?)?['name'];
        flat['warehouse_name'] = (row['warehouses'] as Map?)?['name'];
        return purchaseOrderFromRow(flat);
      }).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<PurchaseOrder> getOrder(String id) async {
    try {
      final row = await _db
          .from('purchase_orders')
          .select('*, suppliers(name), warehouses(name)')
          .eq('id', id)
          .single();

      final flat = Map<String, dynamic>.from(row);
      flat['supplier_name'] = (row['suppliers'] as Map?)?['name'];
      flat['warehouse_name'] = (row['warehouses'] as Map?)?['name'];
      return purchaseOrderFromRow(flat);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw const NotFoundError('Pedido de compra não encontrado.');
      }
      throw _mapError(e);
    }
  }

  Future<List<PurchaseOrderItem>> listItems(String orderId) async {
    try {
      final rows = await _db.rpc(
        'list_purchase_order_items',
        params: {'p_order_id': orderId},
      );
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(purchaseOrderItemFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Cria o pedido em rascunho. Não movimenta estoque.
  Future<String> createOrder({
    required String supplierId,
    required String warehouseId,
    required List<({String productId, double quantity, int unitCostCents})>
        items,
    DateTime? expectedAt,
    String? notes,
  }) async {
    try {
      final res = await _db.rpc(
        'create_purchase_order',
        params: {
          'p_supplier_id': supplierId,
          'p_warehouse_id': warehouseId,
          'p_items': items
              .map((i) => {
                    'product_id': i.productId,
                    'quantity': i.quantity,
                    'unit_cost_cents': i.unitCostCents,
                  })
              .toList(),
          'p_expected_at': expectedAt?.toIso8601String().split('T').first,
          'p_notes': notes,
        },
      );
      return (res as Map<String, dynamic>)['id'] as String;
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> sendOrder(String orderId) async {
    try {
      await _db.rpc('send_purchase_order', params: {'p_order_id': orderId});
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Registra recebimento total ou parcial.
  ///
  /// É aqui que o estoque entra, com o custo real da nota. Se qualquer linha
  /// falhar, a transação inteira volta atrás e o pedido não muda de status.
  Future<PurchaseReceiptResult> receiveOrder({
    required String orderId,
    required List<PurchaseReceiptLine> lines,
  }) async {
    try {
      final res = await _db.rpc(
        'receive_purchase_order',
        params: {
          'p_order_id': orderId,
          'p_items': lines.map((l) => l.toJson()).toList(),
        },
      );
      final map = res as Map<String, dynamic>;
      return PurchaseReceiptResult(
        status: purchaseOrderStatusFromString(map['status'] as String),
        fullyReceived: map['fully_received'] as bool? ?? false,
        itemsReceived: (map['items_received'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> cancelOrder(String orderId, String reason) async {
    try {
      await _db.rpc(
        'cancel_purchase_order',
        params: {'p_order_id': orderId, 'p_reason': reason.trim()},
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  String? _nullIfEmpty(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  AppError _mapError(PostgrestException e) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Você não tem permissão para esta operação de compras.',
      );
    }
    // Mensagens de regra de negócio de 0044 são escritas para o usuário e
    // trazem números úteis ("pedido 100, já recebido 100, tentando receber 1").
    if (e.code == '23514' || e.code == 'P0001') {
      final msg = e.message.trim();
      return BusinessRuleError(
        msg.isEmpty ? 'Revise os dados do pedido.' : msg,
      );
    }
    return UnexpectedError(
      'Operação de compras falhou. Tente novamente.',
      '${e.code}: ${e.message}',
    );
  }
}

class PurchaseReceiptResult {
  const PurchaseReceiptResult({
    required this.status,
    required this.fullyReceived,
    required this.itemsReceived,
  });

  final PurchaseOrderStatus status;
  final bool fullyReceived;
  final int itemsReceived;
}
