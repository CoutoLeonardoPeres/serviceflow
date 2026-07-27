import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/plans/tenant_plan.dart';
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
import '../domain/tenant_billing_webhook_event.dart';
import '../domain/tenant_checkout_session.dart';
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

final tenantCheckoutSessionsProvider =
    FutureProvider.autoDispose<List<TenantCheckoutSession>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) {
    throw StateError('Nenhuma empresa ativa encontrada.');
  }
  return ref.read(settingsRepositoryProvider).listCheckoutSessions(tenantId);
});

final tenantBillingWebhookEventsProvider =
    FutureProvider.autoDispose<List<TenantBillingWebhookEvent>>((ref) async {
  final tenantId = ref.watch(currentTenantIdProvider);
  if (tenantId == null || tenantId.isEmpty) {
    throw StateError('Nenhuma empresa ativa encontrada.');
  }
  return ref
      .read(settingsRepositoryProvider)
      .listBillingWebhookEvents(tenantId);
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
    final planSnapshot = ref.watch(currentTenantPlanProvider);
    final activeUsersAsync = ref.watch(activeTenantMemberCountProvider);
    final activeUnitsAsync = ref.watch(activeTenantUnitCountProvider);
    final billingEventsAsync = ref.watch(tenantBillingEventsProvider);
    final checkoutSessionsAsync = ref.watch(tenantCheckoutSessionsProvider);
    final billingWebhookEventsAsync =
        ref.watch(tenantBillingWebhookEventsProvider);
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
              ref.invalidate(tenantBillingEventsProvider);
              ref.invalidate(tenantCheckoutSessionsProvider);
              ref.invalidate(tenantBillingWebhookEventsProvider);
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
          _PlanSettingsCard(
            snapshot: planSnapshot,
            activeUsersAsync: activeUsersAsync,
            activeUnitsAsync: activeUnitsAsync,
            billingEventsAsync: billingEventsAsync,
            checkoutSessionsAsync: checkoutSessionsAsync,
            billingWebhookEventsAsync: billingWebhookEventsAsync,
            canManage: canManagePlan,
            onPlanChanged: (planKey) async {
              final repository = ref.read(settingsRepositoryProvider);
              await repository.updateTenantPlan(planKey: planKey);
              ref.invalidate(activeMembershipProvider);
              ref.invalidate(activeTenantMemberCountProvider);
              ref.invalidate(activeTenantUnitCountProvider);
              ref.invalidate(tenantUnitsProvider);
              ref.invalidate(tenantBillingEventsProvider);
              ref.invalidate(tenantCheckoutSessionsProvider);
            },
            onBillingStatusChanged: (billingStatus, note, trialEndsAt) async {
              final repository = ref.read(settingsRepositoryProvider);
              await repository.updateBillingStatus(
                billingStatus: billingStatus,
                note: note,
                trialEndsAt: trialEndsAt,
              );
              ref.invalidate(activeMembershipProvider);
              ref.invalidate(tenantBillingEventsProvider);
              ref.invalidate(tenantCheckoutSessionsProvider);
            },
            onConfirmCheckout:
                (checkoutSessionId, note, providerReference) async {
              final repository = ref.read(settingsRepositoryProvider);
              await repository.confirmCheckoutSession(
                checkoutSessionId: checkoutSessionId,
                note: note,
                providerReference: providerReference,
              );
              ref.invalidate(activeMembershipProvider);
              ref.invalidate(tenantBillingEventsProvider);
              ref.invalidate(tenantCheckoutSessionsProvider);
            },
            onCloseCheckout: (checkoutSessionId, targetStatus, note) async {
              final repository = ref.read(settingsRepositoryProvider);
              await repository.closeCheckoutSession(
                checkoutSessionId: checkoutSessionId,
                targetStatus: targetStatus,
                note: note,
              );
              ref.invalidate(tenantBillingEventsProvider);
              ref.invalidate(tenantCheckoutSessionsProvider);
              ref.invalidate(tenantBillingWebhookEventsProvider);
            },
            onSimulateWebhook: (
              checkoutSessionId,
              providerReference,
              eventType,
            ) async {
              final repository = ref.read(settingsRepositoryProvider);
              await repository.registerBillingWebhookEvent(
                provider: 'external_checkout',
                eventType: eventType,
                checkoutSessionId: checkoutSessionId,
                providerReference: providerReference,
                payload: {
                  'source': 'settings_simulation',
                },
              );
              ref.invalidate(activeMembershipProvider);
              ref.invalidate(tenantBillingEventsProvider);
              ref.invalidate(tenantCheckoutSessionsProvider);
              ref.invalidate(tenantBillingWebhookEventsProvider);
            },
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
                const SizedBox(height: 16),
                AppFormSection(
                  title: 'Chamados',
                  icon: Icons.confirmation_number_outlined,
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.label_outline),
                        title: const Text('Categorias'),
                        subtitle: const Text('Categorias usadas na abertura de chamados.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(AppRoutes.serviceCategories),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.flag_outlined),
                        title: const Text('Prioridades'),
                        subtitle: const Text('Níveis de prioridade e SLA de atendimento.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(AppRoutes.servicePriorities),
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

class _PlanSettingsCard extends StatefulWidget {
  const _PlanSettingsCard({
    required this.snapshot,
    required this.activeUsersAsync,
    required this.activeUnitsAsync,
    required this.billingEventsAsync,
    required this.checkoutSessionsAsync,
    required this.billingWebhookEventsAsync,
    required this.canManage,
    required this.onPlanChanged,
    required this.onBillingStatusChanged,
    required this.onConfirmCheckout,
    required this.onCloseCheckout,
    required this.onSimulateWebhook,
  });

  final TenantPlanSnapshot snapshot;
  final AsyncValue<int> activeUsersAsync;
  final AsyncValue<int> activeUnitsAsync;
  final AsyncValue<List<TenantBillingEvent>> billingEventsAsync;
  final AsyncValue<List<TenantCheckoutSession>> checkoutSessionsAsync;
  final AsyncValue<List<TenantBillingWebhookEvent>> billingWebhookEventsAsync;
  final bool canManage;
  final Future<void> Function(String planKey) onPlanChanged;
  final Future<void> Function(
    String billingStatus,
    String? note,
    DateTime? trialEndsAt,
  ) onBillingStatusChanged;
  final Future<void> Function(
    String checkoutSessionId,
    String? note,
    String? providerReference,
  ) onConfirmCheckout;
  final Future<void> Function(
    String checkoutSessionId,
    String targetStatus,
    String? note,
  ) onCloseCheckout;
  final Future<void> Function(
    String checkoutSessionId,
    String? providerReference,
    String eventType,
  ) onSimulateWebhook;

  @override
  State<_PlanSettingsCard> createState() => _PlanSettingsCardState();
}

class _PlanSettingsCardState extends State<_PlanSettingsCard> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final trialEndsAt = widget.snapshot.trialEndsAt;
    final formatter = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 2,
    );

    return AppFormSection(
      title: 'Plano e assinatura',
      icon: Icons.workspace_premium_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PlanStatusChip(
                label: 'Plano atual: ${widget.snapshot.plan.label}',
                tone: _ChipTone.primary,
              ),
              const SizedBox(width: 10),
              _PlanStatusChip(
                label: _billingStatusLabel(widget.snapshot.billingStatus),
                tone: widget.snapshot.isTrialing
                    ? _ChipTone.warning
                    : _ChipTone.neutral,
              ),
              if (trialEndsAt != null) ...[
                const SizedBox(width: 10),
                _PlanStatusChip(
                  label:
                      'Trial até ${DateFormat('dd/MM/yyyy', 'pt_BR').format(trialEndsAt)}',
                  tone: _ChipTone.neutral,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PlanStatusChip(
                label: widget.activeUsersAsync.when(
                  data: (count) =>
                      'Usuários ativos: $count/${widget.snapshot.plan.userLimit}',
                  loading: () => 'Usuários ativos: carregando...',
                  error: (_, __) => 'Usuários ativos: indisponível',
                ),
                tone: _ChipTone.neutral,
              ),
              _PlanStatusChip(
                label: widget.activeUnitsAsync.when(
                  data: (count) =>
                      'Unidades ativas: $count/${widget.snapshot.plan.unitLimit}',
                  loading: () => 'Unidades ativas: carregando...',
                  error: (_, __) => 'Unidades ativas: indisponível',
                ),
                tone: _ChipTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 18),
          AppFormGrid(
            minFieldWidth: 250,
            children: tenantPlans.values
                .map(
                  (plan) => _PlanCard(
                    plan: plan,
                    priceLabel:
                        '${formatter.format(plan.monthlyPriceCents / 100)}/mês',
                    isCurrent: plan.key == widget.snapshot.plan.key,
                    canManage: widget.canManage,
                    isSaving: _isSaving,
                    onSelect: () => _changePlan(plan),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          Text(
            'Checkouts recentes',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          widget.checkoutSessionsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            data: (sessions) {
              if (sessions.isEmpty) {
                return Text(
                  'Ainda não há sessões de checkout registradas.',
                  style: Theme.of(context).textTheme.bodyMedium,
                );
              }
              return Column(
                children: sessions
                    .map(
                      (session) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          child: Icon(
                            _checkoutSessionIcon(session.status),
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          '${_planLabel(session.planKey)} · ${_checkoutSessionStatusLabel(session.status)}',
                        ),
                        subtitle: Text(
                          [
                            'Origem: ${session.source}',
                            DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                                .format(session.createdAt),
                            if ((session.providerReference ?? '')
                                .trim()
                                .isNotEmpty)
                              'Ref: ${session.providerReference!.trim()}',
                          ].join(' · '),
                        ),
                        trailing: widget.canManage &&
                                _canManageCheckoutSession(session.status)
                            ? PopupMenuButton<String>(
                                enabled: !_isSaving,
                                onSelected: (value) {
                                  switch (value) {
                                    case 'confirm':
                                      _openCheckoutConfirmationDialog(session);
                                      break;
                                    case 'cancel':
                                      _openCheckoutClosureDialog(
                                        session,
                                        'canceled',
                                      );
                                      break;
                                    case 'expire':
                                      _openCheckoutClosureDialog(
                                        session,
                                        'expired',
                                      );
                                      break;
                                    case 'webhook_paid':
                                      _simulateWebhook(
                                        session,
                                        'payment_succeeded',
                                      );
                                      break;
                                    case 'webhook_canceled':
                                      _simulateWebhook(
                                        session,
                                        'payment_canceled',
                                      );
                                      break;
                                    case 'webhook_expired':
                                      _simulateWebhook(
                                        session,
                                        'payment_expired',
                                      );
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (session.status == 'pending' ||
                                      session.status == 'returned')
                                    const PopupMenuItem(
                                      value: 'confirm',
                                      child: Text('Confirmar pagamento'),
                                    ),
                                  if (session.status == 'pending' ||
                                      session.status == 'returned')
                                    const PopupMenuItem(
                                      value: 'cancel',
                                      child: Text('Cancelar checkout'),
                                    ),
                                  if (session.status == 'pending' ||
                                      session.status == 'returned')
                                    const PopupMenuItem(
                                      value: 'expire',
                                      child: Text('Marcar expirado'),
                                    ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'webhook_paid',
                                    child: Text('Simular webhook aprovado'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'webhook_canceled',
                                    child: Text('Simular webhook cancelado'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'webhook_expired',
                                    child: Text('Simular webhook expirado'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Webhooks recentes',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          widget.billingWebhookEventsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            data: (events) {
              if (events.isEmpty) {
                return Text(
                  'Ainda não há webhooks registrados.',
                  style: Theme.of(context).textTheme.bodyMedium,
                );
              }
              return Column(
                children: events
                    .map(
                      (event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          child: Icon(
                            _billingWebhookStatusIcon(event.processingStatus),
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          '${event.provider} · ${_billingWebhookEventLabel(event.eventType)}',
                        ),
                        subtitle: Text(
                          [
                            _billingWebhookStatusLabel(event.processingStatus),
                            DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                                .format(event.receivedAt),
                            if ((event.processingNote ?? '').trim().isNotEmpty)
                              event.processingNote!.trim(),
                          ].join(' · '),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Linha do tempo comercial',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (widget.canManage)
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _openBillingStatusDialog,
                  icon: const Icon(Icons.sync_alt_outlined),
                  label: const Text('Atualizar status'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          widget.billingEventsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            data: (events) {
              if (events.isEmpty) {
                return Text(
                  'Ainda não há eventos comerciais registrados.',
                  style: Theme.of(context).textTheme.bodyMedium,
                );
              }
              return Column(
                children: events
                    .map(
                      (event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          child: Icon(
                            _billingEventIcon(event.eventType),
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(_billingEventTitle(event)),
                        subtitle: Text(
                          [
                            DateFormat(
                              'dd/MM/yyyy HH:mm',
                              'pt_BR',
                            ).format(event.occurredAt),
                            if ((event.note ?? '').trim().isNotEmpty)
                              event.note!.trim(),
                          ].join(' · '),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          if (!widget.canManage) ...[
            const SizedBox(height: 14),
            Text(
              'Somente proprietário, administrador ou admin master podem alterar o plano.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _changePlan(TenantPlanDefinition plan) async {
    if (_isSaving ||
        plan.key == widget.snapshot.plan.key ||
        !widget.canManage) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.onPlanChanged(plan.key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plano alterado para ${plan.label}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openCheckoutConfirmationDialog(
    TenantCheckoutSession session,
  ) async {
    final result = await showDialog<_CheckoutConfirmationDialogResult>(
      context: context,
      builder: (context) => _CheckoutConfirmationDialog(session: session),
    );
    if (result == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await widget.onConfirmCheckout(
        session.id,
        result.note,
        result.providerReference,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checkout confirmado e assinatura ativada.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _simulateWebhook(
    TenantCheckoutSession session,
    String eventType,
  ) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSimulateWebhook(
        session.id,
        session.providerReference,
        eventType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Webhook simulado: ${_billingWebhookEventLabel(eventType)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _canManageCheckoutSession(String status) {
    return status == 'pending' || status == 'returned';
  }

  Future<void> _openCheckoutClosureDialog(
    TenantCheckoutSession session,
    String targetStatus,
  ) async {
    final result = await showDialog<_CheckoutClosureDialogResult>(
      context: context,
      builder: (context) => _CheckoutClosureDialog(
        session: session,
        targetStatus: targetStatus,
      ),
    );
    if (result == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await widget.onCloseCheckout(
        session.id,
        targetStatus,
        result.note,
      );
      if (!mounted) return;
      final label = targetStatus == 'canceled' ? 'cancelado' : 'expirado';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout $label.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openBillingStatusDialog() async {
    final result = await showDialog<_BillingStatusDialogResult>(
      context: context,
      builder: (context) => _BillingStatusDialog(
        initialStatus: widget.snapshot.billingStatus,
        initialTrialEndsAt: widget.snapshot.trialEndsAt,
      ),
    );
    if (result == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await widget.onBillingStatusChanged(
        result.billingStatus,
        result.note,
        result.trialEndsAt,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status da assinatura atualizado.'),
        ),
      );
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

class _CheckoutConfirmationDialogResult {
  const _CheckoutConfirmationDialogResult({
    required this.note,
    required this.providerReference,
  });

  final String? note;
  final String? providerReference;
}

class _CheckoutClosureDialogResult {
  const _CheckoutClosureDialogResult({required this.note});

  final String? note;
}

class _BillingStatusDialogResult {
  const _BillingStatusDialogResult({
    required this.billingStatus,
    required this.note,
    required this.trialEndsAt,
  });

  final String billingStatus;
  final String? note;
  final DateTime? trialEndsAt;
}

class _CheckoutConfirmationDialog extends StatefulWidget {
  const _CheckoutConfirmationDialog({required this.session});

  final TenantCheckoutSession session;

  @override
  State<_CheckoutConfirmationDialog> createState() =>
      _CheckoutConfirmationDialogState();
}

class _CheckoutConfirmationDialogState
    extends State<_CheckoutConfirmationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _noteController;
  late final TextEditingController _providerReferenceController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _providerReferenceController = TextEditingController(
      text: widget.session.providerReference ?? '',
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    _providerReferenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirmar checkout'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plano ${_planLabel(widget.session.planKey)} · ${_checkoutSessionStatusLabel(widget.session.status)}',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _providerReferenceController,
                decoration: const InputDecoration(
                  labelText: 'Referência externa',
                  hintText: 'Ex: ID do pagamento no gateway',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observação',
                  hintText: 'Ex: pagamento validado manualmente',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _CheckoutConfirmationDialogResult(
                note: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
                providerReference:
                    _providerReferenceController.text.trim().isEmpty
                        ? null
                        : _providerReferenceController.text.trim(),
              ),
            );
          },
          child: const Text('Confirmar e ativar'),
        ),
      ],
    );
  }
}

class _CheckoutClosureDialog extends StatefulWidget {
  const _CheckoutClosureDialog({
    required this.session,
    required this.targetStatus,
  });

  final TenantCheckoutSession session;
  final String targetStatus;

  @override
  State<_CheckoutClosureDialog> createState() => _CheckoutClosureDialogState();
}

class _CheckoutClosureDialogState extends State<_CheckoutClosureDialog> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCancel = widget.targetStatus == 'canceled';
    return AlertDialog(
      title: Text(isCancel ? 'Cancelar checkout' : 'Marcar checkout expirado'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plano ${_planLabel(widget.session.planKey)} · ${_checkoutSessionStatusLabel(widget.session.status)}',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Observação',
                hintText: isCancel
                    ? 'Ex: checkout encerrado pelo atendimento'
                    : 'Ex: pagamento não retornou no prazo',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _CheckoutClosureDialogResult(
                note: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
              ),
            );
          },
          child: Text(isCancel ? 'Cancelar checkout' : 'Marcar expirado'),
        ),
      ],
    );
  }
}

class _BillingStatusDialog extends StatefulWidget {
  const _BillingStatusDialog({
    required this.initialStatus,
    required this.initialTrialEndsAt,
  });

  final String initialStatus;
  final DateTime? initialTrialEndsAt;

  @override
  State<_BillingStatusDialog> createState() => _BillingStatusDialogState();
}

class _BillingStatusDialogState extends State<_BillingStatusDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _billingStatus;
  late final TextEditingController _noteController;
  late final TextEditingController _trialEndsAtController;

  @override
  void initState() {
    super.initState();
    _billingStatus = widget.initialStatus;
    _noteController = TextEditingController();
    _trialEndsAtController = TextEditingController(
      text: widget.initialTrialEndsAt == null
          ? ''
          : DateFormat('dd/MM/yyyy', 'pt_BR')
              .format(widget.initialTrialEndsAt!),
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    _trialEndsAtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Atualizar status da assinatura'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _billingStatus,
                decoration: const InputDecoration(labelText: 'Novo status'),
                items: const [
                  DropdownMenuItem(value: 'trialing', child: Text('Em trial')),
                  DropdownMenuItem(value: 'active', child: Text('Ativa')),
                  DropdownMenuItem(
                    value: 'past_due',
                    child: Text('Pagamento pendente'),
                  ),
                  DropdownMenuItem(
                    value: 'canceled',
                    child: Text('Cancelada'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _billingStatus = value);
                },
              ),
              if (_billingStatus == 'trialing') ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _trialEndsAtController,
                  decoration: const InputDecoration(
                    labelText: 'Trial até (dd/mm/aaaa)',
                  ),
                  validator: (value) {
                    if (_billingStatus != 'trialing') return null;
                    if ((value ?? '').trim().isEmpty) {
                      return 'Informe a data final do trial.';
                    }
                    return _parseBrazilianDate(value) == null
                        ? 'Data inválida.'
                        : null;
                  },
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observação',
                  hintText: 'Ex: pagamento confirmado, cobrança em aberto...',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _BillingStatusDialogResult(
                billingStatus: _billingStatus,
                note: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
                trialEndsAt: _billingStatus == 'trialing'
                    ? _parseBrazilianDate(_trialEndsAtController.text)
                    : null,
              ),
            );
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

enum _ChipTone { primary, warning, neutral }

class _PlanStatusChip extends StatelessWidget {
  const _PlanStatusChip({
    required this.label,
    required this.tone,
  });

  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color background;
    final Color foreground;

    switch (tone) {
      case _ChipTone.primary:
        background = colorScheme.primary.withValues(alpha: 0.14);
        foreground = colorScheme.primary;
        break;
      case _ChipTone.warning:
        background = const Color(0xFFFFE8BF);
        foreground = const Color(0xFF9A6200);
        break;
      case _ChipTone.neutral:
        background = Colors.white.withValues(alpha: 0.58);
        foreground = colorScheme.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: background,
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.priceLabel,
    required this.isCurrent,
    required this.canManage,
    required this.isSaving,
    required this.onSelect,
  });

  final TenantPlanDefinition plan;
  final String priceLabel;
  final bool isCurrent;
  final bool canManage;
  final bool isSaving;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NeomorphicPanel(
      borderRadius: 28,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.label,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            priceLabel,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colorScheme.primary,
                ),
          ),
          const SizedBox(height: 10),
          Text(plan.description),
          const SizedBox(height: 14),
          Text('Até ${plan.userLimit} usuários'),
          Text('Até ${plan.unitLimit} unidade(s)'),
          Text('Trial de ${plan.trialDays} dias'),
          const SizedBox(height: 12),
          ..._planFeatureLabels(plan).map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_rounded, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isCurrent || !canManage || isSaving ? null : onSelect,
              child: Text(isCurrent ? 'Plano atual' : 'Selecionar plano'),
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

IconData _billingEventIcon(String eventType) {
  switch (eventType) {
    case 'plan_selected':
      return Icons.flag_outlined;
    case 'plan_changed':
      return Icons.swap_horiz_outlined;
    case 'checkout_started':
      return Icons.open_in_new_outlined;
    case 'checkout_returned':
      return Icons.assignment_turned_in_outlined;
    case 'checkout_confirmed':
      return Icons.verified_outlined;
    case 'checkout_canceled':
      return Icons.cancel_outlined;
    case 'checkout_expired':
      return Icons.timer_off_outlined;
    case 'status_changed':
      return Icons.receipt_long_outlined;
    case 'trial_started':
    default:
      return Icons.timer_outlined;
  }
}

String _billingEventTitle(TenantBillingEvent event) {
  switch (event.eventType) {
    case 'plan_selected':
      return 'Plano inicial confirmado: ${event.planKey ?? '—'}';
    case 'plan_changed':
      return 'Plano alterado: ${event.previousPlanKey ?? '—'} -> ${event.planKey ?? '—'}';
    case 'checkout_started':
      return 'Checkout iniciado: ${event.planKey ?? '—'}';
    case 'checkout_returned':
      return 'Retorno do checkout recebido: ${event.planKey ?? '—'}';
    case 'checkout_confirmed':
      return 'Checkout confirmado: ${event.planKey ?? '—'}';
    case 'checkout_canceled':
      return 'Checkout cancelado: ${event.planKey ?? '—'}';
    case 'checkout_expired':
      return 'Checkout expirado: ${event.planKey ?? '—'}';
    case 'status_changed':
      return 'Status alterado: ${_billingStatusLabel(event.previousBillingStatus ?? 'active')} -> ${_billingStatusLabel(event.billingStatus ?? 'active')}';
    case 'trial_started':
    default:
      return 'Linha do tempo comercial iniciada';
  }
}

String _checkoutSessionStatusLabel(String status) {
  switch (status) {
    case 'returned':
      return 'Retornou do pagamento';
    case 'confirmed':
      return 'Confirmado';
    case 'canceled':
      return 'Cancelado';
    case 'expired':
      return 'Expirado';
    case 'pending':
    default:
      return 'Aguardando retorno';
  }
}

IconData _checkoutSessionIcon(String status) {
  switch (status) {
    case 'returned':
      return Icons.assignment_returned_outlined;
    case 'confirmed':
      return Icons.verified_outlined;
    case 'canceled':
      return Icons.cancel_outlined;
    case 'expired':
      return Icons.timer_off_outlined;
    case 'pending':
    default:
      return Icons.open_in_new_outlined;
  }
}

String _planLabel(String planKey) {
  return tenantPlans[planKey]?.label ?? planKey.toUpperCase();
}

String _billingWebhookEventLabel(String eventType) {
  switch (eventType) {
    case 'payment_succeeded':
      return 'Pagamento aprovado';
    case 'payment_canceled':
      return 'Pagamento cancelado';
    case 'payment_expired':
      return 'Pagamento expirado';
    case 'checkout.confirmed':
      return 'Checkout confirmado';
    case 'checkout.canceled':
      return 'Checkout cancelado';
    case 'checkout.expired':
      return 'Checkout expirado';
    case 'invoice.paid':
      return 'Fatura paga';
    default:
      return eventType;
  }
}

String _billingWebhookStatusLabel(String status) {
  switch (status) {
    case 'processed':
      return 'Processado';
    case 'ignored':
      return 'Ignorado';
    case 'failed':
      return 'Falhou';
    case 'received':
    default:
      return 'Recebido';
  }
}

IconData _billingWebhookStatusIcon(String status) {
  switch (status) {
    case 'processed':
      return Icons.bolt_outlined;
    case 'ignored':
      return Icons.remove_circle_outline;
    case 'failed':
      return Icons.error_outline;
    case 'received':
    default:
      return Icons.cloud_download_outlined;
  }
}

DateTime? _parseBrazilianDate(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return null;
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;
  try {
    final parsed = DateTime(year, month, day);
    if (parsed.day != day || parsed.month != month || parsed.year != year) {
      return null;
    }
    return parsed;
  } catch (_) {
    return null;
  }
}

List<String> _planFeatureLabels(TenantPlanDefinition plan) {
  final labels = <String>[
    'Clientes',
    'Chamados',
    'Agenda',
    'Orçamentos',
    'Ordens de serviço',
    'Configurações',
  ];

  if (plan.hasFeature(TenantFeature.professionals)) {
    labels.add('Profissionais');
  }
  if (plan.hasFeature(TenantFeature.financials)) {
    labels.add('Financeiro');
  }
  if (plan.hasFeature(TenantFeature.reports)) {
    labels.add('Relatórios');
  }
  if (plan.hasFeature(TenantFeature.packages)) {
    labels.add('Pacotes');
  }
  if (plan.hasFeature(TenantFeature.commissions)) {
    labels.add('Comissões');
  }
  if (plan.hasFeature(TenantFeature.payments)) {
    labels.add('Pagamentos');
  }
  if (plan.hasFeature(TenantFeature.fiscal)) {
    labels.add('Fiscal');
  }
  if (plan.hasFeature(TenantFeature.promotions)) {
    labels.add('Promoções');
  }
  if (plan.hasFeature(TenantFeature.campaigns)) {
    labels.add('Campanhas');
  }
  if (plan.hasFeature(TenantFeature.advancedBi)) {
    labels.add('BI avançado');
  }
  if (plan.hasFeature(TenantFeature.ai)) {
    labels.add('IA');
  }
  if (plan.hasFeature(TenantFeature.multiUnit)) {
    labels.add('Múltiplas unidades');
  }

  return labels;
}
