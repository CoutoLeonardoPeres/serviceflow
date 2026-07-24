import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env_config.dart';
import '../../../core/plans/plan_checkout.dart';
import '../../../core/plans/tenant_plan.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/onboarding_access_override_stub.dart'
    if (dart.library.html) '../../../core/router/onboarding_access_override_web.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../../shared/providers/tenant_provider.dart';
import '../data/settings_repository.dart';

final planOnboardingSettingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.read(supabaseClientProvider)),
);

class PlanOnboardingScreen extends ConsumerStatefulWidget {
  const PlanOnboardingScreen({super.key});

  @override
  ConsumerState<PlanOnboardingScreen> createState() =>
      _PlanOnboardingScreenState();
}

class _PlanOnboardingScreenState extends ConsumerState<PlanOnboardingScreen> {
  bool _isSaving = false;
  String? _processedCheckoutRef;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRegisterCheckoutReturn();
  }

  @override
  Widget build(BuildContext context) {
    final state = GoRouterState.of(context);
    final tenant = ref.watch(currentTenantProvider);
    final snapshot = ref.watch(currentTenantPlanProvider);
    final activeMemberCount =
        ref.watch(activeTenantMemberCountProvider).maybeWhen(
              data: (value) => value,
              orElse: () => 0,
            );
    final activeUnitCount = ref.watch(activeTenantUnitCountProvider).maybeWhen(
          data: (value) => value,
          orElse: () => 0,
        );
    final tenantSlug = tenant?['slug'] as String?;
    final checkoutStatus = state.uri.queryParameters['checkout'];
    final returnedPlan = state.uri.queryParameters['plan'];
    final formatter = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 2,
    );
    final trialText = snapshot.trialEndsAt == null
        ? null
        : DateFormat('dd/MM/yyyy', 'pt_BR').format(snapshot.trialEndsAt!);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NeomorphicPanel(
                  borderRadius: 34,
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              tenant?['name'] as String? ?? 'ServiceFlow',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton(
                            onPressed: _openSystemAccess,
                            child: const Text('Acessar sistema'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Escolha o plano inicial da sua operação',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A empresa já foi criada. Agora confirme o plano comercial para liberar o uso do sistema. Você poderá trocar depois em Configurações.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetricPill(
                            label: '$activeMemberCount usuário(s) ativos',
                          ),
                          _MetricPill(
                            label: '$activeUnitCount unidade(s) ativas',
                          ),
                        ],
                      ),
                      if (checkoutStatus == 'success') ...[
                        const SizedBox(height: 18),
                        NeomorphicInset(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              returnedPlan == null
                                  ? 'Retorno do checkout recebido. Revise a assinatura em Configurações.'
                                  : 'Retorno do checkout de ${returnedPlan.toUpperCase()} recebido. Revise a assinatura em Configurações.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                      if (trialText != null) ...[
                        const SizedBox(height: 18),
                        NeomorphicBadge(
                          icon: Icons.timer_outlined,
                          label: 'Trial disponível até $trialText',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1080
                        ? 3
                        : constraints.maxWidth >= 760
                            ? 2
                            : 1;
                    final totalSpacing = 18.0 * (columns - 1);
                    final cardWidth =
                        (constraints.maxWidth - totalSpacing) / columns;
                    return Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      children: tenantPlans.values
                          .map(
                            (plan) => SizedBox(
                              width: cardWidth,
                              child: _OnboardingPlanCard(
                                plan: plan,
                                priceLabel:
                                    '${formatter.format(plan.monthlyPriceCents / 100)}/mês',
                                isSaving: _isSaving,
                                isCurrent: plan.key == snapshot.plan.key,
                                activeMemberCount: activeMemberCount,
                                activeUnitCount: activeUnitCount,
                                hasCheckout:
                                    EnvConfig.checkoutUrlForPlan(plan.key) !=
                                        null,
                                onSelect: () => _selectPlan(
                                  planKey: plan.key,
                                  tenantSlug: tenantSlug,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectPlan({
    required String planKey,
    required String? tenantSlug,
  }) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(planOnboardingSettingsRepositoryProvider);
      await repository.completeInitialPlanSelection(planKey: planKey);
      ref.invalidate(activeMembershipProvider);
      ref.invalidate(currentTenantPlanProvider);
      ref.invalidate(currentPlanFeatureSetProvider);
      if (!mounted) return;
      final returnUri = buildAppHashReturnUri(
        '/assinatura',
        queryParameters: {
          'checkout': 'success',
          'plan': planKey,
          'source': 'plan_onboarding',
        },
      );
      final checkoutSession = EnvConfig.checkoutUrlForPlan(planKey) == null
          ? null
          : await repository.createCheckoutSession(
              planKey: planKey,
              source: 'plan_onboarding',
              returnUrl: returnUri.toString(),
              provider: 'external_checkout',
              metadata: {'tenant_slug': tenantSlug},
            );
      final checkout = checkoutSession == null
          ? null
          : buildPlanCheckoutLink(
              planKey: planKey,
              checkoutSessionId: checkoutSession.id,
              tenantSlug: tenantSlug,
              source: 'plan_onboarding',
            );
      final hasCheckout = checkout != null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasCheckout
                ? 'Plano inicial confirmado. Abrindo checkout.'
                : 'Plano inicial confirmado.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (checkout != null) {
        await launchUrl(
          checkout.externalUri,
          mode: LaunchMode.externalApplication,
        );
      }
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _maybeRegisterCheckoutReturn() async {
    final state = GoRouterState.of(context);
    final checkoutStatus = state.uri.queryParameters['checkout'];
    final checkoutRef = state.uri.queryParameters['checkout_ref'];
    if (checkoutStatus != 'success' ||
        checkoutRef == null ||
        checkoutRef.isEmpty ||
        checkoutRef == _processedCheckoutRef) {
      return;
    }

    _processedCheckoutRef = checkoutRef;

    try {
      await ref
          .read(planOnboardingSettingsRepositoryProvider)
          .registerCheckoutReturn(
        checkoutSessionId: checkoutRef,
        metadata: {
          'source': state.uri.queryParameters['source'],
          'plan': state.uri.queryParameters['plan'],
        },
      );
      ref.invalidate(currentTenantPlanProvider);
    } catch (_) {
      // Não bloqueia o retorno da cobrança se o registro comercial falhar.
    }
  }

  Future<void> _openSystemAccess() async {
    enableOnboardingAccessOverride();
    final target = _buildRootAppUri(AppRoutes.login);
    final opened = await launchUrl(target, webOnlyWindowName: '_self');
    if (!opened && mounted) {
      context.go(AppRoutes.login);
    }
  }

  Uri _buildRootAppUri(String route) {
    final base = Uri.base.removeFragment();
    final segments = List<String>.from(base.pathSegments)
      ..removeWhere((segment) => segment.isEmpty);

    if (segments.isNotEmpty && segments.last == 'admin') {
      segments.removeLast();
    }

    final rootPath = segments.isEmpty ? '/' : '/${segments.join('/')}';
    return base.replace(path: rootPath, fragment: route);
  }
}

class _OnboardingPlanCard extends StatelessWidget {
  const _OnboardingPlanCard({
    required this.plan,
    required this.priceLabel,
    required this.isSaving,
    required this.isCurrent,
    required this.activeMemberCount,
    required this.activeUnitCount,
    required this.hasCheckout,
    required this.onSelect,
  });

  final TenantPlanDefinition plan;
  final String priceLabel;
  final bool isSaving;
  final bool isCurrent;
  final int activeMemberCount;
  final int activeUnitCount;
  final bool hasCheckout;
  final VoidCallback onSelect;

  bool get exceedsUserLimit => activeMemberCount > plan.userLimit;
  bool get exceedsUnitLimit => activeUnitCount > plan.unitLimit;
  bool get isSelectable => !exceedsUserLimit && !exceedsUnitLimit;

  @override
  Widget build(BuildContext context) {
    final featureLabels = _planFeatureLabels(plan);
    final blockedReason = exceedsUserLimit
        ? 'Plano comporta até ${plan.userLimit} usuário(s); a operação atual tem $activeMemberCount.'
        : exceedsUnitLimit
            ? 'Plano comporta até ${plan.unitLimit} unidade(s); a operação atual tem $activeUnitCount.'
            : null;

    return NeomorphicPanel(
      borderRadius: 30,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.label,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            priceLabel,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            plan.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.3),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(label: 'Até ${plan.userLimit} usuários'),
              _MetricPill(label: 'Até ${plan.unitLimit} unidade(s)'),
              _MetricPill(label: 'Trial de ${plan.trialDays} dias'),
            ],
          ),
          const SizedBox(height: 12),
          ...featureLabels.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '•',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (blockedReason != null) ...[
            const SizedBox(height: 8),
            Text(
              blockedReason,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSaving || !isSelectable ? null : onSelect,
              child: isSaving && isCurrent
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      !isSelectable
                          ? 'Plano indisponível para a operação atual'
                          : hasCheckout
                              ? 'Escolher e ir para pagamento'
                              : (plan.key == 'starter'
                                  ? 'Começar com este plano'
                                  : 'Escolher este plano'),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

List<String> _planFeatureLabels(TenantPlanDefinition plan) {
  final labels = <String>[
    'Agenda operacional',
    'Cadastros de clientes',
    'Chamados e ordens de serviço',
  ];
  if (plan.hasFeature(TenantFeature.professionals)) {
    labels.add('Cadastro formal de profissionais');
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
    labels.add('Multiunidade');
  }
  return labels;
}
