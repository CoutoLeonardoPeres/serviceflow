import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/stock_notifier.dart';
import '../domain/stock_balance.dart';
import '../domain/stock_movement.dart';
import 'widgets/stock_movement_dialogs.dart';

/// Extrato de movimentos de um produto.
///
/// Cada linha mostra o saldo resultante gravado no próprio movimento — não um
/// valor recalculado no cliente. Isso mantém o extrato fiel ao razão mesmo se a
/// regra de custo mudar no futuro.
class StockMovementsScreen extends ConsumerWidget {
  const StockMovementsScreen({
    super.key,
    required this.productId,
    this.balance,
  });

  final String productId;

  /// Saldo de origem, quando a tela foi aberta a partir da lista. Permite
  /// mostrar o cabeçalho e habilitar o ajuste sem uma consulta extra.
  final StockBalance? balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouseId = balance?.warehouseId;
    final movementsAsync = ref.watch(
      stockMovementsProvider(
        (productId: productId, warehouseId: warehouseId),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(balance?.productName ?? 'Extrato de estoque'),
        actions: [
          if (balance != null)
            IconButton(
              tooltip: 'Ajuste de inventário',
              icon: const Icon(Icons.tune),
              onPressed: () => showStockAdjustmentDialog(
                context,
                ref,
                balance: balance!,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (balance != null) _BalanceHeader(balance: balance!),
          Expanded(
            child: movementsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => ErrorView(
                message: e.toString().replaceAll('Exception: ', ''),
                onRetry: () => ref.invalidate(stockMovementsProvider),
              ),
              data: (movements) {
                if (movements.isEmpty) {
                  return const EmptyView(
                    icon: Icons.receipt_long_outlined,
                    message: 'Nenhum movimento registrado para este produto.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: movements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _MovementTile(movement: movements[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.balance});

  final StockBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: NeomorphicPanel(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balance.warehouseName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    balance.quantityLabel,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Custo médio',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currency.format(balance.averageUnitCostCents / 100),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Total ${currency.format(balance.totalValueCents / 100)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementTile extends ConsumerWidget {
  const _MovementTile({required this.movement});

  final StockMovement movement;

  Future<void> _showLotHistory(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(stockRepositoryProvider);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Histórico — lote ${movement.lotCode}'),
        content: SizedBox(
          width: 420,
          child: FutureBuilder<List<StockMovement>>(
            future: repo.getLotHistory(movement.lotId!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final items = snapshot.data!;
              if (items.isEmpty) {
                return const Text('Nenhum movimento encontrado.');
              }
              final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
              return SizedBox(
                height: 320,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, i) {
                    final m = items[i];
                    return Row(
                      children: [
                        Expanded(
                          child: Text('${m.kind.label} · ${_fmt(m.quantity)}'),
                        ),
                        Text(
                          dateFormat.format(m.createdAt.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

    final (color, icon) = switch (movement.kind) {
      StockMovementKind.entry => (Colors.green.shade700, Icons.arrow_downward),
      StockMovementKind.exit => (Colors.orange.shade800, Icons.arrow_upward),
      StockMovementKind.adjustment => (theme.colorScheme.primary, Icons.tune),
    };

    return NeomorphicPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      movement.kind.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${movement.kind.sign}${_fmt(movement.quantity)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Saldo após: ${_fmt(movement.quantityAfter)} · '
                  'médio ${currency.format(movement.averageCostAfterCents / 100)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (movement.reason != null && movement.reason!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(movement.reason!, style: theme.textTheme.bodySmall),
                ],
                if (movement.lotCode != null) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _showLotHistory(context, ref),
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.qr_code_2_outlined, size: 16),
                      label: Text(movement.lotCode!),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  dateFormat.format(movement.createdAt.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double value) {
    if (value == value.truncate()) return '${value.truncate()}';
    return value
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
