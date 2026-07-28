import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../stock/application/stock_notifier.dart';
import '../../stock/domain/product.dart';
import '../application/purchase_notifier.dart';
import '../domain/material_catalog.dart';
import '../domain/supplier.dart';
import 'price_import_screen.dart';

/// Tabela de preços de um fornecedor.
///
/// É a fonte de preço do orçamento: sem ela, quem monta a proposta digita o
/// valor de cabeça e o "melhor preço" não existe — existe o que a pessoa
/// lembra.
class SupplierPricesScreen extends ConsumerWidget {
  const SupplierPricesScreen({super.key, required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pricesAsync = ref.watch(supplierPricesProvider(supplier.id));
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: Text('Preços · ${supplier.displayName}'),
        actions: [
          IconButton(
            tooltip: 'Importar planilha',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PriceImportScreen(supplier: supplier),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo preço'),
      ),
      body: pricesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => ErrorView(
          message: e is AppError ? e.userMessage : e.toString(),
          onRetry: () => ref.invalidate(supplierPricesProvider(supplier.id)),
        ),
        data: (prices) {
          if (prices.isEmpty) {
            return const EmptyView(
              icon: Icons.request_quote_outlined,
              message: 'Nenhum preço cadastrado para este fornecedor.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: prices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _PriceCard(
              price: prices[i],
              currency: currency,
              onEdit: () => _openForm(context, ref, price: prices[i]),
              onDelete: () => _delete(context, ref, prices[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    SupplierPrice? price,
  }) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: price == null ? 'Novo preço' : 'Editar preço',
      maxWidth: 720,
      child: _PriceForm(supplierId: supplier.id, price: price),
    );
    if (saved == true) ref.invalidate(supplierPricesProvider(supplier.id));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SupplierPrice price,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover preço'),
        content: Text(
          'Remover ${price.productName ?? 'este item'} da tabela deste '
          'fornecedor? O histórico de preço é mantido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(purchaseRepositoryProvider).deleteSupplierPrice(price.id);
      ref.invalidate(supplierPricesProvider(supplier.id));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AppError ? e.userMessage : 'Não foi possível remover.',
          ),
        ),
      );
    }
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.price,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  final SupplierPrice price;
  final NumberFormat currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NeomorphicPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  price.productName ?? 'Produto',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (price.supplierCode != null &&
                        price.supplierCode!.isNotEmpty)
                      'Cód. ${price.supplierCode}',
                    if (price.packQuantity != 1)
                      'Embalagem ${price.packQuantity}',
                    if (price.minQuantity > 0) 'Mín. ${price.minQuantity}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (price.isStale) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tabela vencida em '
                    '${DateFormat('dd/MM/yyyy').format(price.validUntil!)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          Text(
            currency.format(price.priceCents / 100),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: price.isStale ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _PriceForm extends ConsumerStatefulWidget {
  const _PriceForm({required this.supplierId, this.price});

  final String supplierId;
  final SupplierPrice? price;

  @override
  ConsumerState<_PriceForm> createState() => _PriceFormState();
}

class _PriceFormState extends ConsumerState<_PriceForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _price;
  late final TextEditingController _pack;
  late final TextEditingController _min;
  String? _productId;
  DateTime? _validUntil;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.price;
    _code = TextEditingController(text: p?.supplierCode ?? '');
    _price = TextEditingController(
      text: p == null ? '' : (p.priceCents / 100).toStringAsFixed(2),
    );
    _pack = TextEditingController(text: (p?.packQuantity ?? 1).toString());
    _min = TextEditingController(text: (p?.minQuantity ?? 0).toString());
    _productId = p?.productId;
    _validUntil = p?.validUntil;
  }

  @override
  void dispose() {
    _code.dispose();
    _price.dispose();
    _pack.dispose();
    _min.dispose();
    super.dispose();
  }

  int _cents(String raw) {
    final normalized =
        raw.replaceAll(RegExp(r'[^0-9,.]'), '').replaceAll(',', '.');
    return ((double.tryParse(normalized) ?? 0) * 100).round();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_productId == null) {
      setState(() => _error = 'Escolha o produto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(purchaseRepositoryProvider).saveSupplierPrice(
            SupplierPrice(
              id: widget.price?.id ?? '',
              supplierId: widget.supplierId,
              productId: _productId!,
              supplierCode: _code.text,
              priceCents: _cents(_price.text),
              packQuantity: num.tryParse(_pack.text.replaceAll(',', '.')) ?? 1,
              minQuantity: num.tryParse(_min.text.replaceAll(',', '.')) ?? 0,
              validUntil: _validUntil,
              isActive: true,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is AppError ? e.userMessage : 'Não foi possível salvar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(productsProvider);

    // Mesmo motivo do formulário de fornecedor: o diálogo não rola sozinho.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          AppFormSection(
            title: 'Item da tabela',
            icon: Icons.sell_outlined,
            child: AppFormGrid(
              children: [
                AppFormFieldSpan(
                  columns: 2,
                  child: productsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) =>
                        const Text('Não foi possível carregar os produtos.'),
                    data: (products) => DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _productId,
                      decoration: const InputDecoration(
                        labelText: 'Produto *',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      items: [
                        for (final Product p in products)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (v) => setState(() => _productId = v),
                    ),
                  ),
                ),
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Código do fornecedor',
                    helperText: 'É por ele que a planilha casa',
                  ),
                  maxLength: 60,
                ),
                TextFormField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Preço de compra *',
                    prefixText: 'R\$ ',
                  ),
                  validator: (v) =>
                      _cents(v ?? '') <= 0 ? 'Informe o preço.' : null,
                ),
                TextFormField(
                  controller: _pack,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Embalagem',
                    helperText: 'Quantidade por unidade de venda',
                  ),
                ),
                TextFormField(
                  controller: _min,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Quantidade mínima'),
                ),
                AppFormFieldSpan(
                  columns: 2,
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _validUntil ?? DateTime.now(),
                        firstDate: DateTime.now()
                            .subtract(const Duration(days: 365)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365 * 3)),
                      );
                      if (picked != null) setState(() => _validUntil = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tabela válida até',
                        prefixIcon: Icon(Icons.event_outlined),
                        helperText: 'Vencida, perde a vez no melhor preço',
                      ),
                      child: Text(
                        _validUntil == null
                            ? 'Sem validade'
                            : DateFormat('dd/MM/yyyy').format(_validUntil!),
                      ),
                    ),
                  ),
                ),
              ],
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
          const SizedBox(height: 20),
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
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
