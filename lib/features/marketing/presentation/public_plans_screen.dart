import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/plans/tenant_plan.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neomorphic.dart';

/// Vitrine pública de planos, mostrada em '/' para visitantes não
/// autenticados. Só exibe os planos e leva para o login — a escolha de
/// plano de fato acontece no onboarding pós-cadastro (PlanOnboardingScreen).
class PublicPlansScreen extends StatelessWidget {
  const PublicPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NeomorphicBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                children: [
                  Text(
                    'ServiceFlow',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Escolha o plano ideal para a sua operação de serviços',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: tenantPlans.values
                        .map((plan) => _PlanCard(plan: plan))
                        .toList(),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: 320,
                    child: ElevatedButton(
                      onPressed: () => context.go(AppRoutes.login),
                      child: const Text('Acessar sistema'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final TenantPlanDefinition plan;

  @override
  Widget build(BuildContext context) {
    final price = plan.monthlyPriceCents / 100;
    return SizedBox(
      width: 240,
      child: NeomorphicPanel(
        borderRadius: 28,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.label,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              plan.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
            ),
            const SizedBox(height: 18),
            Text(
              'R\$ ${price.toStringAsFixed(0)}/mês',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Até ${plan.userLimit} usuários · ${plan.trialDays} dias grátis',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
