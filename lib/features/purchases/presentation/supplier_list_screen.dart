import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/purchase_notifier.dart';
import '../domain/supplier.dart';

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
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: supplier == null ? 'Novo fornecedor' : 'Editar fornecedor',
      maxWidth: 560,
      child: _SupplierForm(supplier: supplier),
    );
    if (saved == true) ref.invalidate(suppliersProvider);
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier, required this.onEdit});

  final Supplier supplier;
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
  late final TextEditingController _name;
  late final TextEditingController _tradeName;
  late final TextEditingController _document;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late bool _isActive;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _name = TextEditingController(text: s?.name ?? '');
    _tradeName = TextEditingController(text: s?.tradeName ?? '');
    _document = TextEditingController(text: s?.document ?? '');
    _email = TextEditingController(text: s?.email ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _isActive = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _tradeName.dispose();
    _document.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(purchaseRepositoryProvider);

    try {
      if (widget.supplier == null) {
        await repo.createSupplier(
          name: _name.text,
          tradeName: _tradeName.text,
          document: _document.text,
          email: _email.text,
          phone: _phone.text,
        );
      } else {
        await repo.updateSupplier(
          id: widget.supplier!.id,
          name: _name.text,
          tradeName: _tradeName.text,
          document: _document.text,
          email: _email.text,
          phone: _phone.text,
          isActive: _isActive,
        );
      }
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

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Razão social *'),
            maxLength: 200,
            validator: (v) =>
                (v ?? '').trim().length < 2 ? 'Informe o nome.' : null,
          ),
          TextFormField(
            controller: _tradeName,
            decoration: const InputDecoration(labelText: 'Nome fantasia'),
            maxLength: 200,
          ),
          TextFormField(
            controller: _document,
            decoration: const InputDecoration(
              labelText: 'CNPJ / CPF',
              helperText: 'Único por empresa, quando informado.',
            ),
            maxLength: 20,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Telefone'),
            maxLength: 20,
          ),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'E-mail'),
            maxLength: 160,
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
    );
  }
}
