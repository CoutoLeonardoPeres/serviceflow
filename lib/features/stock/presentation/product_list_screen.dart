import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/stock_notifier.dart';
import '../domain/product.dart';

/// Catálogo de produtos.
class ProductListScreen extends ConsumerWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Produtos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo produto'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nome ou SKU',
              ),
              onChanged: (v) =>
                  ref.read(productSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => ErrorView(
                message: e.toString().replaceAll('Exception: ', ''),
                onRetry: () => ref.invalidate(productsProvider),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return const EmptyView(
                    icon: Icons.inventory_2_outlined,
                    message: 'Nenhum produto cadastrado.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ProductCard(
                    product: products[i],
                    onEdit: () =>
                        _openForm(context, ref, product: products[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    Product? product,
  }) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: product == null ? 'Novo produto' : 'Editar produto',
      maxWidth: 560,
      child: _ProductForm(product: product),
    );
    if (saved == true) {
      ref.invalidate(productsProvider);
      ref.invalidate(stockTrackedProductsProvider);
    }
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onEdit});

  final Product product;
  final VoidCallback onEdit;

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
                  product.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: product.isActive
                        ? null
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Tag(label: product.unit.label),
                    if (!product.trackStock) const _Tag(label: 'Sem estoque'),
                    if (product.minQuantity > 0)
                      _Tag(
                        label:
                            'Mín. ${product.minQuantity.toStringAsFixed(0)}',
                      ),
                    if (!product.isActive) const _Tag(label: 'Inativo'),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.product});

  final Product? product;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _minController;

  late ProductUnit _unit;
  late bool _trackStock;
  late bool _isActive;
  late ProductTrackingType _trackingType;
  bool _saving = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _skuController = TextEditingController(text: p?.sku ?? '');
    _minController = TextEditingController(
      text: p == null || p.minQuantity == 0
          ? ''
          : p.minQuantity.toStringAsFixed(0),
    );
    _unit = p?.unit ?? ProductUnit.un;
    _trackStock = p?.trackStock ?? true;
    _isActive = p?.isActive ?? true;
    _trackingType = p?.trackingType ?? ProductTrackingType.none;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _minController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _serverError = null;
    });

    final repo = ref.read(stockRepositoryProvider);
    final minQty = double.tryParse(_minController.text.replaceAll(',', '.')) ?? 0;

    try {
      if (widget.product == null) {
        await repo.createProduct(
          name: _nameController.text,
          unit: _unit,
          sku: _skuController.text,
          trackStock: _trackStock,
          minQuantity: minQty,
          trackingType: _trackingType,
        );
      } else {
        await repo.updateProduct(
          id: widget.product!.id,
          name: _nameController.text,
          unit: _unit,
          sku: _skuController.text,
          minQuantity: minQty,
          isActive: _isActive,
          trackingType: _trackingType,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _serverError =
            e is AppError ? e.userMessage : 'Não foi possível salvar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.product != null;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Nome *'),
            maxLength: 200,
            validator: (v) {
              if ((v ?? '').trim().length < 2) return 'Informe o nome.';
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _skuController,
            decoration: const InputDecoration(
              labelText: 'SKU',
              helperText: 'Opcional, mas único dentro da empresa.',
            ),
            maxLength: 60,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ProductUnit>(
            isExpanded: true,
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Unidade *'),
            items: ProductUnit.values
                .map((u) => DropdownMenuItem(
                      value: u,
                      child: Text('${u.label} (${u.short})'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _unit = v ?? ProductUnit.un),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _minController,
            decoration: const InputDecoration(
              labelText: 'Quantidade mínima',
              helperText: 'Alerta quando o saldo ficar abaixo. 0 desliga.',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),

          // track_stock não é editável depois de criado: alternar isso com
          // saldo e movimentos existentes deixaria o razão inconsistente.
          if (!isEditing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _trackStock,
              onChanged: (v) => setState(() => _trackStock = v),
              title: const Text('Controlar estoque'),
              subtitle: const Text(
                'Desligue para serviços e itens sem saldo.',
              ),
            )
          else if (!widget.product!.trackStock)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Este produto não controla estoque. Para mudar isso, cadastre '
                'um novo produto — alternar com histórico existente deixaria o '
                'razão inconsistente.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          if (_trackStock) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<ProductTrackingType>(
              isExpanded: true,
              initialValue: _trackingType,
              decoration: const InputDecoration(
                labelText: 'Rastreio',
                helperText: 'Opcional. Exige lote/série a cada movimento.',
              ),
              items: ProductTrackingType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _trackingType = v ?? ProductTrackingType.none),
            ),
          ],

          if (isEditing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('Ativo'),
              subtitle: const Text(
                'Inativo some dos seletores, mas mantém o histórico.',
              ),
            ),

          if (_serverError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _serverError!,
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
    );
  }
}
