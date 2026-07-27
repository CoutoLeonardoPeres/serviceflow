import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../stock/application/stock_notifier.dart';
import '../data/purchase_repository.dart';
import '../domain/purchase_order.dart';
import '../domain/supplier.dart';

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return PurchaseRepository(ref.read(supabaseClientProvider));
});

// ── Fornecedores ─────────────────────────────────────────────────────────────

final supplierSearchProvider = StateProvider<String>((ref) => '');

final suppliersProvider =
    FutureProvider.autoDispose<List<Supplier>>((ref) async {
  final search = ref.watch(supplierSearchProvider);
  return ref.read(purchaseRepositoryProvider).listSuppliers(search: search);
});

// ── Pedidos ──────────────────────────────────────────────────────────────────

/// Filtro da lista. Null = todos.
final purchaseStatusFilterProvider =
    StateProvider<PurchaseOrderStatus?>((ref) => null);

final purchaseOrdersProvider =
    FutureProvider.autoDispose<List<PurchaseOrder>>((ref) async {
  final status = ref.watch(purchaseStatusFilterProvider);
  return ref.read(purchaseRepositoryProvider).listOrders(status: status);
});

final purchaseOrderDetailProvider =
    FutureProvider.autoDispose.family<PurchaseOrder, String>((ref, id) async {
  return ref.read(purchaseRepositoryProvider).getOrder(id);
});

final purchaseOrderItemsProvider = FutureProvider.autoDispose
    .family<List<PurchaseOrderItem>, String>((ref, orderId) async {
  return ref.read(purchaseRepositoryProvider).listItems(orderId);
});

/// Pedidos abertos — o que já foi pedido e ainda não chegou.
final openPurchaseOrdersProvider =
    FutureProvider.autoDispose<List<PurchaseOrder>>((ref) async {
  return ref.read(purchaseRepositoryProvider).listOrders(openOnly: true);
});

/// Invalida o que muda depois de um recebimento.
///
/// O recebimento gera entrada de estoque, então os saldos também precisam ser
/// recarregados — centralizado aqui para que nenhuma tela mostre saldo velho.
void invalidateAfterReceipt(WidgetRef ref, String orderId) {
  ref.invalidate(purchaseOrderDetailProvider(orderId));
  ref.invalidate(purchaseOrderItemsProvider(orderId));
  ref.invalidate(purchaseOrdersProvider);
  ref.invalidate(openPurchaseOrdersProvider);
  invalidateStockAfterMovement(ref);
}
