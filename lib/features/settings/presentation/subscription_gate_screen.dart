import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/plans/plan_checkout.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../shared/providers/tenant_provider.dart';
import '../../auth/application/auth_notifier.dart';
import 'settings_screen.dart';

class SubscriptionGateScreen extends ConsumerStatefulWidget {
  const SubscriptionGateScreen({super.key});

  @override
  ConsumerState<SubscriptionGateScreen> createState() =>
      _SubscriptionGateScreenState();
}

class _SubscriptionGateScreenState
    extends ConsumerState<SubscriptionGateScreen> {
  bool _isOpeningCheckout = false;
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
    final planSnapshot = ref.watch(currentTenantPlanProvider);
    final blockReason = ref.watch(planAccessBlockReasonProvider);
    final roleKey = ref.watch(currentRoleKeyProvider);
    final tenantSlug = tenant?['slug'] as String?;
    final checkoutStatus = state.uri.queryParameters['checkout'];
    final portalStatus = state.uri.queryParameters['portal'];
    final canManagePlan = {
      'tenant_owner',
      'tenant_admin',
      'platform_admin',
    }.contains(roleKey);

    final title = switch (planSnapshot.billingStatus) {
      'past_due' => 'Assinatura pendente',
      'canceled' => 'Assinatura cancelada',
      _ when planSnapshot.isTrialExpired => 'Trial encerrado',
      _ => 'Regularização necessária',
    };

    final description = switch (planSnapshot.billingStatus) {
      'past_due' =>
        'O acesso operacional foi pausado até a regularização do pagamento do plano.',
      'canceled' =>
        'A operação desta empresa foi pausada porque a assinatura não está mais ativa.',
      _ when planSnapshot.isTrialExpired =>
        'O período de avaliação terminou. Escolha um plano para liberar novamente o sistema.',
      _ => 'É necessário revisar o status comercial da empresa para continuar.',
    };

    final trialLabel = planSnapshot.trialEndsAt == null
        ? null
        : DateFormat('dd/MM/yyyy', 'pt_BR').format(planSnapshot.trialEndsAt!);
    final planCheckoutAvailable = buildPlanCheckoutLink(
          planKey: planSnapshot.plan.key,
          checkoutSessionId: 'preview',
          tenantSlug: tenantSlug,
          source: 'subscription_gate',
        ) !=
        null;
    final billingPortal = buildBillingPortalUri(
      tenantSlug: tenantSlug,
      source: 'subscription_gate',
    );

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: NeomorphicPanel(
              borderRadius: 34,
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.28),
                              offset: const Offset(10, 14),
                              blurRadius: 26,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.workspace_premium_outlined,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tenant?['name'] as String? ?? 'ServiceFlow',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (checkoutStatus == 'success' ||
                      portalStatus == 'return') ...[
                    const SizedBox(height: 14),
                    NeomorphicInset(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          checkoutStatus == 'success'
                              ? 'Retorno do checkout recebido. Revise o status da assinatura em Configurações.'
                              : 'Retorno do portal de cobrança recebido. Atualize a assinatura se necessário.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                  if (blockReason != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      blockReason,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      NeomorphicBadge(
                        icon: Icons.sell_outlined,
                        label: 'Plano: ${planSnapshot.plan.label}',
                      ),
                      NeomorphicBadge(
                        icon: Icons.groups_outlined,
                        label: 'Usuários: até ${planSnapshot.plan.userLimit}',
                      ),
                      NeomorphicBadge(
                        icon: Icons.apartment_outlined,
                        label: 'Unidades: até ${planSnapshot.plan.unitLimit}',
                      ),
                      if (trialLabel != null)
                        NeomorphicBadge(
                          icon: Icons.timer_outlined,
                          label: 'Trial até $trialLabel',
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  NeomorphicInset(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            canManagePlan
                                ? 'Como regularizar'
                                : 'Próximo passo',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            canManagePlan
                                ? 'Abra Configurações para ajustar o plano ou revisar a assinatura. Após isso, recarregue a página.'
                                : 'Peça para o proprietário ou administrador da empresa revisar a assinatura em Configurações.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.end,
                    children: [
                      if (canManagePlan && planCheckoutAvailable)
                        ElevatedButton.icon(
                          onPressed: _isOpeningCheckout
                              ? null
                              : () => _openCheckout(
                                    planKey: planSnapshot.plan.key,
                                    tenantSlug: tenantSlug,
                                  ),
                          icon: const Icon(Icons.open_in_new_outlined),
                          label: Text(
                            _isOpeningCheckout
                                ? 'Abrindo...'
                                : 'Ir para pagamento',
                          ),
                        ),
                      if (canManagePlan && billingPortal != null)
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            billingPortal,
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.credit_card_outlined),
                          label: const Text('Portal de cobrança'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(authNotifierProvider.notifier)
                              .signOut();
                        },
                        icon: const Icon(Icons.logout_outlined),
                        label: const Text('Sair'),
                      ),
                      if (canManagePlan)
                        ElevatedButton.icon(
                          onPressed: () => context.go(AppRoutes.settings),
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Abrir configurações'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCheckout({
    required String planKey,
    required String? tenantSlug,
  }) async {
    setState(() => _isOpeningCheckout = true);
    try {
      final repository = ref.read(settingsRepositoryProvider);
      final returnUri = buildAppHashReturnUri(
        '/assinatura',
        queryParameters: {
          'checkout': 'success',
          'plan': planKey,
          'source': 'subscription_gate',
        },
      );
      final session = await repository.createCheckoutSession(
        planKey: planKey,
        source: 'subscription_gate',
        returnUrl: returnUri.toString(),
        provider: 'external_checkout',
        metadata: {'tenant_slug': tenantSlug},
      );
      final checkout = buildPlanCheckoutLink(
        planKey: planKey,
        checkoutSessionId: session.id,
        tenantSlug: tenantSlug,
        source: 'subscription_gate',
      );
      if (checkout == null) {
        throw StateError('Checkout não configurado para este plano.');
      }
      await launchUrl(
        checkout.externalUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpeningCheckout = false);
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
      await ref.read(settingsRepositoryProvider).registerCheckoutReturn(
        checkoutSessionId: checkoutRef,
        metadata: {
          'source': state.uri.queryParameters['source'],
          'plan': state.uri.queryParameters['plan'],
        },
      );
      ref.invalidate(currentTenantPlanProvider);
      ref.invalidate(tenantBillingEventsProvider);
    } catch (_) {
      // Não bloqueia a tela de assinatura se o retorno comercial falhar.
    }
  }
}
