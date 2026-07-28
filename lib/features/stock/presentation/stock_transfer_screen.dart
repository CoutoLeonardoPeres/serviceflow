import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/stock_notifier.dart';
import '../domain/product.dart';
import '../domain/stock_transfer.dart';

/// Histórico de transferências entre depósitos.
class StockTransferScreen extends ConsumerWidget {
  const StockTransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfersAsync = ref.watch(stockTransfersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Transferências')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Nova transferência'),
      ),
      body: transfersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => ErrorView(
          message: e is AppError
              ? e.userMessage
              : e.toString().replaceAll('Exception: ', ''),
          onRetry: () => ref.invalidate(stockTransfersProvider),
        ),
        data: (transfers) {
          if (transfers.isEmpty) {
            return const EmptyView(
              icon: Icons.swap_horiz,
              message: 'Nenhuma transferência registrada.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: transfers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _TransferCard(transfer: transfers[i]),
          );
        },
      ),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    final number = await showAppFormDialog<int>(
      context: context,
      title: 'Nova transferência',
      maxWidth: 640,
      child: const _TransferForm(),
    );
    if (number != null) {
      invalidateStockAfterMovement(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transferência #$number registrada.')),
        );
      }
    }
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.transfer});

  final StockTransfer transfer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

    return NeomorphicPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Transferência ${transfer.displayNumber}',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                currency.format(transfer.totalValueCents / 100),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(transfer.route, style: theme.textTheme.bodyMedium),
          if (transfer.reason != null) ...[
            const SizedBox(height: 4),
            Text(transfer.reason!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 4),
          Text(
            date.format(transfer.createdAt.toLocal()),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferForm extends ConsumerStatefulWidget {
  const _TransferForm();

  @override
  ConsumerState<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends ConsumerState<_TransferForm> {
  final _reasonController = TextEditingController();
  final _lines = <_DraftLine>[];

  String? _fromId;
  String? _toId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_fromId == null || _toId == null) {
      setState(() => _error = 'Escolha origem e destino.');
      return;
    }
    if (_fromId == _toId) {
      setState(() => _error = 'Origem e destino devem ser diferentes.');
      return;
    }

    final valid = _lines.where((l) => l.isValid).toList();
    if (valid.isEmpty) {
      setState(() => _error = 'Adicione ao menos um item.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final number = await ref.read(stockRepositoryProvider).transfer(
            fromWarehouseId: _fromId!,
            toWarehouseId: _toId!,
            lines: valid
                .map((l) => StockTransferLine(
                      productId: l.productId!,
                      quantity: l.quantity,
                    ))
                .toList(),
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(number);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AppError ? e.userMessage : 'Não foi possível transferir.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warehousesAsync = ref.watch(warehousesProvider);
    final productsAsync = ref.watch(stockTrackedProductsProvider);

    return warehousesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Text('Erro ao carregar depósitos.'),
      data: (warehouses) {
        if (warehouses.length < 2) {
          return const Text(
            'Transferência exige pelo menos dois depósitos ativos. '
            'Cadastre outro depósito para usar este recurso.',
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _fromId,
                    decoration: const InputDecoration(
                      labelText: 'Origem *',
                      isDense: true,
                    ),
                    items: warehouses
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _fromId = v),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _toId,
                    decoration: const InputDecoration(
                      labelText: 'Destino *',
                      isDense: true,
                    ),
                    items: warehouses
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _toId = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            productsAsync.maybeWhen(
              data: (products) => Column(
                children: [
                  ..._lines.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LineEditor(
                            line: e.value,
                            products: products,
                            onChanged: () => setState(() {}),
                            onRemove: () => setState(() {
                              _lines.removeAt(e.key).dispose();
                            }),
                          ),
                        ),
                      ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _lines.add(_DraftLine())),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar item'),
                  ),
                ],
              ),
              orElse: () => const LinearProgressIndicator(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reasonController,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Ex.: reposição do estoque do veículo',
              ),
            ),
            Text(
              'O valor viaja junto com a mercadoria: o custo médio do destino '
              'é recalculado com o valor exato que saiu da origem.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
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
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Transferir'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DraftLine {
  final quantityController = TextEditingController(text: '1');
  String? productId;

  double get quantity =>
      double.tryParse(quantityController.text.replaceAll(',', '.')) ?? 0;

  bool get isValid => productId != null && quantity > 0;

  void dispose() => quantityController.dispose();
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    required this.line,
    required this.products,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftLine line;
  final List<Product> products;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: line.productId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Produto',
              isDense: true,
            ),
            items: products
                .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              line.productId = v;
              onChanged();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: line.quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Qtd',
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onRemove,
        ),
      ],
    );
  }
}
