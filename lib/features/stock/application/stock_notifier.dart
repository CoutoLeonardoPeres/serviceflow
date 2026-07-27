import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../data/stock_repository.dart';
import '../domain/product.dart';
import '../domain/stock_balance.dart';
import '../domain/stock_count.dart';
import '../domain/stock_movement.dart';
import '../domain/stock_transfer.dart';
import '../domain/warehouse.dart';

final stockRepositoryProvider = Provider<StockRepository>((ref) {
  return StockRepository(ref.read(supabaseClientProvider));
});

// ── Depósitos ────────────────────────────────────────────────────────────────

final warehousesProvider =
    FutureProvider.autoDispose<List<Warehouse>>((ref) async {
  return ref.read(stockRepositoryProvider).listWarehouses();
});

/// Depósito selecionado na tela de estoque.
///
/// `null` significa "todos os depósitos". A tela resolve o padrão do tenant na
/// primeira carga.
final selectedWarehouseIdProvider = StateProvider<String?>((ref) => null);

// ── Catálogo ─────────────────────────────────────────────────────────────────

final productSearchProvider = StateProvider<String>((ref) => '');

final productsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final search = ref.watch(productSearchProvider);
  return ref.read(stockRepositoryProvider).listProducts(search: search);
});

/// Produtos que aceitam movimento — usado nos seletores de entrada/saída.
final stockTrackedProductsProvider =
    FutureProvider.autoDispose<List<Product>>((ref) async {
  return ref.read(stockRepositoryProvider).listProducts(trackStockOnly: true);
});

// ── Saldos ───────────────────────────────────────────────────────────────────

/// Quando true, a lista mostra só itens abaixo do mínimo.
final showOnlyBelowMinimumProvider = StateProvider<bool>((ref) => false);

final stockBalancesProvider =
    FutureProvider.autoDispose<List<StockBalance>>((ref) async {
  final warehouseId = ref.watch(selectedWarehouseIdProvider);
  final onlyBelowMin = ref.watch(showOnlyBelowMinimumProvider);
  return ref.read(stockRepositoryProvider).listBalances(
        warehouseId: warehouseId,
        onlyBelowMinimum: onlyBelowMin,
      );
});

/// Quantos itens estão abaixo do mínimo — para o indicador no topo da lista.
final belowMinimumCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final warehouseId = ref.watch(selectedWarehouseIdProvider);
  final list = await ref
      .read(stockRepositoryProvider)
      .listBalances(warehouseId: warehouseId, onlyBelowMinimum: true);
  return list.length;
});

// ── Extrato ──────────────────────────────────────────────────────────────────

final stockMovementsProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, ({String productId, String? warehouseId})>(
        (ref, args) async {
  return ref.read(stockRepositoryProvider).listMovements(
        productId: args.productId,
        warehouseId: args.warehouseId,
      );
});

// ── Transferências e inventário (F3-P4) ──────────────────────────────────────

final stockTransfersProvider =
    FutureProvider.autoDispose<List<StockTransfer>>((ref) async {
  return ref.read(stockRepositoryProvider).listTransfers();
});

final stockCountsProvider =
    FutureProvider.autoDispose<List<StockCount>>((ref) async {
  return ref.read(stockRepositoryProvider).listCounts();
});

final stockCountItemsProvider = FutureProvider.autoDispose
    .family<List<StockCountItem>, String>((ref, countId) async {
  return ref.read(stockRepositoryProvider).listCountItems(countId);
});

/// Invalida tudo que depende de saldo depois de um movimento.
///
/// Centralizado aqui para que nenhuma tela esqueça de atualizar um provider e
/// mostre saldo velho depois de movimentar. Transferência e aplicação de
/// inventário também passam por aqui — ambas geram movimento.
void invalidateStockAfterMovement(WidgetRef ref) {
  ref.invalidate(stockBalancesProvider);
  ref.invalidate(belowMinimumCountProvider);
  ref.invalidate(stockMovementsProvider);
  ref.invalidate(stockTransfersProvider);
  ref.invalidate(stockCountsProvider);
}
