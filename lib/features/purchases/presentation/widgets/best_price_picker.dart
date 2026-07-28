import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/widgets/neomorphic.dart';
import '../../../stock/application/stock_notifier.dart';
import '../../../stock/domain/product.dart';
import '../../application/purchase_notifier.dart';
import '../../domain/material_catalog.dart';

/// O que o chamador recebe quando alguém escolhe uma origem para o material.
///
/// Traz custo e preço de venda separados: o orçamento precisa dos dois — um
/// para a margem, outro para a proposta.
class MaterialSourceChoice {
  const MaterialSourceChoice({
    required this.productId,
    required this.productName,
    required this.unitCostCents,
    required this.unitPriceCents,
    this.supplierId,
    this.supplierName,
    this.fromStock = false,
  });

  final String productId;
  final String productName;
  final int unitCostCents;
  final int unitPriceCents;
  final String? supplierId;
  final String? supplierName;

  /// Escolha foi o saldo próprio, não uma compra.
  final bool fromStock;
}

/// Escolhe o material e de onde ele vem, mostrando o ranking de fornecedores.
///
/// Existe uma vez só e é usado pelo orçamento e pela OS: eram duas telas
/// digitando preço de cabeça, e duplicar o ranking garantiria que uma das
/// duas ficaria desatualizada.
Future<MaterialSourceChoice?> showMaterialSourcePicker({
  required BuildContext context,
  String? initialProductId,
}) {
  return showDialog<MaterialSourceChoice>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: _MaterialSourcePicker(initialProductId: initialProductId),
      ),
    ),
  );
}

class _MaterialSourcePicker extends ConsumerStatefulWidget {
  const _MaterialSourcePicker({this.initialProductId});

  final String? initialProductId;

  @override
  ConsumerState<_MaterialSourcePicker> createState() =>
      _MaterialSourcePickerState();
}

class _MaterialSourcePickerState extends ConsumerState<_MaterialSourcePicker> {
  String? _productId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _productId = widget.initialProductId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(productsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Escolher material',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar no catálogo',
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                e is AppError ? e.userMessage : 'Erro ao carregar o catálogo.',
              ),
            ),
            data: (products) {
              final filtered = _search.isEmpty
                  ? products
                  : products
                      .where((p) =>
                          p.name.toLowerCase().contains(_search) ||
                          (p.sku ?? '').toLowerCase().contains(_search))
                      .toList();

              if (_productId != null) {
                final Product? selected =
                    products.where((p) => p.id == _productId).firstOrNull;
                if (selected != null) {
                  return _SupplierRanking(
                    product: selected,
                    onBack: () => setState(() => _productId = null),
                  );
                }
              }

              if (filtered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nenhum material encontrado.'),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final product = filtered[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(product.name),
                    subtitle: product.sku == null
                        ? null
                        : Text(product.sku!,
                            style: theme.textTheme.bodySmall),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _productId = product.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SupplierRanking extends ConsumerWidget {
  const _SupplierRanking({required this.product, required this.onBack});

  final Product product;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final optionsAsync = ref.watch(bestPricesProvider(product.id));

    return optionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          e is AppError ? e.userMessage : 'Erro ao buscar os preços.',
        ),
      ),
      data: (options) {
        final stockQuantity =
            options.isEmpty ? 0 : options.first.stockQuantity;
        final stockCost =
            options.isEmpty ? 0 : options.first.stockAvgCostCents;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    product.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Saldo próprio primeiro: sai na hora, sem compra e sem prazo.
            if (stockQuantity > 0)
              _SourceTile(
                title: 'Usar do estoque',
                subtitle: 'Saldo de $stockQuantity ${product.unit.value} · '
                    'custo médio ${currency.format(stockCost / 100)}',
                trailing: currency.format(
                  _clientPriceFromStock(options, stockCost) / 100,
                ),
                highlight: true,
                onTap: () => Navigator.of(context).pop(
                  MaterialSourceChoice(
                    productId: product.id,
                    productName: product.name,
                    unitCostCents: stockCost,
                    unitPriceCents:
                        _clientPriceFromStock(options, stockCost),
                    fromStock: true,
                  ),
                ),
              ),

            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  stockQuantity > 0
                      ? 'Nenhum fornecedor com preço cadastrado para este '
                          'material — só o saldo próprio.'
                      : 'Nenhum fornecedor com preço cadastrado, e sem saldo '
                          'em estoque. Cadastre um preço na tela do '
                          'fornecedor ou importe a tabela dele.',
                  style: theme.textTheme.bodySmall,
                ),
              ),

            for (var i = 0; i < options.length; i++)
              _SourceTile(
                title: options[i].supplierName,
                subtitle: [
                  'Custo ${currency.format(options[i].priceCents / 100)}',
                  if (options[i].leadTimeDays != null)
                    '${options[i].leadTimeDays} dia(s)',
                  if (options[i].isStale) 'tabela vencida',
                ].join(' · '),
                trailing:
                    currency.format(options[i].clientPriceCents / 100),
                // Só o primeiro válido ganha destaque: dois "melhores" não
                // ajudam ninguém a decidir.
                highlight: i == 0 && !options[i].isStale && stockQuantity <= 0,
                muted: options[i].isStale,
                onTap: () => Navigator.of(context).pop(
                  MaterialSourceChoice(
                    productId: product.id,
                    productName: product.name,
                    unitCostCents: options[i].priceCents,
                    unitPriceCents: options[i].clientPriceCents,
                    supplierId: options[i].supplierId,
                    supplierName: options[i].supplierName,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Material do estoque também tem repasse — a margem é a mesma do produto,
  /// aplicada sobre o custo médio em vez do preço do fornecedor.
  int _clientPriceFromStock(List<BestPriceOption> options, int stockCost) {
    final markup = options.isEmpty ? 0.0 : options.first.markupPercent;
    return applyMarkup(stockCost, markup);
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.highlight = false,
    this.muted = false,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;
  final bool highlight;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NeomorphicPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: muted
                                    ? theme.colorScheme.onSurfaceVariant
                                    : null,
                              ),
                            ),
                          ),
                          if (highlight) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'melhor opção',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      trailing,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color:
                            muted ? theme.colorScheme.onSurfaceVariant : null,
                      ),
                    ),
                    Text(
                      'ao cliente',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
