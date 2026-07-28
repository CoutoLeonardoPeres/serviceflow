import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/stock_notifier.dart';
import '../domain/stock_count.dart';

/// Lista de inventários (contagens cíclicas).
class StockCountListScreen extends ConsumerWidget {
  const StockCountListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(stockCountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventário')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNew(context, ref),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Nova contagem'),
      ),
      body: countsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => ErrorView(
          message: e is AppError
              ? e.userMessage
              : e.toString().replaceAll('Exception: ', ''),
          onRetry: () => ref.invalidate(stockCountsProvider),
        ),
        data: (counts) {
          if (counts.isEmpty) {
            return const EmptyView(
              icon: Icons.fact_check_outlined,
              message: 'Nenhuma contagem registrada.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: counts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _CountCard(count: counts[i]),
          );
        },
      ),
    );
  }

  Future<void> _openNew(BuildContext context, WidgetRef ref) async {
    final warehouses = await ref.read(warehousesProvider.future);
    if (!context.mounted) return;

    if (warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre um depósito primeiro.')),
      );
      return;
    }

    final id = await showAppFormDialog<String>(
      context: context,
      title: 'Nova contagem',
      maxWidth: 520,
      child: _NewCountForm(),
    );

    if (id != null && context.mounted) {
      ref.invalidate(stockCountsProvider);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StockCountDetailScreen(countId: id),
        ),
      );
    }
  }
}

class _CountCard extends ConsumerWidget {
  const _CountCard({required this.count});

  final StockCount count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final date = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

    final color = switch (count.status) {
      StockCountStatus.open => theme.colorScheme.primary,
      StockCountStatus.applied => Colors.green.shade700,
      StockCountStatus.cancelled => theme.colorScheme.error,
    };

    return NeomorphicPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StockCountDetailScreen(countId: count.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Contagem ${count.displayNumber}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      count.status.label,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                count.warehouseName ?? 'Depósito',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                date.format(count.createdAt.toLocal()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewCountForm extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NewCountForm> createState() => _NewCountFormState();
}

class _NewCountFormState extends ConsumerState<_NewCountForm> {
  final _notesController = TextEditingController();
  String? _warehouseId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_warehouseId == null) {
      setState(() => _error = 'Escolha o depósito.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final id = await ref.read(stockRepositoryProvider).createCount(
            warehouseId: _warehouseId!,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AppError ? e.userMessage : 'Não foi possível abrir.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warehousesAsync = ref.watch(warehousesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        warehousesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Erro ao carregar depósitos.'),
          data: (warehouses) {
            _warehouseId ??=
                warehouses.where((w) => w.isDefault).firstOrNull?.id;
            return DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _warehouseId,
              decoration: const InputDecoration(
                labelText: 'Depósito *',
                helperText: 'Entram todos os produtos com saldo no depósito.',
              ),
              items: warehouses
                  .map((w) => DropdownMenuItem(
                        value: w.id,
                        child: Text(w.name),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _warehouseId = v),
            );
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _notesController,
          maxLength: 1000,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Observações'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
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
              child: const Text('Abrir contagem'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Detalhe da contagem: registrar quantidades e aplicar.
class StockCountDetailScreen extends ConsumerStatefulWidget {
  const StockCountDetailScreen({super.key, required this.countId});

  final String countId;

  @override
  ConsumerState<StockCountDetailScreen> createState() =>
      _StockCountDetailScreenState();
}

class _StockCountDetailScreenState
    extends ConsumerState<StockCountDetailScreen> {
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(StockCountItem item) async {
    final raw = _controllers[item.id]?.text.trim() ?? '';
    final qty = raw.isEmpty
        ? null
        : double.tryParse(raw.replaceAll(',', '.'));

    if (raw.isNotEmpty && qty == null) return;

    try {
      await ref.read(stockRepositoryProvider).setCountQuantity(
            countItemId: item.id,
            quantity: qty,
          );
      ref.invalidate(stockCountItemsProvider(widget.countId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is AppError ? e.userMessage : 'Não foi possível salvar.',
          ),
        ),
      );
    }
  }

  Future<void> _apply() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aplicar contagem'),
        content: const Text(
          'Os itens com divergência serão ajustados para a quantidade contada. '
          'Cada ajuste gera um movimento no histórico e não pode ser desfeito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result =
          await ref.read(stockRepositoryProvider).applyCount(widget.countId);
      invalidateStockAfterMovement(ref);
      ref.invalidate(stockCountItemsProvider(widget.countId));

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.adjusted == 0
                ? 'Contagem aplicada. Nenhuma divergência encontrada.'
                : '${result.adjusted} ${result.adjusted == 1 ? 'item ajustado' : 'itens ajustados'}; '
                    '${result.unchanged} sem divergência.',
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AppError ? e.userMessage : 'Não foi possível aplicar.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(stockCountItemsProvider(widget.countId));
    final countsAsync = ref.watch(stockCountsProvider);

    final count = countsAsync.maybeWhen(
      data: (list) => list.where((c) => c.id == widget.countId).firstOrNull,
      orElse: () => null,
    );
    final isOpen = count?.status.isOpen ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          count == null ? 'Contagem' : 'Contagem ${count.displayNumber}',
        ),
      ),
      floatingActionButton: isOpen
          ? FloatingActionButton.extended(
              onPressed: _apply,
              icon: const Icon(Icons.check),
              label: const Text('Aplicar contagem'),
            )
          : null,
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => ErrorView(
          message: e is AppError
              ? e.userMessage
              : e.toString().replaceAll('Exception: ', ''),
          onRetry: () =>
              ref.invalidate(stockCountItemsProvider(widget.countId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              icon: Icons.inventory_2_outlined,
              message: 'Nenhum item nesta contagem.',
            );
          }

          final counted = items.where((i) => i.isCounted).length;
          final divergent = items.where((i) => i.hasDivergence).length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: NeomorphicPanel(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '$counted de ${items.length} contados'
                    '${divergent > 0 ? ' · $divergent com divergência' : ''}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final controller = _controllers.putIfAbsent(
                      item.id,
                      () => TextEditingController(
                        text: item.countedQuantity == null
                            ? ''
                            : _fmt(item.countedQuantity!),
                      ),
                    );
                    return _CountItemCard(
                      item: item,
                      controller: controller,
                      enabled: isOpen,
                      onSubmit: () => _save(item),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CountItemCard extends StatelessWidget {
  const _CountItemCard({
    required this.item,
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final StockCountItem item;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NeomorphicPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.displayName,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sistema: ${_fmt(item.systemQuantity)} ${item.unit}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Contado',
                    isDense: true,
                  ),
                  onEditingComplete: onSubmit,
                  onTapOutside: (_) => onSubmit(),
                ),
              ),
            ],
          ),
          if (item.hasDivergence) ...[
            const SizedBox(height: 6),
            Text(
              'Divergência: ${item.difference! > 0 ? '+' : ''}'
              '${_fmt(item.difference!)} ${item.unit}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
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
