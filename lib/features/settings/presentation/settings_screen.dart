import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/validators.dart';
import '../../communications/application/communication_notifier.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../../shared/providers/tenant_provider.dart';
import '../../professionals/application/service_professional_list_notifier.dart';
import '../../professionals/domain/service_professional.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/data/member_management_repository.dart';
import '../../settings/data/tenant_unit_repository.dart';
import '../domain/schedule_models.dart';
import '../domain/tenant_billing_event.dart';
import '../domain/tenant_invitation.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_role_option.dart';
import '../domain/tenant_unit.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.read(supabaseClientProvider)),
);

final tenantUnitRepositoryProvider = Provider<TenantUnitRepository>(
  (ref) => TenantUnitRepository(ref.read(supabaseClientProvider)),
);

final companySettingsProvider =
    FutureProvider.autoDispose<CompanyScheduleSettings>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) {
    throw StateError('Nenhuma empresa ativa encontrada.');
  }
  return ref.read(settingsRepositoryProvider).loadCompanySettings(tenantId);
});

final tenantBillingEventsProvider =
    FutureProvider.autoDispose<List<TenantBillingEvent>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) {
    throw StateError('Nenhuma empresa ativa encontrada.');
  }
  return ref.read(settingsRepositoryProvider).listBillingEvents(tenantId);
});

final tenantUnitsProvider =
    FutureProvider.autoDispose<List<TenantUnit>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) {
    throw StateError('Nenhuma empresa ativa encontrada.');
  }
  return ref.read(tenantUnitRepositoryProvider).list(tenantId);
});

final memberManagementRepositoryProvider = Provider<MemberManagementRepository>(
  (ref) => MemberManagementRepository(ref.read(supabaseClientProvider)),
);

final tenantMembersProvider =
    FutureProvider.autoDispose<List<TenantMember>>((ref) async {
  return ref.read(memberManagementRepositoryProvider).listMembers();
});

final tenantInvitationsProvider =
    FutureProvider.autoDispose<List<TenantInvitation>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) {
    throw StateError('Nenhuma empresa ativa encontrada.');
  }
  return ref.read(memberManagementRepositoryProvider).listInvitations(tenantId);
});

final tenantRoleOptionsProvider =
    FutureProvider.autoDispose<List<TenantRoleOption>>((ref) async {
  return ref.read(memberManagementRepositoryProvider).listRoles();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(currentTenantProvider);
    final roleKey = ref.watch(currentRoleKeyProvider);
    final settingsAsync = ref.watch(companySettingsProvider);
    final unitsAsync = ref.watch(tenantUnitsProvider);
    final membersAsync = ref.watch(tenantMembersProvider);
    final invitationsAsync = ref.watch(tenantInvitationsProvider);
    final professionalsState = ref.watch(serviceProfessionalListProvider);
    final canManagePlan = {
      'tenant_owner',
      'tenant_admin',
      'platform_admin',
    }.contains(roleKey);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: () {
              ref.invalidate(companySettingsProvider);
              ref.invalidate(tenantMembersProvider);
              ref.invalidate(tenantInvitationsProvider);
              ref.invalidate(tenantRoleOptionsProvider);
              ref.invalidate(tenantUnitsProvider);
              ref.read(serviceProfessionalListProvider.notifier).load();
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          AppFormSection(
            title: tenant?['name'] as String? ?? 'Empresa',
            icon: Icons.settings_outlined,
            child: const Text(
              'Defina dias e horários de atendimento da empresa, bloqueios de agenda e a disponibilidade operacional de cada profissional.',
            ),
          ),
          const SizedBox(height: 16),
          // Fica fora do settingsAsync.when de propósito: não depende das
          // configurações da empresa e some da tela se aquele provider falhar.
          AppFormSection(
            title: 'Chamados',
            icon: Icons.confirmation_number_outlined,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.label_outline),
                  title: const Text('Categorias'),
                  subtitle: const Text(
                    'Categorias usadas na abertura de chamados.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.serviceCategories),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Prioridades'),
                  subtitle: const Text(
                    'Níveis de prioridade e SLA de atendimento.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.servicePriorities),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          settingsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(companySettingsProvider),
            ),
            data: (settings) => Column(
              children: [
                _SettingsCard(
                  title: 'Membros e acesso',
                  icon: Icons.admin_panel_settings_outlined,
                  actionLabel: canManagePlan ? 'Convidar usuário' : 'Atualizar',
                  onTap: () {
                    if (!canManagePlan) {
                      ref.invalidate(tenantMembersProvider);
                      ref.invalidate(tenantInvitationsProvider);
                      return;
                    }
                    showAppFormDialog<void>(
                      context: context,
                      title: 'Convidar usuário',
                      maxWidth: 900,
                      child: _InviteMemberDialog(
                        onSaved: () {
                          ref.invalidate(tenantInvitationsProvider);
                        },
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      membersAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (error, _) => ErrorView(
                          message: error.toString(),
                          onRetry: () => ref.invalidate(tenantMembersProvider),
                        ),
                        data: (members) => Column(
                          children: members
                              .map(
                                (member) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    member.isActive
                                        ? Icons.verified_user_outlined
                                        : Icons.person_off_outlined,
                                  ),
                                  title: Text(member.fullName),
                                  subtitle: Text(
                                    [
                                      if (member.email.isNotEmpty) member.email,
                                      member.roleName,
                                      member.isActive ? 'Ativo' : 'Suspenso',
                                    ].join(' · '),
                                  ),
                                  trailing: canManagePlan && !member.isOwner
                                      ? OutlinedButton(
                                          onPressed: () async {
                                            final nextStatus = member.isActive
                                                ? 'suspended'
                                                : 'active';
                                            try {
                                              await ref
                                                  .read(
                                                    memberManagementRepositoryProvider,
                                                  )
                                                  .setMembershipStatus(
                                                    membershipId: member.id,
                                                    status: nextStatus,
                                                  );
                                              ref.invalidate(
                                                tenantMembersProvider,
                                              );
                                              ref.invalidate(
                                                activeTenantMemberCountProvider,
                                              );
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(e.toString()),
                                                ),
                                              );
                                            }
                                          },
                                          child: Text(
                                            member.isActive
                                                ? 'Suspender'
                                                : 'Reativar',
                                          ),
                                        )
                                      : null,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Convites pendentes',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      invitationsAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (error, _) => ErrorView(
                          message: error.toString(),
                          onRetry: () =>
                              ref.invalidate(tenantInvitationsProvider),
                        ),
                        data: (invites) => invites.isEmpty
                            ? const Align(
                                alignment: Alignment.centerLeft,
                                child: Text('Nenhum convite pendente.'),
                              )
                            : Column(
                                children: invites
                                    .map(
                                      (invite) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                          Icons.mark_email_unread_outlined,
                                        ),
                                        title: Text(invite.email),
                                        subtitle: Text(
                                          '${invite.roleName} · expira em ${DateFormat('dd/MM/yyyy', 'pt_BR').format(invite.expiresAt)}',
                                        ),
                                        trailing: canManagePlan
                                            ? Wrap(
                                                spacing: 8,
                                                children: [
                                                  OutlinedButton(
                                                    onPressed: () async {
                                                      try {
                                                        await ref
                                                            .read(
                                                              memberManagementRepositoryProvider,
                                                            )
                                                            .revokeInvitation(
                                                              invite.id,
                                                            );
                                                        ref.invalidate(
                                                          tenantInvitationsProvider,
                                                        );
                                                      } catch (e) {
                                                        if (!context.mounted) {
                                                          return;
                                                        }
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              e.toString(),
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                    child:
                                                        const Text('Revogar'),
                                                  ),
                                                ],
                                              )
                                            : null,
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsCard(
                  title: 'Atendimento da empresa',
                  icon: Icons.calendar_month_outlined,
                  actionLabel: 'Editar horários',
                  onTap: () => showAppFormDialog<void>(
                    context: context,
                    title: 'Horários da empresa',
                    maxWidth: 1160,
                    child: _CompanyScheduleDialog(
                      initialSchedule: settings.weeklySchedule,
                      initialClosures: settings.closures,
                    ),
                  ),
                  child: _WeeklyScheduleSummary(
                    weeklySchedule: settings.weeklySchedule,
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsCard(
                  title: 'Fechamentos e licenças',
                  icon: Icons.event_busy_outlined,
                  actionLabel: 'Gerenciar datas',
                  onTap: () => showAppFormDialog<void>(
                    context: context,
                    title: 'Fechamentos da agenda',
                    maxWidth: 1160,
                    child: _CompanyScheduleDialog(
                      initialSchedule: settings.weeklySchedule,
                      initialClosures: settings.closures,
                      initialTab: 1,
                    ),
                  ),
                  child: settings.closures.isEmpty
                      ? const Text('Nenhum fechamento cadastrado.')
                      : Column(
                          children: settings.closures
                              .take(6)
                              .map(
                                (closure) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.block_outlined,
                                    size: 18,
                                  ),
                                  title: Text(
                                    DateFormat('dd/MM/yyyy', 'pt_BR')
                                        .format(closure.date),
                                  ),
                                  subtitle: Text(closure.reason),
                                ),
                              )
                              .toList(),
                        ),
                ),
                const SizedBox(height: 16),
                _SettingsCard(
                  title: 'Unidades e filiais',
                  icon: Icons.apartment_outlined,
                  actionLabel: canManagePlan ? 'Nova unidade' : 'Ver unidades',
                  onTap: () {
                    if (!canManagePlan) return;
                    showAppFormDialog<void>(
                      context: context,
                      title: 'Nova unidade',
                      maxWidth: 920,
                      child: _TenantUnitDialog(
                        onSaved: () {
                          ref.invalidate(tenantUnitsProvider);
                          ref.invalidate(activeTenantUnitCountProvider);
                        },
                      ),
                    );
                  },
                  child: unitsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => ErrorView(
                      message: error.toString(),
                      onRetry: () => ref.invalidate(tenantUnitsProvider),
                    ),
                    data: (units) => Column(
                      children: [
                        if (units.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Nenhuma unidade cadastrada.'),
                          )
                        else
                          ...units.map(
                            (unit) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                unit.isPrimary
                                    ? Icons.location_city_outlined
                                    : Icons.apartment_outlined,
                              ),
                              title: Text(unit.name),
                              subtitle: Text(
                                [
                                  if ((unit.city ?? '').trim().isNotEmpty)
                                    unit.city!.trim(),
                                  if ((unit.state ?? '').trim().isNotEmpty)
                                    unit.state!.trim(),
                                  if (unit.isPrimary) 'Principal',
                                  if (!unit.isActive) 'Inativa',
                                ].join(' · '),
                              ),
                              trailing: canManagePlan
                                  ? OutlinedButton(
                                      onPressed: () => showAppFormDialog<void>(
                                        context: context,
                                        title: 'Editar unidade',
                                        maxWidth: 920,
                                        child: _TenantUnitDialog(
                                          unit: unit,
                                          onSaved: () {
                                            ref.invalidate(tenantUnitsProvider);
                                            ref.invalidate(
                                              activeTenantUnitCountProvider,
                                            );
                                          },
                                        ),
                                      ),
                                      child: const Text('Editar'),
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsCard(
                  title: 'Disponibilidade dos profissionais',
                  icon: Icons.groups_2_outlined,
                  actionLabel: 'Atualizar lista',
                  onTap: () =>
                      ref.read(serviceProfessionalListProvider.notifier).load(),
                  child: professionalsState.isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : professionalsState.error != null
                          ? ErrorView(
                              message: professionalsState.error!.userMessage,
                              onRetry: () => ref
                                  .read(
                                      serviceProfessionalListProvider.notifier)
                                  .load(),
                            )
                          : Column(
                              children: professionalsState.items
                                  .map(
                                    (professional) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(professional.name),
                                      subtitle: Text(
                                        '${professional.category} · ${_availabilitySummary(professional.weeklyAvailability)}',
                                      ),
                                      trailing: OutlinedButton(
                                        onPressed: () =>
                                            showAppFormDialog<void>(
                                          context: context,
                                          title:
                                              'Disponibilidade de ${professional.name}',
                                          maxWidth: 1080,
                                          child:
                                              _ProfessionalAvailabilityDialog(
                                            professional: professional,
                                          ),
                                        ),
                                        child: const Text('Editar horários'),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                ),
                // Templates de mensagem (visível para quem tem acesso à escrita de clientes)
                const SizedBox(height: 16),
                AppFormSection(
                  title: 'Templates de mensagem',
                  icon: Icons.chat_bubble_outline,
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.message_outlined),
                        title: const Text('Gerenciar templates'),
                        subtitle: const Text(
                          'Crie modelos reutilizáveis para WhatsApp, e-mail e outros canais.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(AppRoutes.messageTemplates),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.auto_fix_high_outlined),
                        title: const Text('Carregar templates padrão'),
                        subtitle: const Text('Insere os modelos iniciais (apenas se não houver nenhum).'),
                        onTap: () async {
                          await ref
                              .read(communicationRepositoryProvider)
                              .seedDefaultTemplates();
                          ref.invalidate(messageTemplatesProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Templates padrão carregados.')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                if ({
                  'tenant_owner',
                  'tenant_admin',
                  'platform_admin',
                }.contains(roleKey)) ...[
                  const SizedBox(height: 16),
                  AppFormSection(
                    title: 'Trilha de auditoria',
                    icon: Icons.history_outlined,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Ver eventos de auditoria'),
                      subtitle: const Text(
                        'Registro imutável de ações sensíveis realizadas no sistema.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.auditLog),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TenantUnitDialog extends ConsumerStatefulWidget {
  const _TenantUnitDialog({
    this.unit,
    required this.onSaved,
  });

  final TenantUnit? unit;
  final VoidCallback onSaved;

  @override
  ConsumerState<_TenantUnitDialog> createState() => _TenantUnitDialogState();
}

class _TenantUnitDialogState extends ConsumerState<_TenantUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  bool _isPrimary = false;
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final unit = widget.unit;
    _nameController = TextEditingController(text: unit?.name ?? '');
    _cityController = TextEditingController(text: unit?.city ?? '');
    _stateController = TextEditingController(text: unit?.state ?? '');
    _isPrimary = unit?.isPrimary ?? false;
    _isActive = unit?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Dados da unidade',
              icon: Icons.apartment_outlined,
              child: Column(
                children: [
                  AppFormGrid(
                    minFieldWidth: 220,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nome da unidade',
                        ),
                        validator: (value) =>
                            validateRequired(value, 'Nome da unidade'),
                      ),
                      TextFormField(
                        controller: _cityController,
                        decoration: const InputDecoration(labelText: 'Cidade'),
                      ),
                      TextFormField(
                        controller: _stateController,
                        decoration: const InputDecoration(labelText: 'UF'),
                        maxLength: 2,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _isPrimary,
                          title: const Text('Unidade principal'),
                          onChanged: (value) =>
                              setState(() => _isPrimary = value),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _isActive,
                          title: const Text('Unidade ativa'),
                          onChanged: (value) =>
                              setState(() => _isActive = value),
                        ),
                      ),
                    ],
                  ),
                ],
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
                widget.unit == null ? 'Criar unidade' : 'Salvar unidade',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null || tenantId.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(tenantUnitRepositoryProvider);
      final unit = TenantUnit(
        id: widget.unit?.id ?? '',
        tenantId: tenantId,
        name: _nameController.text.trim(),
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        state: _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim().toUpperCase(),
        isPrimary: _isPrimary,
        isActive: _isActive,
      );

      if (widget.unit == null) {
        await repository.create(tenantId: tenantId, unit: unit);
      } else {
        await repository.update(unit);
      }

      widget.onSaved();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _InviteMemberDialog extends ConsumerStatefulWidget {
  const _InviteMemberDialog({
    required this.onSaved,
  });

  final VoidCallback onSaved;

  @override
  ConsumerState<_InviteMemberDialog> createState() =>
      _InviteMemberDialogState();
}

class _InviteMemberDialogState extends ConsumerState<_InviteMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _roleKey;
  bool _isSaving = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(tenantRoleOptionsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Novo convite',
              icon: Icons.person_add_alt_1_outlined,
              child: rolesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => ErrorView(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(tenantRoleOptionsProvider),
                ),
                data: (roles) {
                  _roleKey ??= roles.any((role) => role.key == 'technician')
                      ? 'technician'
                      : (roles.isNotEmpty ? roles.first.key : null);
                  return AppFormGrid(
                    minFieldWidth: 220,
                    children: [
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        validator: validateEmail,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _roleKey,
                        decoration: const InputDecoration(labelText: 'Papel'),
                        items: roles
                            .map(
                              (role) => DropdownMenuItem(
                                value: role.key,
                                child: Text(role.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _roleKey = value),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Gerar convite'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _roleKey == null) return;

    setState(() => _isSaving = true);
    try {
      final result =
          await ref.read(memberManagementRepositoryProvider).createInvitation(
                email: _emailController.text.trim(),
                roleKey: _roleKey!,
              );
      final tenant = ref.read(currentTenantProvider);
      const baseUrl =
          'https://cliente.leonardoperescouto.com/#/aceitar-convite';
      final inviteLink =
          '$baseUrl?invite=${result.token}&tenant=${tenant?['slug'] ?? ''}';

      await Clipboard.setData(ClipboardData(text: inviteLink));
      widget.onSaved();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Convite gerado'),
          content: Text(
            'O link foi copiado para a área de transferência.\n\nExpira em ${DateFormat('dd/MM/yyyy', 'pt_BR').format(result.expiresAt)}.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Ok'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFormSection(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyScheduleSummary extends StatelessWidget {
  const _WeeklyScheduleSummary({required this.weeklySchedule});

  final Map<String, DaySchedule> weeklySchedule;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: kWeekdayOrder.map((weekday) {
        final day = weeklySchedule[weekday] ?? defaultDaySchedule();
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            day.enabled ? Icons.check_circle_outline : Icons.block_outlined,
            size: 18,
          ),
          title: Text(kWeekdayLabels[weekday] ?? weekday),
          subtitle: Text(_formatDaySchedule(day)),
        );
      }).toList(),
    );
  }
}

class _CompanyScheduleDialog extends ConsumerStatefulWidget {
  const _CompanyScheduleDialog({
    required this.initialSchedule,
    required this.initialClosures,
    this.initialTab = 0,
  });

  final Map<String, DaySchedule> initialSchedule;
  final List<AgendaClosure> initialClosures;
  final int initialTab;

  @override
  ConsumerState<_CompanyScheduleDialog> createState() =>
      _CompanyScheduleDialogState();
}

class _CompanyScheduleDialogState
    extends ConsumerState<_CompanyScheduleDialog> {
  late Map<String, DaySchedule> _schedule;
  late List<AgendaClosure> _closures;
  int _tab = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _schedule = {
      for (final entry in widget.initialSchedule.entries)
        entry.key: entry.value,
    };
    _closures = [...widget.initialClosures];
    _tab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Horários'),
                icon: Icon(Icons.schedule_outlined),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Fechamentos'),
                icon: Icon(Icons.event_busy_outlined),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (value) => setState(() => _tab = value.first),
          ),
          const SizedBox(height: 18),
          if (_tab == 0)
            _WeeklyScheduleEditor(
              schedule: _schedule,
              onChanged: (day, schedule) =>
                  setState(() => _schedule[day] = schedule),
            )
          else
            _ClosureEditor(
              closures: _closures,
              onChanged: (closures) => setState(() => _closures = closures),
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
            label: const Text('Salvar configurações'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final tenantId = ref.read(currentTenantIdProvider);
    if (tenantId == null || tenantId.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(settingsRepositoryProvider).saveCompanySettings(
            tenantId: tenantId,
            weeklySchedule: _schedule,
            closures: _closures,
          );
      ref.invalidate(companySettingsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _ProfessionalAvailabilityDialog extends ConsumerStatefulWidget {
  const _ProfessionalAvailabilityDialog({required this.professional});

  final ServiceProfessional professional;

  @override
  ConsumerState<_ProfessionalAvailabilityDialog> createState() =>
      _ProfessionalAvailabilityDialogState();
}

class _ProfessionalAvailabilityDialogState
    extends ConsumerState<_ProfessionalAvailabilityDialog> {
  late Map<String, DaySchedule> _schedule;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _schedule = {
      for (final entry in widget.professional.weeklyAvailability.entries)
        entry.key: entry.value,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WeeklyScheduleEditor(
            schedule: _schedule,
            onChanged: (day, schedule) =>
                setState(() => _schedule[day] = schedule),
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
            label: const Text('Salvar disponibilidade'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(serviceProfessionalRepositoryProvider).update(
            widget.professional.copyWithAvailability(_schedule),
          );
      ref.read(serviceProfessionalListProvider.notifier).load();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _WeeklyScheduleEditor extends StatelessWidget {
  const _WeeklyScheduleEditor({
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
          padding: const EdgeInsets.only(bottom: 12),
          child: NeomorphicPanel(
            borderRadius: 24,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        kWeekdayLabels[weekday] ?? weekday,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
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
                const SizedBox(height: 8),
                AppFormGrid(
                  minFieldWidth: 190,
                  children: [
                    _PeriodEditor(
                      label: 'Manhã',
                      period: day.morning,
                      enabled: day.enabled,
                      onChanged: (period) =>
                          onChanged(weekday, day.copyWith(morning: period)),
                    ),
                    _PeriodEditor(
                      label: 'Tarde',
                      period: day.afternoon,
                      enabled: day.enabled,
                      onChanged: (period) =>
                          onChanged(weekday, day.copyWith(afternoon: period)),
                    ),
                    _PeriodEditor(
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

class _PeriodEditor extends StatelessWidget {
  const _PeriodEditor({
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

class _ClosureEditor extends StatelessWidget {
  const _ClosureEditor({
    required this.closures,
    required this.onChanged,
  });

  final List<AgendaClosure> closures;
  final ValueChanged<List<AgendaClosure>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () async {
              final result = await _pickClosure(context);
              if (result != null) {
                onChanged([...closures, result]
                  ..sort((a, b) => a.date.compareTo(b.date)));
              }
            },
            icon: const Icon(Icons.add_outlined),
            label: const Text('Adicionar fechamento'),
          ),
        ),
        const SizedBox(height: 12),
        if (closures.isEmpty)
          const Text('Nenhuma data de fechamento cadastrada.')
        else
          ...closures.asMap().entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_busy_outlined),
                  title: Text(
                    DateFormat('dd/MM/yyyy', 'pt_BR').format(entry.value.date),
                  ),
                  subtitle: Text(entry.value.reason),
                  trailing: IconButton(
                    onPressed: () {
                      final next = [...closures]..removeAt(entry.key);
                      onChanged(next);
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
      ],
    );
  }

  Future<AgendaClosure?> _pickClosure(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (date == null || !context.mounted) return null;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motivo do fechamento'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Feriado, licença, manutenção...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    final reason = (result ?? '').trim();
    if (reason.isEmpty) return null;
    return AgendaClosure(date: date, reason: reason);
  }
}

String _formatDaySchedule(DaySchedule schedule) {
  if (!schedule.enabled) return 'Fechado';
  final parts = <String>[];
  if (schedule.morning.enabled &&
      schedule.morning.start != null &&
      schedule.morning.end != null) {
    parts.add('Manhã ${schedule.morning.start}-${schedule.morning.end}');
  }
  if (schedule.afternoon.enabled &&
      schedule.afternoon.start != null &&
      schedule.afternoon.end != null) {
    parts.add('Tarde ${schedule.afternoon.start}-${schedule.afternoon.end}');
  }
  if (schedule.night.enabled &&
      schedule.night.start != null &&
      schedule.night.end != null) {
    parts.add('Noite ${schedule.night.start}-${schedule.night.end}');
  }
  return parts.isEmpty ? 'Sem horários definidos' : parts.join(' · ');
}

String _availabilitySummary(Map<String, DaySchedule> schedule) {
  final activeDays =
      schedule.entries.where((entry) => entry.value.enabled).length;
  return activeDays == 0 ? 'sem disponibilidade' : '$activeDays dias ativos';
}

String _billingStatusLabel(String status) {
  switch (status) {
    case 'trialing':
      return 'Trial ativo';
    case 'past_due':
      return 'Pagamento pendente';
    case 'canceled':
      return 'Assinatura cancelada';
    case 'active':
    default:
      return 'Assinatura ativa';
  }
}
