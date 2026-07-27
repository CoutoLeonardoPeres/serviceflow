import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/service_request_list_notifier.dart';
import '../domain/service_category.dart';

/// Cadastro de categorias de chamado.
class ServiceCategoryScreen extends ConsumerWidget {
  const ServiceCategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          if (categories.isEmpty) {
            return const EmptyView(
              icon: Icons.label_outline,
              message: 'Nenhuma categoria cadastrada.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _CategoryCard(
              category: categories[i],
              onEdit: () => _openForm(context, ref, category: categories[i]),
            ),
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
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late bool _isActive;
  bool _saving = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _nameController = TextEditingController(text: c?.name ?? '');
    _descriptionController = TextEditingController(text: c?.description ?? '');
    _isActive = c?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
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
          name: _nameController.text,
          description: _descriptionController.text,
        );
      } else {
        await repo.updateCategory(
          id: widget.category!.id,
          name: _nameController.text,
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
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Nome *'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
            autofocus: true,
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
