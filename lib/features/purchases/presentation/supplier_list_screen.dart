import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../application/purchase_notifier.dart';
import '../domain/material_catalog.dart';
import '../domain/supplier.dart';
import 'supplier_prices_screen.dart';

/// Cadastro de fornecedores.
class SupplierListScreen extends ConsumerWidget {
  const SupplierListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fornecedores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo fornecedor'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar fornecedor',
              ),
              onChanged: (v) =>
                  ref.read(supplierSearchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: suppliersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => ErrorView(
                message: e is AppError
                    ? e.userMessage
                    : e.toString().replaceAll('Exception: ', ''),
                onRetry: () => ref.invalidate(suppliersProvider),
              ),
              data: (suppliers) {
                if (suppliers.isEmpty) {
                  return const EmptyView(
                    icon: Icons.local_shipping_outlined,
                    message: 'Nenhum fornecedor cadastrado.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: suppliers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _SupplierCard(
                    supplier: suppliers[i],
                    onEdit: () =>
                        _openForm(context, ref, supplier: suppliers[i]),
                    onPrices: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SupplierPricesScreen(supplier: suppliers[i]),
                      ),
                    ),
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
    Supplier? supplier,
  }) async {
    // A lista não traz as categorias vinculadas — buscar o detalhe evita
    // salvar o fornecedor apagando os vínculos que a tela não conhecia.
    var loaded = supplier;
    if (supplier != null) {
      try {
        loaded = await ref
            .read(purchaseRepositoryProvider)
            .getSupplier(supplier.id);
      } catch (_) {
        loaded = supplier;
      }
    }
    if (!context.mounted) return;

    final saved = await showAppFormDialog<bool>(
      context: context,
      title: supplier == null ? 'Novo fornecedor' : 'Editar fornecedor',
      maxWidth: 880,
      child: _SupplierForm(supplier: loaded),
    );
    if (saved == true) ref.invalidate(suppliersProvider);
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.onEdit,
    required this.onPrices,
  });

  final Supplier supplier;
  final VoidCallback onEdit;
  final VoidCallback onPrices;

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
                  supplier.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: supplier.isActive
                        ? null
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (supplier.document != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    supplier.document!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (supplier.location.isNotEmpty ||
                    supplier.leadTimeDays != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (supplier.location.isNotEmpty) supplier.location,
                      if (supplier.leadTimeDays != null)
                        supplier.leadTimeLabel,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (supplier.phone != null || supplier.email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [supplier.phone, supplier.email]
                        .whereType<String>()
                        .join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (!supplier.isActive) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Inativo',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Tabela de preços',
            icon: const Icon(Icons.request_quote_outlined),
            onPressed: onPrices,
          ),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _SupplierForm extends ConsumerStatefulWidget {
  const _SupplierForm({this.supplier});

  final Supplier? supplier;

  @override
  ConsumerState<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends ConsumerState<_SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  late bool _isActive;
  late bool _delivers;
  Set<String> _categoryIds = {};

  bool _saving = false;
  String? _error;

  TextEditingController _c(String key, [String? initial]) =>
      _controllers.putIfAbsent(
        key,
        () => TextEditingController(text: initial ?? ''),
      );

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _c('name', s?.name);
    _c('tradeName', s?.tradeName);
    _c('document', s?.document);
    _c('stateRegistration', s?.stateRegistration);
    _c('contactName', s?.contactName);
    _c('phone', s?.phone);
    _c('whatsapp', s?.whatsapp);
    _c('email', s?.email);
    _c('website', s?.website);
    _c('zipCode', s?.zipCode);
    _c('street', s?.street);
    _c('number', s?.number);
    _c('complement', s?.complement);
    _c('district', s?.district);
    _c('city', s?.city);
    _c('state', s?.state);
    _c('leadTime', s?.leadTimeDays?.toString());
    _c('paymentTerms', s?.paymentTerms);
    _c('minOrder', s == null || s.minOrderCents == 0
        ? ''
        : (s.minOrderCents / 100).toStringAsFixed(2).replaceAll('.', ','));
    _c('notes', s?.notes);
    _isActive = s?.isActive ?? true;
    _delivers = s?.delivers ?? true;
    _categoryIds = {...?s?.categoryIds};
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _parseMoneyCents(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9,.]'), '').replaceAll(',', '.');
    final value = double.tryParse(digits) ?? 0;
    return (value * 100).round();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final existing = widget.supplier;
    final supplier = Supplier(
      id: existing?.id ?? '',
      tenantId: existing?.tenantId ?? '',
      name: _c('name').text,
      tradeName: _c('tradeName').text,
      document: _c('document').text,
      stateRegistration: _c('stateRegistration').text,
      contactName: _c('contactName').text,
      phone: _c('phone').text,
      whatsapp: _c('whatsapp').text,
      email: _c('email').text,
      website: _c('website').text,
      zipCode: _c('zipCode').text,
      street: _c('street').text,
      number: _c('number').text,
      complement: _c('complement').text,
      district: _c('district').text,
      city: _c('city').text,
      state: _c('state').text.toUpperCase(),
      leadTimeDays: int.tryParse(_c('leadTime').text.trim()),
      paymentTerms: _c('paymentTerms').text,
      minOrderCents: _parseMoneyCents(_c('minOrder').text),
      delivers: _delivers,
      notes: _c('notes').text,
      isActive: _isActive,
      createdAt: existing?.createdAt ?? DateTime.now(),
      categoryIds: _categoryIds.toList(),
    );

    try {
      await ref.read(purchaseRepositoryProvider).saveSupplier(supplier);
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
    final categoriesAsync = ref.watch(materialCategoriesProvider);

    // O diálogo limita a altura em 760 e NÃO rola sozinho — quem rola é cada
    // formulário. Com cinco seções, sem isto o conteúdo estoura por ~800px.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          AppFormSection(
            title: 'Identificação',
            icon: Icons.badge_outlined,
            child: AppFormGrid(
              children: [
                AppFormFieldSpan(
                  columns: 2,
                  child: TextFormField(
                    controller: _c('name'),
                    decoration:
                        const InputDecoration(labelText: 'Razão social *'),
                    maxLength: 200,
                    validator: (v) =>
                        (v ?? '').trim().length < 2 ? 'Informe o nome.' : null,
                  ),
                ),
                TextFormField(
                  controller: _c('tradeName'),
                  decoration: const InputDecoration(labelText: 'Nome fantasia'),
                  maxLength: 200,
                ),
                TextFormField(
                  controller: _c('document'),
                  decoration: const InputDecoration(labelText: 'CNPJ / CPF'),
                  maxLength: 20,
                ),
                TextFormField(
                  controller: _c('stateRegistration'),
                  decoration: const InputDecoration(
                    labelText: 'Inscrição estadual',
                  ),
                  maxLength: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppFormSection(
            title: 'Contato',
            icon: Icons.contact_phone_outlined,
            child: AppFormGrid(
              children: [
                TextFormField(
                  controller: _c('contactName'),
                  decoration: const InputDecoration(
                    labelText: 'Pessoa de contato',
                  ),
                  maxLength: 120,
                ),
                TextFormField(
                  controller: _c('phone'),
                  decoration: const InputDecoration(labelText: 'Telefone'),
                  maxLength: 20,
                ),
                TextFormField(
                  controller: _c('whatsapp'),
                  decoration: const InputDecoration(labelText: 'WhatsApp'),
                  maxLength: 20,
                ),
                AppFormFieldSpan(
                  columns: 2,
                  child: TextFormField(
                    controller: _c('email'),
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    maxLength: 160,
                  ),
                ),
                TextFormField(
                  controller: _c('website'),
                  decoration: const InputDecoration(labelText: 'Site'),
                  maxLength: 200,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppFormSection(
            title: 'Endereço',
            icon: Icons.location_on_outlined,
            child: AppFormGrid(
              children: [
                TextFormField(
                  controller: _c('zipCode'),
                  decoration: const InputDecoration(labelText: 'CEP'),
                  maxLength: 12,
                ),
                AppFormFieldSpan(
                  columns: 2,
                  child: TextFormField(
                    controller: _c('street'),
                    decoration: const InputDecoration(labelText: 'Logradouro'),
                    maxLength: 200,
                  ),
                ),
                TextFormField(
                  controller: _c('number'),
                  decoration: const InputDecoration(labelText: 'Número'),
                  maxLength: 20,
                ),
                TextFormField(
                  controller: _c('complement'),
                  decoration: const InputDecoration(labelText: 'Complemento'),
                  maxLength: 100,
                ),
                TextFormField(
                  controller: _c('district'),
                  decoration: const InputDecoration(labelText: 'Bairro'),
                  maxLength: 100,
                ),
                TextFormField(
                  controller: _c('city'),
                  decoration: const InputDecoration(labelText: 'Cidade'),
                  maxLength: 100,
                ),
                TextFormField(
                  controller: _c('state'),
                  decoration: const InputDecoration(labelText: 'UF'),
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty || value.length == 2) return null;
                    return 'Use a sigla, com 2 letras.';
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppFormSection(
            title: 'Condições comerciais',
            icon: Icons.handshake_outlined,
            child: AppFormGrid(
              children: [
                TextFormField(
                  controller: _c('leadTime'),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prazo de entrega',
                    suffixText: 'dias',
                  ),
                ),
                AppFormFieldSpan(
                  columns: 2,
                  child: TextFormField(
                    controller: _c('paymentTerms'),
                    decoration: const InputDecoration(
                      labelText: 'Condição de pagamento',
                      hintText: 'à vista · 28 dd · 30/60/90',
                    ),
                    maxLength: 200,
                  ),
                ),
                TextFormField(
                  controller: _c('minOrder'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Pedido mínimo',
                    prefixText: 'R\$ ',
                    helperText: 'Deixe vazio se não houver',
                  ),
                ),
                AppFormFieldSpan(
                  columns: 2,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _delivers,
                    onChanged: (v) => setState(() => _delivers = v),
                    title: const Text('Entrega no local'),
                    subtitle: const Text('Desligado = retirada no balcão'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppFormSection(
            title: 'O que este fornecedor atende',
            icon: Icons.category_outlined,
            child: categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text(
                'Não foi possível carregar as categorias agora.',
              ),
              data: (categories) {
                if (categories.isEmpty) {
                  return _EmptyCategories(
                    onSeed: () async {
                      await ref
                          .read(purchaseRepositoryProvider)
                          .seedCategories();
                      ref.invalidate(materialCategoriesProvider);
                    },
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in categories)
                      FilterChip(
                        label: Text(category.name),
                        selected: _categoryIds.contains(category.id),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _categoryIds.add(category.id);
                          } else {
                            _categoryIds.remove(category.id);
                          }
                        }),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _c('notes'),
            decoration: const InputDecoration(labelText: 'Observações'),
            maxLines: 3,
            maxLength: 1000,
          ),
          if (widget.supplier != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('Ativo'),
              subtitle: const Text(
                'Inativo some dos seletores, mas mantém os pedidos.',
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

/// Primeiro acesso: ninguém quer digitar 24 categorias à mão.
class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories({required this.onSeed});

  final Future<void> Function() onSeed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nenhuma categoria cadastrada ainda. Posso criar as do setor '
          '(elétrica, hidráulica, CFTV, piscina, gesso, vidraçaria…) para '
          'você ajustar depois.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onSeed,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Criar categorias padrão'),
        ),
      ],
    );
  }
}
