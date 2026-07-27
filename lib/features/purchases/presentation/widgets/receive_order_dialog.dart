import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/widgets/app_form_dialog.dart';
import '../../application/purchase_notifier.dart';
import '../../domain/purchase_order.dart';

/// Abre o diálogo de recebimento do pedido.
Future<void> showReceiveOrderDialog(
  BuildContext context,
  WidgetRef ref, {
  required PurchaseOrder order,
}) async {
  final done = await showAppFormDialog<bool>(
    context: context,
    title: 'Receber pedido ${order.displayNumber}',
    maxWidth: 720,
    child: _ReceiveForm(order: order),
  );
  if (done == true) {
    invalidateAfterReceipt(ref, order.id);
  }
}

class _ReceiveForm extends ConsumerStatefulWidget {
  const _ReceiveForm({required this.order});

  final PurchaseOrder order;

  @override
  ConsumerState<_ReceiveForm> createState() => _ReceiveFormState();
}

class _ReceiveFormState extends ConsumerState<_ReceiveForm> {
  /// Quantidade digitada por item.
  final _quantities = <String, TextEditingController>{};

  /// Custo da nota por item — vazio mantém o cotado no pedido.
  final _costs = <String, TextEditingController>{};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _quantities.values) {
      c.dispose();
    }
    for (final c in _costs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _qtyController(PurchaseOrderItem item) {
    return _quantities.putIfAbsent(
      item.id,
      // Pré-preenche com o que falta: o caso comum é receber tudo que resta.
      () => TextEditingController(text: _fmt(item.quantityPending)),
    );
  }

  TextEditingController _costController(PurchaseOrderItem item) {
    return _costs.putIfAbsent(item.id, () => TextEditingController());
  }

  Future<void> _submit(List<PurchaseOrderItem> items) async {
    final lines = <PurchaseReceiptLine>[];

    for (final item in items) {
      if (item.isFullyReceived) continue;

      final raw = _quantities[item.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;

      final qty = double.tryParse(raw.replaceAll(',', '.'));
      if (qty == null || qty <= 0) continue;

      if (qty > item.quantityPending) {
        setState(() {
          _error = '${item.displayName}: faltam apenas '
              '${_fmt(item.quantityPending)} ${item.unit}.';
        });
        return;
      }

      final costRaw = _costs[item.id]?.text.trim() ?? '';
      int? costCents;
      if (costRaw.isNotEmpty) {
        final parsed = double.tryParse(costRaw.replaceAll(',', '.'));
        if (parsed == null || parsed < 0) {
          setState(() => _error = '${item.displayName}: custo inválido.');
          return;
        }
        costCents = (parsed * 100).round();
      }

      lines.add(PurchaseReceiptLine(
        itemId: item.id,
        quantity: qty,
        unitCostCents: costCents,
      ));
    }

    if (lines.isEmpty) {
      setState(() => _error = 'Informe a quantidade recebida de ao menos um item.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await ref.read(purchaseRepositoryProvider).receiveOrder(
            orderId: widget.order.id,
            lines: lines,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.fullyReceived
                ? 'Pedido recebido por completo. Estoque atualizado.'
                : 'Recebimento parcial registrado. O pedido segue aberto.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AppError ? e.userMessage : 'Não foi possível receber.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(purchaseOrderItemsProvider(widget.order.id));

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Text('Erro ao carregar itens do pedido.'),
      data: (items) {
        final pending = items.where((i) => !i.isFullyReceived).toList();

        if (pending.isEmpty) {
          return const Text('Todos os itens deste pedido já foram recebidos.');
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Confira o que chegou. A entrada no estoque usa o custo da nota — '
              'preencha o campo de custo só se o preço veio diferente do pedido.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ...pending.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ItemRow(
                    item: item,
                    quantityController: _qtyController(item),
                    costController: _costController(item),
                  ),
                )),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : () => _submit(items),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirmar recebimento'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.quantityController,
    required this.costController,
  });

  final PurchaseOrderItem item;
  final TextEditingController quantityController;
  final TextEditingController costController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.displayName,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          'Faltam ${_fmt(item.quantityPending)} ${item.unit} de '
          '${_fmt(item.quantityOrdered)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: quantityController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Quantidade recebida',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: costController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Custo da nota (R\$)',
                  hintText: _fmtMoney(item.unitCostCents),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _fmt(double v) {
  if (v == v.truncate()) return '${v.truncate()}';
  return v
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

String _fmtMoney(int cents) => (cents / 100).toStringAsFixed(2);
