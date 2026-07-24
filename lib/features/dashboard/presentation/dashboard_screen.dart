import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/plans/tenant_plan.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../financials/application/financial_list_notifier.dart';
import '../../../shared/providers/tenant_provider.dart';
import '../../../shared/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(financialListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(currentTenantProvider);
    final user = ref.watch(currentUserProvider);
    final role = ref.watch(currentRoleKeyProvider);
    final financial = ref.watch(financialListProvider);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final planSnapshot = ref.watch(currentTenantPlanProvider);
    final features = ref.watch(currentPlanFeatureSetProvider);
    final trialText = planSnapshot.trialEndsAt == null
        ? null
        : DateFormat('dd/MM/yyyy').format(planSnapshot.trialEndsAt!);

    return Scaffold(
      appBar: AppBar(
        title: Text(tenant?['name'] as String? ?? 'ServiceFlow'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          NeomorphicPanel(
            padding: const EdgeInsets.all(28),
            child: Wrap(
              spacing: 24,
              runSpacing: 20,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.32),
                        offset: const Offset(10, 14),
                        blurRadius: 26,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sistema operacional',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Logado como ${user?.email ?? '—'} · papel: ${role ?? '—'}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          NeomorphicPanel(
            borderRadius: 22,
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MetricTile(
                  icon: Icons.workspace_premium_outlined,
                  label: 'Plano atual',
                  value: planSnapshot.plan.label,
                ),
                _MetricTile(
                  icon: Icons.groups_outlined,
                  label: 'Limite de usuários',
                  value: '${planSnapshot.plan.userLimit}',
                ),
                _MetricTile(
                  icon: Icons.apartment_outlined,
                  label: 'Limite de unidades',
                  value: '${planSnapshot.plan.unitLimit}',
                ),
                _MetricTile(
                  icon: planSnapshot.isTrialing
                      ? Icons.timer_outlined
                      : Icons.verified_outlined,
                  label: planSnapshot.isTrialing
                      ? 'Trial até'
                      : 'Status da assinatura',
                  value: planSnapshot.isTrialing
                      ? (trialText ?? '—')
                      : _billingStatusLabel(planSnapshot.billingStatus),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Resumo financeiro',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          NeomorphicPanel(
            borderRadius: 22,
            padding: const EdgeInsets.all(18),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Saldo em aberto',
                  value: currency.format(financial.openBalanceCents / 100),
                ),
                _MetricTile(
                  icon: Icons.warning_amber_outlined,
                  label: 'Vencido',
                  value: currency.format(financial.overdueBalanceCents / 100),
                ),
                _MetricTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'Recebíveis',
                  value: financial.items.length.toString(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              if (features.contains(TenantFeature.customers))
                _QuickAction(
                  icon: Icons.people_outline,
                  label: 'Clientes',
                  onTap: () => context.go(AppRoutes.customers),
                ),
              if (features.contains(TenantFeature.serviceRequests))
                _QuickAction(
                  icon: Icons.support_agent_outlined,
                  label: 'Chamados',
                  onTap: () => context.go(AppRoutes.serviceRequests),
                ),
              if (features.contains(TenantFeature.appointments))
                _QuickAction(
                  icon: Icons.event_outlined,
                  label: 'Agenda',
                  onTap: () => context.go(AppRoutes.appointments),
                ),
              if (features.contains(TenantFeature.quotations))
                _QuickAction(
                  icon: Icons.request_quote_outlined,
                  label: 'Orçamentos',
                  onTap: () => context.go(AppRoutes.quotations),
                ),
              if (features.contains(TenantFeature.financials))
                _QuickAction(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Financeiro',
                  onTap: () => context.go(AppRoutes.financials),
                ),
              if (features.contains(TenantFeature.payments))
                _QuickAction(
                  icon: Icons.credit_card_outlined,
                  label: 'Pagamentos',
                  onTap: () => context.go(AppRoutes.payments),
                ),
              if (features.contains(TenantFeature.fiscal))
                _QuickAction(
                  icon: Icons.receipt_long_outlined,
                  label: 'Fiscal',
                  onTap: () => context.go(AppRoutes.fiscal),
                ),
              if (features.contains(TenantFeature.promotions))
                _QuickAction(
                  icon: Icons.local_offer_outlined,
                  label: 'Promoções',
                  onTap: () => context.go(AppRoutes.promotions),
                ),
              if (features.contains(TenantFeature.campaigns))
                _QuickAction(
                  icon: Icons.campaign_outlined,
                  label: 'Campanhas',
                  onTap: () => context.go(AppRoutes.campaigns),
                ),
              if (features.contains(TenantFeature.advancedBi))
                _QuickAction(
                  icon: Icons.insights_outlined,
                  label: 'BI avançado',
                  onTap: () => context.go(AppRoutes.advancedBi),
                ),
              if (features.contains(TenantFeature.ai))
                _QuickAction(
                  icon: Icons.auto_awesome_outlined,
                  label: 'IA',
                  onTap: () => context.go(AppRoutes.ai),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _billingStatusLabel(String status) {
    switch (status) {
      case 'trialing':
        return 'Em trial';
      case 'past_due':
        return 'Pagamento pendente';
      case 'canceled':
        return 'Cancelada';
      case 'active':
      default:
        return 'Ativa';
    }
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: NeomorphicInset(
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: NeomorphicPanel(
          borderRadius: 20,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
