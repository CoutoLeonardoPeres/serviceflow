import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/plans/tenant_plan.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/neomorphic.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/tenant_provider.dart';
import '../../features/auth/application/auth_notifier.dart';

/// Breakpoints de layout.
abstract class Breakpoints {
  /// Abaixo: mobile (NavigationBar inferior).
  static const mobile = 600.0;

  /// Acima: desktop (NavigationRail lateral).
  static const desktop = 1024.0;
}

/// Destino de navegação.
class _NavDestination {
  const _NavDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.feature,
  });

  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final TenantFeature? feature;
}

const _destinations = [
  _NavDestination(
    route: AppRoutes.dashboard,
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    label: 'Início',
    feature: TenantFeature.dashboard,
  ),
  _NavDestination(
    route: AppRoutes.customers,
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    label: 'Clientes',
    feature: TenantFeature.customers,
  ),
  _NavDestination(
    route: AppRoutes.serviceRequests,
    icon: Icons.support_agent_outlined,
    selectedIcon: Icons.support_agent,
    label: 'Chamados',
    feature: TenantFeature.serviceRequests,
  ),
  _NavDestination(
    route: AppRoutes.appointments,
    icon: Icons.event_outlined,
    selectedIcon: Icons.event,
    label: 'Agenda',
    feature: TenantFeature.appointments,
  ),
  _NavDestination(
    route: AppRoutes.professionals,
    icon: Icons.groups_2_outlined,
    selectedIcon: Icons.groups,
    label: 'Profissionais',
    feature: TenantFeature.professionals,
  ),
  _NavDestination(
    route: AppRoutes.quotations,
    icon: Icons.request_quote_outlined,
    selectedIcon: Icons.request_quote,
    label: 'Orçamentos',
    feature: TenantFeature.quotations,
  ),
  _NavDestination(
    route: AppRoutes.workOrders,
    icon: Icons.engineering_outlined,
    selectedIcon: Icons.engineering,
    label: 'OS',
    feature: TenantFeature.workOrders,
  ),
  _NavDestination(
    route: AppRoutes.stock,
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    label: 'Estoque',
    feature: TenantFeature.stock,
  ),
  _NavDestination(
    route: AppRoutes.purchases,
    icon: Icons.shopping_cart_outlined,
    selectedIcon: Icons.shopping_cart,
    label: 'Compras',
    feature: TenantFeature.stock,
  ),
  _NavDestination(
    route: AppRoutes.financials,
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    label: 'Financeiro',
    feature: TenantFeature.financials,
  ),
  _NavDestination(
    route: AppRoutes.payables,
    icon: Icons.request_page_outlined,
    selectedIcon: Icons.request_page,
    label: 'A Pagar',
    feature: TenantFeature.financials,
  ),
  _NavDestination(
    route: AppRoutes.dre,
    icon: Icons.summarize_outlined,
    selectedIcon: Icons.summarize,
    label: 'DRE',
    feature: TenantFeature.financials,
  ),
  _NavDestination(
    route: AppRoutes.payments,
    icon: Icons.credit_card_outlined,
    selectedIcon: Icons.credit_card,
    label: 'Pagamentos',
    feature: TenantFeature.payments,
  ),
  _NavDestination(
    route: AppRoutes.fiscal,
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Fiscal',
    feature: TenantFeature.fiscal,
  ),
  _NavDestination(
    route: AppRoutes.promotions,
    icon: Icons.local_offer_outlined,
    selectedIcon: Icons.local_offer,
    label: 'Promoções',
    feature: TenantFeature.promotions,
  ),
  _NavDestination(
    route: AppRoutes.campaigns,
    icon: Icons.campaign_outlined,
    selectedIcon: Icons.campaign,
    label: 'Campanhas',
    feature: TenantFeature.campaigns,
  ),
  _NavDestination(
    route: AppRoutes.reports,
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics,
    label: 'Relatórios',
    feature: TenantFeature.reports,
  ),
  _NavDestination(
    route: AppRoutes.advancedBi,
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    label: 'BI avançado',
    feature: TenantFeature.advancedBi,
  ),
  _NavDestination(
    route: AppRoutes.ai,
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome,
    label: 'IA',
    feature: TenantFeature.ai,
  ),
  _NavDestination(
    route: AppRoutes.settings,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Configurações',
    feature: TenantFeature.settings,
  ),
];

/// Shell responsivo: NavigationRail no desktop, NavigationBar no mobile.
class ResponsiveShell extends ConsumerWidget {
  const ResponsiveShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= Breakpoints.mobile) {
      return _DesktopShell(child: child);
    }
    return _MobileShell(child: child);
  }
}

// ── Desktop (Rail) ──────────────────────────────────────────────────────────
class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({required this.child});

  final Widget child;

  int _indexForRoute(String location, List<_NavDestination> destinations) {
    for (int i = 0; i < destinations.length; i++) {
      if (location.startsWith(destinations[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final features = ref.watch(currentPlanFeatureSetProvider);
    final destinations = _destinations
        .where(
          (destination) =>
              destination.feature == null ||
              features.contains(destination.feature),
        )
        .toList();
    final selectedIndex = _indexForRoute(location, destinations);
    final tenant = ref.watch(currentTenantProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      body: NeomorphicBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth:
                        MediaQuery.sizeOf(context).width >= Breakpoints.desktop
                            ? 280
                            : 104,
                    maxWidth:
                        MediaQuery.sizeOf(context).width >= Breakpoints.desktop
                            ? 320
                            : 104,
                  ),
                  child: NeomorphicPanel(
                    borderRadius: 34,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: NavigationRail(
                            extended: MediaQuery.sizeOf(context).width >=
                                Breakpoints.desktop,
                            scrollable: true,
                            selectedIndex: selectedIndex,
                            onDestinationSelected: (i) =>
                                context.go(destinations[i].route),
                            leading: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(10, 10, 10, 18),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  NeomorphicInset(
                                    borderRadius: 20,
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(
                                      Icons.electrical_services_rounded,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      size: 30,
                                    ),
                                  ),
                                  if (MediaQuery.sizeOf(context).width >=
                                      Breakpoints.desktop) ...[
                                    const SizedBox(width: 14),
                                    Text(
                                      'ServiceFlow',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            destinations: destinations
                                .map(
                                  (d) => NavigationRailDestination(
                                    icon: Icon(d.icon),
                                    selectedIcon: Icon(d.selectedIcon),
                                    label: Text(d.label),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 12,
                            right: 12,
                            top: 8,
                            bottom: 12,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _UserMenu(
                              tenantName: tenant?['name'] as String? ?? '',
                              userEmail: user?.email ?? '',
                              onLogout: () => ref
                                  .read(authNotifierProvider.notifier)
                                  .signOut(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mobile (Bottom Bar) ─────────────────────────────────────────────────────
class _MobileShell extends ConsumerWidget {
  const _MobileShell({required this.child});

  final Widget child;

  int _indexForRoute(String location, List<_NavDestination> destinations) {
    for (int i = 0; i < destinations.length; i++) {
      if (location.startsWith(destinations[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final features = ref.watch(currentPlanFeatureSetProvider);
    final destinations = _destinations
        .where(
          (destination) =>
              destination.feature == null ||
              features.contains(destination.feature),
        )
        .toList();
    final selectedIndex = _indexForRoute(location, destinations);

    return Scaffold(
      body: NeomorphicBackdrop(
        child: child,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: NeomorphicPanel(
          borderRadius: 26,
          padding: EdgeInsets.zero,
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) => context.go(destinations[i].route),
            destinations: destinations
                .map((d) => NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ── Menu de usuário ──────────────────────────────────────────────────────────
class _UserMenu extends StatelessWidget {
  const _UserMenu({
    required this.tenantName,
    required this.userEmail,
    required this.onLogout,
  });

  final String tenantName;
  final String userEmail;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menu do usuário',
      color: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      icon: const NeomorphicInset(
        borderRadius: 20,
        padding: EdgeInsets.all(10),
        child: Icon(Icons.account_circle_outlined),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tenantName.isNotEmpty)
                Text(
                  tenantName,
                  style: Theme.of(context).textTheme.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                userEmail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Sair'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'logout') onLogout();
      },
    );
  }
}
