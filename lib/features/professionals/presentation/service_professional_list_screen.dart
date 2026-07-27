import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../shared/providers/tenant_provider.dart';
import '../../settings/domain/schedule_models.dart';
import '../application/service_professional_list_notifier.dart';
import '../domain/professional_categories.dart';
import '../domain/service_professional.dart';

class ServiceProfessionalListScreen extends ConsumerStatefulWidget {
  const ServiceProfessionalListScreen({super.key});

  @override
  ConsumerState<ServiceProfessionalListScreen> createState() =>
      _ServiceProfessionalListScreenState();
}

class _ServiceProfessionalListScreenState
    extends ConsumerState<ServiceProfessionalListScreen> {
  final _searchController = TextEditingController();
  String _kindFilter = 'Todos';
  String _statusFilter = 'Ativos';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(serviceProfessionalListProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openForm({ServiceProfessional? professional}) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: professional == null ? 'Novo profissional' : 'Editar profissional',
      maxWidth: 920,
      child: _ServiceProfessionalForm(professional: professional),
    );
    if (saved == true && mounted) {
      ref.read(serviceProfessionalListProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serviceProfessionalListProvider);
    final filtered = state.items.where((professional) {
      final search = _searchController.text.trim().toLowerCase();
      final matchesSearch = search.isEmpty ||
          professional.name.toLowerCase().contains(search) ||
          professional.category.toLowerCase().contains(search) ||
          (professional.phone ?? '').contains(search) ||
          (professional.email ?? '').toLowerCase().contains(search);
      final matchesKind =
          _kindFilter == 'Todos' || professional.kindLabel == _kindFilter;
      final matchesStatus = _statusFilter == 'Todos' ||
          (_statusFilter == 'Ativos'
              ? professional.isActive
              : !professional.isActive);
      return matchesSearch && matchesKind && matchesStatus;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profissionais'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: () =>
                ref.read(serviceProfessionalListProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Novo profissional'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(serviceProfessionalListProvider.notifier).load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            AppFormSection(
              title: 'Equipe e parceiros',
              icon: Icons.groups_2_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormGrid(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'Buscar profissional',
                          hintText: 'Nome, categoria, telefone ou e-mail',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _kindFilter,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                        ),
                        items: const ['Todos', 'Interno', 'Parceiro']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _kindFilter = value ?? 'Todos'),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                        ),
                        items: const ['Ativos', 'Inativos', 'Todos']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _statusFilter = value ?? 'Ativos'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricBadge(
                        label: 'Total',
                        value: '${state.items.length}',
                      ),
                      _MetricBadge(
                        label: 'Internos',
                        value:
                            '${state.items.where((item) => item.isInternal).length}',
                      ),
                      _MetricBadge(
                        label: 'Parceiros',
                        value:
                            '${state.items.where((item) => !item.isInternal).length}',
                      ),
                      _MetricBadge(
                        label: 'Agendáveis',
                        value:
                            '${state.items.where((item) => item.linkedUserId != null && item.isActive).length}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ErrorView(
                  message: state.error!.userMessage,
                  onRetry: () =>
                      ref.read(serviceProfessionalListProvider.notifier).load(),
                ),
              ),
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const NeomorphicPanel(
                borderRadius: 28,
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Nenhum profissional encontrado com os filtros atuais.',
                  ),
                ),
              )
            else
              ...filtered.map(
                (professional) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProfessionalCard(
                    professional: professional,
                    onEdit: () => _openForm(professional: professional),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _ProfessionalCard extends StatelessWidget {
  const _ProfessionalCard({
    required this.professional,
    required this.onEdit,
  });

  final ServiceProfessional professional;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return NeomorphicPanel(
      borderRadius: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  professional.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Editar profissional',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(
                icon: professional.isInternal
                    ? Icons.badge_outlined
                    : Icons.handshake_outlined,
                label: professional.kindLabel,
              ),
              _InfoChip(
                icon: Icons.category_outlined,
                label: professional.category,
              ),
              _InfoChip(
                icon: professional.isActive
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline,
                label: professional.isActive ? 'Ativo' : 'Inativo',
              ),
              if (professional.linkedUserId != null)
                const _InfoChip(
                  icon: Icons.event_available_outlined,
                  label: 'Disponível na agenda',
                ),
            ],
          ),
          const SizedBox(height: 12),
          AppFormGrid(
            minFieldWidth: 240,
            children: [
              _InfoLine(
                label: 'Telefone',
                value: professional.phone ?? 'Não informado',
              ),
              _InfoLine(
                label: 'E-mail',
                value: professional.email ?? 'Não informado',
              ),
              _InfoLine(
                label: 'Valor da hora',
                value: _formatMoney(professional.hourlyRateCents),
              ),
              _InfoLine(
                label: 'Transporte',
                value: _formatMoney(professional.transportCostCents),
              ),
              _InfoLine(
                label: 'Refeição',
                value: _formatMoney(professional.mealCostCents),
              ),
              _InfoLine(
                label: 'Deslocamento',
                value: _formatMoney(professional.travelCostCents),
              ),
              _InfoLine(
                label: 'Hospedagem',
                value: _formatMoney(professional.lodgingCostCents),
              ),
              _InfoLine(
                label: 'Outros custos',
                value: _formatMoney(professional.otherCostCents),
              ),
            ],
          ),
          if ((professional.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoLine(
              label: 'Observações',
              value: professional.notes!,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }
}

class _ServiceProfessionalForm extends ConsumerStatefulWidget {
  const _ServiceProfessionalForm({this.professional});

  final ServiceProfessional? professional;

  @override
  ConsumerState<_ServiceProfessionalForm> createState() =>
      _ServiceProfessionalFormState();
}

class _ServiceProfessionalFormState
    extends ConsumerState<_ServiceProfessionalForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;
  late final TextEditingController _hourlyRateController;
  late final TextEditingController _transportCostController;
  late final TextEditingController _mealCostController;
  late final TextEditingController _travelCostController;
  late final TextEditingController _lodgingCostController;
  late final TextEditingController _otherCostController;
  late String _kind;
  late String _category;
  late bool _isActive;
  late Map<String, DaySchedule> _availability;
  String? _linkedUserId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final professional = widget.professional;
    _nameController = TextEditingController(text: professional?.name ?? '');
    _category = professional != null && professional.category.trim().isNotEmpty
        ? professional.category
        : professionalCategories.first;
    _emailController = TextEditingController(text: professional?.email ?? '');
    _phoneController = TextEditingController(text: professional?.phone ?? '');
    _notesController = TextEditingController(text: professional?.notes ?? '');
    _hourlyRateController = TextEditingController(
      text: _moneyInputValue(professional?.hourlyRateCents ?? 0),
    );
    _transportCostController = TextEditingController(
      text: _moneyInputValue(professional?.transportCostCents ?? 0),
    );
    _mealCostController = TextEditingController(
      text: _moneyInputValue(professional?.mealCostCents ?? 0),
    );
    _travelCostController = TextEditingController(
      text: _moneyInputValue(professional?.travelCostCents ?? 0),
    );
    _lodgingCostController = TextEditingController(
      text: _moneyInputValue(professional?.lodgingCostCents ?? 0),
    );
    _otherCostController = TextEditingController(
      text: _moneyInputValue(professional?.otherCostCents ?? 0),
    );
    _kind = professional?.kind ?? 'partner';
    _isActive = professional?.isActive ?? true;
    _linkedUserId = professional?.linkedUserId;
    _availability = {
      for (final entry
          in (professional?.weeklyAvailability ?? defaultWeeklySchedule())
              .entries)
        entry.key: entry.value,
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _hourlyRateController.dispose();
    _transportCostController.dispose();
    _mealCostController.dispose();
    _travelCostController.dispose();
    _lodgingCostController.dispose();
    _otherCostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final internalUsersAsync =
        ref.watch(serviceProfessionalInternalUsersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Dados do profissional',
              icon: Icons.person_outline,
              child: Column(
                children: [
                  AppFormGrid(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _kind,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'internal',
                            child: Text('Interno'),
                          ),
                          DropdownMenuItem(
                            value: 'partner',
                            child: Text('Parceiro'),
                          ),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() {
                                  _kind = value ?? 'partner';
                                  if (_kind != 'internal') {
                                    _linkedUserId = null;
                                  }
                                }),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Categoria / especialidade *',
                        ),
                        items: [
                          ...professionalCategories,
                          if (!professionalCategories.contains(_category))
                            _category,
                        ]
                            .map(
                              (category) => DropdownMenuItem(
                                value: category,
                                child: Text(
                                  category,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(
                                  () => _category =
                                      value ?? professionalCategories.first,
                                ),
                        validator: (value) =>
                            value == null || value.trim().length < 2
                                ? 'Informe a categoria.'
                                : null,
                      ),
                      TextFormField(
                        controller: _nameController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                          labelText: 'Nome do profissional *',
                        ),
                        validator: (value) =>
                            value == null || value.trim().length < 3
                                ? 'Informe o nome.'
                                : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _isActive,
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() => _isActive = value),
                        title: const Text('Profissional ativo'),
                      ),
                    ],
                  ),
                  if (_kind == 'internal') ...[
                    const SizedBox(height: 12),
                    internalUsersAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String?>(
                            initialValue: _linkedUserId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Vincular ao usuário interno',
                              helperText:
                                  'Opcional. Se a lista não carregar, você ainda pode salvar o profissional sem vínculo.',
                            ),
                            items: const [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Sem vínculo'),
                              ),
                            ],
                            onChanged: null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Não foi possível carregar os usuários internos agora. O cadastro do profissional continua liberado.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                      data: (users) {
                        final hasUsers = users.isNotEmpty;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String?>(
                              initialValue: _linkedUserId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Vincular ao usuário interno',
                                helperText: hasUsers
                                    ? 'Opcional. Use este vínculo quando o profissional também acessar o sistema.'
                                    : 'Opcional. Ainda não há usuários internos do tipo técnico para vincular.',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Sem vínculo'),
                                ),
                                ...users.map(
                                  (user) => DropdownMenuItem<String?>(
                                    value: user.userId,
                                    child: Text(
                                      '${user.name}${user.phone != null ? ' · ${user.phone}' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: _isSaving || !hasUsers
                                  ? null
                                  : (value) =>
                                      setState(() => _linkedUserId = value),
                            ),
                            if (!hasUsers) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Você pode cadastrar o profissional agora e fazer o vínculo depois, quando existir um usuário interno técnico ativo nesta empresa.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
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
                    controller: _phoneController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                    ),
                  ),
                  TextFormField(
                    controller: _emailController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFormSection(
              title: 'Custos e valores',
              icon: Icons.payments_outlined,
              child: AppFormGrid(
                children: [
                  TextFormField(
                    controller: _hourlyRateController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor da hora',
                    ),
                    validator: (value) => _moneyToCents(value ?? '') < 0
                        ? 'Informe um valor válido.'
                        : null,
                  ),
                  TextFormField(
                    controller: _transportCostController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Transporte',
                    ),
                  ),
                  TextFormField(
                    controller: _mealCostController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Refeição',
                    ),
                  ),
                  TextFormField(
                    controller: _travelCostController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Deslocamento',
                    ),
                  ),
                  TextFormField(
                    controller: _lodgingCostController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Hospedagem',
                    ),
                  ),
                  TextFormField(
                    controller: _otherCostController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Outros custos',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFormSection(
              title: 'Disponibilidade',
              icon: Icons.schedule_outlined,
              child: _ProfessionalAvailabilityInlineEditor(
                schedule: _availability,
                onChanged: (day, schedule) =>
                    setState(() => _availability[day] = schedule),
              ),
            ),
            const SizedBox(height: 16),
            AppFormSection(
              title: 'Observações',
              icon: Icons.notes_outlined,
              child: TextFormField(
                controller: _notesController,
                enabled: !_isSaving,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Notas operacionais',
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                widget.professional == null
                    ? 'Salvar profissional'
                    : 'Salvar alterações',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final repo = ref.read(serviceProfessionalRepositoryProvider);
    final tenantId = ref.read(currentTenantIdProvider);
    try {
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError('Nenhuma empresa ativa encontrada para este usuário.');
      }
      final current = widget.professional;
      final professional = ServiceProfessional(
        id: current?.id ?? '',
        tenantId: current?.tenantId ?? tenantId,
        linkedUserId: _kind == 'internal' ? _linkedUserId : null,
        kind: _kind,
        category: _category,
        name: _nameController.text,
        hourlyRateCents: _moneyToCents(_hourlyRateController.text),
        transportCostCents: _moneyToCents(_transportCostController.text),
        mealCostCents: _moneyToCents(_mealCostController.text),
        travelCostCents: _moneyToCents(_travelCostController.text),
        lodgingCostCents: _moneyToCents(_lodgingCostController.text),
        otherCostCents: _moneyToCents(_otherCostController.text),
        weeklyAvailability: _availability,
        email: _emailController.text,
        phone: _phoneController.text,
        notes: _notesController.text,
        isActive: _isActive,
        createdAt: current?.createdAt ?? DateTime.now(),
        updatedAt: current?.updatedAt ?? DateTime.now(),
      );
      if (current == null) {
        await repo.create(professional);
      } else {
        await repo.update(professional);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _ProfessionalAvailabilityInlineEditor extends StatelessWidget {
  const _ProfessionalAvailabilityInlineEditor({
    required this.schedule,
    required this.onChanged,
  });

  final Map<String, DaySchedule> schedule;
  final void Function(String day, DaySchedule schedule) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: kWeekdayOrder.map((weekday) {
        final day = schedule[weekday] ?? defaultDaySchedule();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: NeomorphicInset(
            borderRadius: 20,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        kWeekdayLabels[weekday] ?? weekday,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Switch(
                      value: day.enabled,
                      onChanged: (value) => onChanged(
                        weekday,
                        day.copyWith(
                          enabled: value,
                          morning: day.morning.copyWith(enabled: value),
                          afternoon: day.afternoon.copyWith(enabled: value),
                        ),
                      ),
                    ),
                  ],
                ),
                AppFormGrid(
                  minFieldWidth: 180,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _AvailabilityPeriodField(
                      label: 'Manhã',
                      period: day.morning,
                      enabled: day.enabled,
                      onChanged: (period) =>
                          onChanged(weekday, day.copyWith(morning: period)),
                    ),
                    _AvailabilityPeriodField(
                      label: 'Tarde',
                      period: day.afternoon,
                      enabled: day.enabled,
                      onChanged: (period) =>
                          onChanged(weekday, day.copyWith(afternoon: period)),
                    ),
                    _AvailabilityPeriodField(
                      label: 'Noite',
                      period: day.night,
                      enabled: day.enabled,
                      onChanged: (period) =>
                          onChanged(weekday, day.copyWith(night: period)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AvailabilityPeriodField extends StatelessWidget {
  const _AvailabilityPeriodField({
    required this.label,
    required this.period,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final SchedulePeriod period;
  final bool enabled;
  final ValueChanged<SchedulePeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    const times = <String>[
      '06:00',
      '06:30',
      '07:00',
      '07:30',
      '08:00',
      '08:30',
      '09:00',
      '09:30',
      '10:00',
      '10:30',
      '11:00',
      '11:30',
      '12:00',
      '12:30',
      '13:00',
      '13:30',
      '14:00',
      '14:30',
      '15:00',
      '15:30',
      '16:00',
      '16:30',
      '17:00',
      '17:30',
      '18:00',
      '18:30',
      '19:00',
      '19:30',
      '20:00',
      '20:30',
      '21:00',
      '21:30',
      '22:00',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Checkbox(
              value: enabled && period.enabled,
              onChanged: !enabled
                  ? null
                  : (value) => onChanged(period.copyWith(enabled: value)),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: period.start,
          decoration: const InputDecoration(labelText: 'Início'),
          items: times
              .map((time) => DropdownMenuItem(value: time, child: Text(time)))
              .toList(),
          onChanged: !enabled || !period.enabled
              ? null
              : (value) => onChanged(period.copyWith(start: value)),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: period.end,
          decoration: const InputDecoration(labelText: 'Fim'),
          items: times
              .map((time) => DropdownMenuItem(value: time, child: Text(time)))
              .toList(),
          onChanged: !enabled || !period.enabled
              ? null
              : (value) => onChanged(period.copyWith(end: value)),
        ),
      ],
    );
  }
}

int _moneyToCents(String value) {
  final normalized = value
      .replaceAll(RegExp(r'[^0-9,.-]'), '')
      .replaceAll('.', '')
      .replaceAll(',', '.');
  final parsed = double.tryParse(normalized);
  if (parsed == null) return 0;
  return (parsed * 100).round();
}

String _moneyInputValue(int cents) {
  return (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
}

String _formatMoney(int cents) {
  final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
  return currency.format(cents / 100);
}
