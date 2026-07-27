import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/service_request_list_notifier.dart';
import '../domain/service_priority.dart';

/// Cadastro de prioridades de chamado — mesmo padrão visual do cadastro
/// de profissionais (AppFormSection com busca + cards abaixo).
class ServicePriorityScreen extends ConsumerStatefulWidget {
  const ServicePriorityScreen({super.key});

  @override
  ConsumerState<ServicePriorityScreen> createState() =>
      _ServicePriorityScreenState();
}

class _ServicePriorityScreenState extends ConsumerState<ServicePriorityScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prioritiesAsync = ref.watch(servicePrioritiesAllProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Prioridades de chamado')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova prioridade'),
      ),
      body: prioritiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => ErrorView(
          message: e.toString().replaceAll('Exception: ', ''),
          onRetry: () => ref.invalidate(servicePrioritiesAllProvider),
        ),
        data: (priorities) {
          final search = _searchController.text.trim().toLowerCase();
          final filtered = search.isEmpty
              ? priorities
              : priorities
                  .where((p) => p.name.toLowerCase().contains(search))
                  .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              AppFormSection(
                title: 'Prioridades de chamado',
                icon: Icons.flag_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar prioridade',
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
                            '${priorities.length}',
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
                    child: Text('Nenhuma prioridade encontrada.'),
                  ),
                )
              else
                ...filtered.map(
                  (priority) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PriorityCard(
                      priority: priority,
                      onEdit: () =>
                          _openForm(context, ref, priority: priority),
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
    ServicePriority? priority,
  }) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: priority == null ? 'Nova prioridade' : 'Editar prioridade',
      maxWidth: 480,
      child: _PriorityForm(priority: priority),
    );
    if (saved == true) {
      ref.invalidate(servicePrioritiesAllProvider);
      ref.invalidate(serviceRequestPrioritiesProvider);
    }
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.priority, required this.onEdit});

  final ServicePriority priority;
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
                  priority.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: priority.isActive
                        ? null
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Tag(label: 'Nível ${priority.level}'),
                    if (priority.slaHours != null)
                      _Tag(label: 'SLA ${priority.slaHours}h'),
                    if (!priority.isActive) const _Tag(label: 'Inativa'),
                  ],
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

class _PriorityForm extends ConsumerStatefulWidget {
  const _PriorityForm({this.priority});

  final ServicePriority? priority;

  @override
  ConsumerState<_PriorityForm> createState() => _PriorityFormState();
}

class _PriorityFormState extends ConsumerState<_PriorityForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _levelController;
  late final TextEditingController _slaController;
  late bool _isActive;
  bool _saving = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final p = widget.priority;
    _nameController = TextEditingController(text: p?.name ?? '');
    _levelController = TextEditingController(text: p?.level.toString() ?? '');
    _slaController = TextEditingController(text: p?.slaHours?.toString() ?? '');
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _levelController.dispose();
    _slaController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _serverError = null;
    });

    final repo = ref.read(serviceRequestRepositoryProvider);
    final level = int.parse(_levelController.text.trim());
    final sla = _slaController.text.trim().isEmpty
        ? null
        : int.tryParse(_slaController.text.trim());

    try {
      if (widget.priority == null) {
        await repo.createPriority(
          name: _nameController.text,
          level: level,
          slaHours: sla,
        );
      } else {
        await repo.updatePriority(
          id: widget.priority!.id,
          name: _nameController.text,
          level: level,
          slaHours: sla,
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
            controller: _levelController,
            decoration: const InputDecoration(
              labelText: 'Nível (1 a 5, menor = mais urgente) *',
            ),
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              if (n == null || n < 1 || n > 5) return 'Informe de 1 a 5';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _slaController,
            decoration: const InputDecoration(labelText: 'SLA (horas, opcional)'),
            keyboardType: TextInputType.number,
          ),
          if (widget.priority != null) ...[
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
