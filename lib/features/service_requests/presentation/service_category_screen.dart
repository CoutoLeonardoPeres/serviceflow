import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../professionals/domain/professional_categories.dart';
import '../application/service_request_list_notifier.dart';
import '../domain/service_category.dart';

/// Cadastro de categorias de chamado — mesmo padrão visual do cadastro
/// de profissionais (AppFormSection com busca + cards abaixo).
class ServiceCategoryScreen extends ConsumerStatefulWidget {
  const ServiceCategoryScreen({super.key});

  @override
  ConsumerState<ServiceCategoryScreen> createState() =>
      _ServiceCategoryScreenState();
}

class _ServiceCategoryScreenState extends ConsumerState<ServiceCategoryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(serviceCategoriesAllProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categorias de chamado')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova categoria'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => ErrorView(
          message: e.toString().replaceAll('Exception: ', ''),
          onRetry: () => ref.invalidate(serviceCategoriesAllProvider),
        ),
        data: (categories) {
          final search = _searchController.text.trim().toLowerCase();
          final filtered = search.isEmpty
              ? categories
              : categories
                  .where((c) => c.name.toLowerCase().contains(search))
                  .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              AppFormSection(
                title: 'Categorias de chamado',
                icon: Icons.label_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar categoria',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    NeomorphicInset(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${categories.length}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(width: 8),
                          const Text('cadastradas'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const NeomorphicPanel(
                  borderRadius: 28,
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nenhuma categoria encontrada.'),
                  ),
                )
              else
                ...filtered.map(
                  (category) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CategoryCard(
                      category: category,
                      onEdit: () =>
                          _openForm(context, ref, category: category),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    ServiceCategory? category,
  }) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: category == null ? 'Nova categoria' : 'Editar categoria',
      maxWidth: 480,
      child: _CategoryForm(category: category),
    );
    if (saved == true) {
      ref.invalidate(serviceCategoriesAllProvider);
      ref.invalidate(serviceRequestCategoriesProvider);
    }
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onEdit});

  final ServiceCategory category;
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
                  category.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: category.isActive
                        ? null
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (category.description != null &&
                    category.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      category.description!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (!category.isActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Inativa', style: theme.textTheme.labelSmall),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
        ],
      ),
    );
  }
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.category});

  final ServiceCategory? category;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descriptionController;
  late String _name;
  late bool _isActive;
  bool _saving = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _name = c != null && c.name.trim().isNotEmpty
        ? c.name
        : professionalCategories.first;
    _descriptionController = TextEditingController(text: c?.description ?? '');
    _isActive = c?.isActive ?? true;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _serverError = null;
    });

    final repo = ref.read(serviceRequestRepositoryProvider);
    try {
      if (widget.category == null) {
        await repo.createCategory(
          name: _name,
          description: _descriptionController.text,
        );
      } else {
        await repo.updateCategory(
          id: widget.category!.id,
          name: _name,
          description: _descriptionController.text,
          isActive: _isActive,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _serverError = e is AppError ? e.userMessage : 'Não foi possível salvar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _name,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Nome *'),
            items: [
              ...professionalCategories,
              if (!professionalCategories.contains(_name)) _name,
            ]
                .map(
                  (category) => DropdownMenuItem(
                    value: category,
                    child: Text(category, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _name = value ?? professionalCategories.first),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Descrição'),
            maxLines: 2,
          ),
          if (widget.category != null) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativa'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
          if (_serverError != null) ...[
            const SizedBox(height: 8),
            Text(_serverError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
