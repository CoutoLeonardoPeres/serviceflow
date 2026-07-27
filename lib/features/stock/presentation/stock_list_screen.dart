import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/stock_notifier.dart';
import '../domain/stock_balance.dart';
import '../domain/warehouse.dart';
import 'widgets/stock_movement_dialogs.dart';

/// Lista de saldos de estoque por depósito.
class StockListScreen extends ConsumerWidget {
  const StockListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(stockBalancesProvider);
    final warehousesAsync = ref.watch(warehousesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estoque'),
        actions: [
          IconButton(
            tooltip: 'Transferências',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => context.push(AppRoutes.stockTransfers),
          ),
          IconButton(
            tooltip: 'Inventário',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => context.push(AppRoutes.stockCounts),
          ),
          IconButton(
            tooltip: 'Produtos',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => context.push(AppRoutes.products),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showStockEntryDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Entrada'),
      ),
      body: Column(
        children: [
          warehousesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (warehouses) => _WarehouseFilter(warehouses: warehouses),
          ),
          const _BelowMinimumBanner(),
          Expanded(
            child: balancesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => ErrorView(
                message: e.toString().replaceAll('Exception: ', ''),
                onRetry: () => ref.invalidate(stockBalancesProvider),
              ),
              data: (balances) {
                if (balances.isEmpty) return const _EmptyStock();
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(stockBalancesProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: balances.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) =>
                        _BalanceCard(balance: balances[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseFilter extends ConsumerWidget {
  const _WarehouseFilter({required this.warehouses});

  final List<Warehouse> warehouses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (warehouses.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(selectedWarehouseIdProvider);

    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: selected == null,
            onSelected: (_) =>
                ref.read(selectedWarehouseIdProvider.notifier).state = null,
          ),
          const SizedBox(width: 8),
          ...warehouses.map(
            (w) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(w.name),
                selected: selected == w.id,
                onSelected: (_) => ref
                    .read(selectedWarehouseIdProvider.notifier)
                    .state = w.id,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BelowMinimumBanner extends ConsumerWidget {
  const _BelowMinimumBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(belowMinimumCountProvider);
    final onlyBelowMin = ref.watch(showOnlyBelowMinimumProvider);

    return countAsync.maybeWhen(
      data: (count) {
        if (count == 0 && !onlyBelowMin) return const SizedBox.shrink();
        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Material(
            color: onlyBelowMin
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => ref
                  .read(showOnlyBelowMinimumProvider.notifier)
                  .state = !onlyBelowMin,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: onlyBelowMin
                          ? theme.colorScheme.onErrorContainer
                          : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        onlyBelowMin
                            ? 'Mostrando apenas itens abaixo do mínimo. Toque para ver todos.'
                            : '$count ${count == 1 ? 'item está' : 'itens estão'} abaixo do mínimo.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Icon(
                      onlyBelowMin ? Icons.close : Icons.filter_alt_outlined,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.balance});

  final StockBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return NeomorphicPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      balance.displayName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      balance.warehouseName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    balance.quantityLabel,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: balance.belowMinimum
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (balance.belowMinimum)
                    Text(
                      'mín. ${balance.minQuantity.toStringAsFixed(0)}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CostChip(
                label: 'Custo médio',
                value: currency.format(balance.averageUnitCostCents / 100),
              ),
              const SizedBox(width: 8),
              _CostChip(
                label: 'Total',
                value: currency.format(balance.totalValueCents / 100),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => showStockExitDialog(
                  context,
                  ref,
                  balance: balance,
                ),
                icon: const Icon(Icons.remove, size: 16),
                label: const Text('Saída'),
              ),
              OutlinedButton.icon(
                onPressed: () => showStockEntryDialog(
                  context,
                  ref,
                  productId: balance.productId,
                  warehouseId: balance.warehouseId,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Entrada'),
              ),
              TextButton.icon(
                onPressed: () => context.push(
                  AppRoutes.stockMovements(balance.productId),
                  extra: balance,
                ),
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Extrato'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CostChip extends StatelessWidget {
  const _CostChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EmptyStock extends StatelessWidget {
  const _EmptyStock();

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.inventory_2_outlined,
      message: 'Nenhum saldo de estoque ainda.\n\nCadastre produtos e registre '
          'a primeira entrada para começar a controlar o estoque.',
      action: () => context.push(AppRoutes.products),
      actionLabel: 'Cadastrar produto',
    );
  }
}
