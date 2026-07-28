import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/purchase_order.dart';
import '../domain/material_catalog.dart';
import '../domain/price_sheet.dart';
import '../domain/price_import_result.dart';
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

  /// Cria ou atualiza o fornecedor a partir do próprio modelo.
  ///
  /// Uma função só, com payload do domínio, em vez de duas com vinte
  /// parâmetros nomeados cada — o cadastro cresceu na 0059 e a assinatura
  /// antiga não escalava.
  Future<Supplier> saveSupplier(Supplier supplier) async {
    try {
      final payload = supplier.toPayload();
      final row = supplier.id.isEmpty
          ? await _db.from('suppliers').insert(payload).select().single()
          : await _db
              .from('suppliers')
              .update(payload)
              .eq('id', supplier.id)
              .select()
              .single();

      final saved = supplierFromRow(row);
      await _replaceSupplierCategories(
        supplierId: saved.id,
        tenantId: saved.tenantId,
        categoryIds: supplier.categoryIds,
      );
      return saved.copyWith(categoryIds: supplier.categoryIds);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ValidationError(
          'Já existe um fornecedor com este documento.',
        );
      }
      throw _mapError(e);
    }
  }

  /// Substitui as categorias atendidas. Apaga e reinsere de propósito: a
  /// tabela é um vínculo puro, sem histórico, e diffar duas listas pequenas
  /// custaria mais código do que vale.
  Future<void> _replaceSupplierCategories({
    required String supplierId,
    required String tenantId,
    required List<String> categoryIds,
  }) async {
    await _db.from('supplier_categories').delete().eq('supplier_id', supplierId);
    if (categoryIds.isEmpty) return;
    await _db.from('supplier_categories').insert([
      for (final id in categoryIds)
        {
          'supplier_id': supplierId,
          'category_id': id,
          'tenant_id': tenantId,
        },
    ]);
  }

  Future<Supplier> getSupplier(String id) async {
    try {
      final row = await _db
          .from('suppliers')
          .select('*, supplier_categories(category_id)')
          .eq('id', id)
          .single();
      return supplierFromRow(row);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Categorias de material ─────────────────────────────────────────────────

  Future<List<MaterialCategory>> listCategories({bool activeOnly = true}) async {
    try {
      var query = _db.from('material_categories').select();
      if (activeOnly) query = query.eq('is_active', true);
      final rows = await query.order('name');
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(materialCategoryFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Cria as categorias padrão do setor. Idempotente no banco — chamar duas
  /// vezes não duplica. Devolve quantas foram criadas agora.
  Future<int> seedCategories() async {
    try {
      final result = await _db.rpc('seed_material_categories');
      return (result as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<MaterialCategory> saveCategory(MaterialCategory category) async {
    try {
      final payload = {
        'name': category.name.trim(),
        'markup_percent': category.markupPercent,
        'is_active': category.isActive,
      };
      final row = category.id.isEmpty
          ? await _db
              .from('material_categories')
              .insert(payload)
              .select()
              .single()
          : await _db
              .from('material_categories')
              .update(payload)
              .eq('id', category.id)
              .select()
              .single();
      return materialCategoryFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ValidationError('Já existe uma categoria com este nome.');
      }
      throw _mapError(e);
    }
  }

  // ── Preços por fornecedor ──────────────────────────────────────────────────

  Future<List<SupplierPrice>> listSupplierPrices({
    String? supplierId,
    String? productId,
  }) async {
    try {
      var query = _db
          .from('supplier_products')
          .select('*, suppliers(name), products(name)');
      if (supplierId != null) query = query.eq('supplier_id', supplierId);
      if (productId != null) query = query.eq('product_id', productId);
      final rows = await query.order('price_cents');
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(supplierPriceFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  Future<SupplierPrice> saveSupplierPrice(SupplierPrice price) async {
    try {
      final payload = price.toPayload();
      final row = price.id.isEmpty
          ? await _db
              .from('supplier_products')
              .insert(payload)
              .select('*, suppliers(name), products(name)')
              .single()
          : await _db
              .from('supplier_products')
              .update(payload)
              .eq('id', price.id)
              .select('*, suppliers(name), products(name)')
              .single();
      return supplierPriceFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const ValidationError(
          'Este fornecedor já tem preço para este produto.',
        );
      }
      throw _mapError(e);
    }
  }

  Future<void> deleteSupplierPrice(String id) async {
    try {
      await _db.from('supplier_products').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Ranking de fornecedores para o produto, do mais barato ao mais caro, com
  /// o repasse ao cliente já calculado e o saldo próprio junto.
  Future<List<BestPriceOption>> bestPrices(String productId) async {
    try {
      final rows = await _db.rpc(
        'best_price_for_product',
        params: {'p_product_id': productId},
      );
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(bestPriceOptionFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    }
  }

  /// Importa a tabela de precos do fornecedor.
  ///
  /// O upsert roda inteiro no banco (RPC da 0060): mexe em `products` e
  /// `supplier_products` por linha e precisa ser tudo ou nada. Em laco de
  /// HTTP, uma queda no meio deixaria metade da tabela nova e metade velha.
  Future<PriceImportResult> importSupplierPrices({
    required String supplierId,
    required List<PriceSheetRow> rows,
    bool createMissing = true,
  }) async {
    try {
      final result = await _db.rpc(
        'import_supplier_prices',
        params: {
          'p_supplier_id': supplierId,
          'p_rows': rows.map((r) => r.toPayload()).toList(),
          'p_create_missing': createMissing,
        },
      );
      return priceImportResultFromJson(
        Map<String, dynamic>.from(result as Map),
      );
    } on PostgrestException catch (e) {
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
