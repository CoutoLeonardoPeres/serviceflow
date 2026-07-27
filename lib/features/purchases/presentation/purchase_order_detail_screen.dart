import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/purchase_notifier.dart';
import '../domain/purchase_order.dart';
import 'widgets/receive_order_dialog.dart';

/// Detalhe do pedido de compra, com envio, recebimento e cancelamento.
class PurchaseOrderDetailScreen extends ConsumerWidget {
  const PurchaseOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(purchaseOrderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Pedido de compra')),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => ErrorView(
          message: e is AppError
              ? e.userMessage
              : e.toString().replaceAll('Exception: ', ''),
          onRetry: () => ref.invalidate(purchaseOrderDetailProvider(orderId)),
        ),
        data: (order) => _OrderBody(order: order),
      ),
    );
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order});

  final PurchaseOrder order;

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(purchaseRepositoryProvider).sendOrder(order.id);
      ref.invalidate(purchaseOrderDetailProvider(order.id));
      ref.invalidate(purchaseOrdersProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Pedido enviado ao fornecedor.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AppError ? e.userMessage : 'Não foi possível enviar.',
          ),
        ),
      );
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _CancelDialog(),
    );
    if (reason == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(purchaseRepositoryProvider).cancelOrder(order.id, reason);
      ref.invalidate(purchaseOrderDetailProvider(order.id));
      ref.invalidate(purchaseOrdersProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Pedido cancelado.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AppError ? e.userMessage : 'Não foi possível cancelar.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy', 'pt_BR');
    final itemsAsync = ref.watch(purchaseOrderItemsProvider(order.id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        NeomorphicPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pedido ${order.displayNumber}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              _InfoLine(label: 'Status', value: order.status.label),
              _InfoLine(
                label: 'Fornecedor',
                value: order.supplierName ?? '—',
              ),
              _InfoLine(
                label: 'Depósito de entrada',
                value: order.warehouseName ?? '—',
              ),
              if (order.expectedAt != null)
                _InfoLine(
                  label: 'Previsão',
                  value: date.format(order.expectedAt!),
                ),
              _InfoLine(
                label: 'Total',
                value: currency.format(order.totalCents / 100),
              ),
              if (order.notes != null && order.notes!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(order.notes!, style: theme.textTheme.bodyMedium),
              ],
              if (order.status == PurchaseOrderStatus.cancelled &&
                  order.cancellationReason != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Cancelado: ${order.cancellationReason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (order.status.canSend)
                    FilledButton.icon(
                      onPressed: () => _send(context, ref),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Enviar ao fornecedor'),
                    ),
                  if (order.status.canReceive)
                    FilledButton.icon(
                      onPressed: () => showReceiveOrderDialog(
                        context,
                        ref,
                        order: order,
                      ),
                      icon: const Icon(Icons.inventory_outlined),
                      label: const Text('Registrar recebimento'),
                    ),
                  if (order.status.canCancel)
                    OutlinedButton.icon(
                      onPressed: () => _cancel(context, ref),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancelar pedido'),
                    ),
                ],
              ),
              if (order.status == PurchaseOrderStatus.partiallyReceived) ...[
                const SizedBox(height: 12),
                Text(
                  'Parte da mercadoria já entrou no estoque, por isso este '
                  'pedido não pode mais ser cancelado. Divergências se '
                  'corrigem por ajuste de inventário.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Itens',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text('Erro ao carregar itens.'),
          data: (items) => Column(
            children: items
                .map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ItemCard(item: i),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final PurchaseOrderItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final progress = item.quantityOrdered == 0
        ? 0.0
        : (item.quantityReceived / item.quantityOrdered).clamp(0.0, 1.0);

    return NeomorphicPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.displayName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                currency.format(item.totalCostCents / 100),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: item.isFullyReceived
                  ? Colors.green.shade600
                  : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Recebido ${_fmt(item.quantityReceived)} de '
            '${_fmt(item.quantityOrdered)} ${item.unit}'
            '${item.isFullyReceived ? '' : ' · faltam ${_fmt(item.quantityPending)}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: item.isFullyReceived
                  ? Colors.green.shade700
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Custo cotado: ${currency.format(item.unitCostCents / 100)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.truncate()) return '${v.truncate()}';
    return v
        .toStringAsFixed(3)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancelar pedido'),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: 'Motivo *',
          hintText: 'Ex.: fornecedor sem estoque, preço reajustado…',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.length < 3) {
              setState(() => _error = 'Descreva o motivo.');
              return;
            }
            Navigator.of(context).pop(text);
          },
          child: const Text('Cancelar pedido'),
        ),
      ],
    );
  }
}
