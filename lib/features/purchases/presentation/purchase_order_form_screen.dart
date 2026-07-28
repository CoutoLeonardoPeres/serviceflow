import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../stock/application/stock_notifier.dart';
import '../../stock/domain/product.dart';
import '../application/purchase_notifier.dart';

/// Criação de pedido de compra.
///
/// O pedido nasce em rascunho e não movimenta estoque — a entrada só acontece
/// no recebimento.
class PurchaseOrderFormScreen extends ConsumerStatefulWidget {
  const PurchaseOrderFormScreen({super.key});

  @override
  ConsumerState<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState
    extends ConsumerState<PurchaseOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  String? _supplierId;
  String? _warehouseId;
  DateTime? _expectedAt;
  final _items = <_DraftItem>[];

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  int get _totalCents => _items.fold(0, (sum, i) => sum + i.totalCents);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_supplierId == null || _warehouseId == null) {
      setState(() => _error = 'Escolha o fornecedor e o depósito.');
      return;
    }

    final valid = _items.where((i) => i.isValid).toList();
    if (valid.isEmpty) {
      setState(() => _error = 'Adicione ao menos um item válido.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final id = await ref.read(purchaseRepositoryProvider).createOrder(
            supplierId: _supplierId!,
            warehouseId: _warehouseId!,
            items: valid
                .map((i) => (
                      productId: i.productId!,
                      quantity: i.quantity,
                      unitCostCents: i.unitCostCents,
                    ))
                .toList(),
            expectedAt: _expectedAt,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      ref.invalidate(purchaseOrdersProvider);
      if (!mounted) return;
      context.pushReplacement(AppRoutes.purchaseOrderDetail(id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AppError ? e.userMessage : 'Não foi possível criar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final suppliersAsync = ref.watch(suppliersProvider);
    final warehousesAsync = ref.watch(warehousesProvider);
    final productsAsync = ref.watch(stockTrackedProductsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Novo pedido de compra')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            NeomorphicPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  suppliersAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) =>
                        const Text('Erro ao carregar fornecedores.'),
                    data: (suppliers) => DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _supplierId,
                      decoration:
                          const InputDecoration(labelText: 'Fornecedor *'),
                      items: suppliers
                          .map((s) => DropdownMenuItem(
                                value: s.id,
                                child: Text(s.name),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _supplierId = v),
                      validator: (v) =>
                          v == null ? 'Escolha o fornecedor.' : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  warehousesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const Text('Erro ao carregar depósitos.'),
                    data: (warehouses) {
                      _warehouseId ??= warehouses
                          .where((w) => w.isDefault)
                          .firstOrNull
                          ?.id;
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _warehouseId,
                        decoration: const InputDecoration(
                          labelText: 'Depósito de entrada *',
                          helperText:
                              'Onde a mercadoria entra no recebimento.',
                        ),
                        items: warehouses
                            .map((w) => DropdownMenuItem(
                                  value: w.id,
                                  child: Text(w.name),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _warehouseId = v),
                        validator: (v) =>
                            v == null ? 'Escolha o depósito.' : null,
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _expectedAt ?? DateTime.now(),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 365)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setState(() => _expectedAt = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Previsão de entrega',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(
                        _expectedAt == null
                            ? 'Não informada'
                            : DateFormat('dd/MM/yyyy', 'pt_BR')
                                .format(_expectedAt!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Itens',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  currency.format(_totalCents / 100),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Erro ao carregar produtos.'),
              data: (products) => Column(
                children: [
                  ..._items.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ItemEditor(
                            item: e.value,
                            products: products,
                            onChanged: () => setState(() {}),
                            onRemove: () => setState(() {
                              _items.removeAt(e.key).dispose();
                            }),
                          ),
                        ),
                      ),
                  OutlinedButton.icon(
                    onPressed: products.isEmpty
                        ? null
                        : () => setState(() => _items.add(_DraftItem())),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar item'),
                  ),
                  if (products.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Cadastre produtos no estoque antes de montar o pedido.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Criando…' : 'Criar pedido'),
            ),
            const SizedBox(height: 8),
            Text(
              'O pedido nasce como rascunho e não movimenta estoque. A entrada '
              'acontece no recebimento.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Item em edição, antes de virar linha do pedido.
class _DraftItem {
  final quantityController = TextEditingController(text: '1');
  final costController = TextEditingController();
  String? productId;

  double get quantity =>
      double.tryParse(quantityController.text.replaceAll(',', '.')) ?? 0;

  int get unitCostCents {
    final v = double.tryParse(costController.text.replaceAll(',', '.')) ?? 0;
    return (v * 100).round();
  }

  int get totalCents => (quantity * unitCostCents).round();

  bool get isValid => productId != null && quantity > 0;

  void dispose() {
    quantityController.dispose();
    costController.dispose();
  }
}

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    required this.item,
    required this.products,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftItem item;
  final List<Product> products;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return NeomorphicPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: item.productId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Produto *',
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
                    item.productId = v;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: item.quantityController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Quantidade',
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: item.costController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Custo unitário (R\$)',
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
