import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/platform_admin_provider.dart';
import '../domain/platform_tenant.dart';

class PlatformAdminScreen extends ConsumerStatefulWidget {
  const PlatformAdminScreen({super.key});

  @override
  ConsumerState<PlatformAdminScreen> createState() =>
      _PlatformAdminScreenState();
}

class _PlatformAdminScreenState extends ConsumerState<PlatformAdminScreen> {
  final _searchController = TextEditingController();
  String _status = 'all';
  String _plan = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(isPlatformAdminProvider);
    final tenants = ref.watch(platformTenantsProvider);

    return access.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: error.toString(),
        onRetry: () => ref.invalidate(isPlatformAdminProvider),
      ),
      data: (isAdmin) => isAdmin
          ? _buildAdminView(context, tenants)
          : const _AccessDeniedState(),
    );
  }

  Widget _buildAdminView(
    BuildContext context,
    AsyncValue<List<PlatformTenant>> tenants,
  ) {
    final list = tenants.valueOrNull ?? const <PlatformTenant>[];
    final query = _searchController.text.trim().toLowerCase();
    final filtered = list.where((tenant) {
      final matchesSearch = query.isEmpty ||
          tenant.name.toLowerCase().contains(query) ||
          tenant.slug.toLowerCase().contains(query);
      final matchesStatus = _status == 'all' || tenant.status == _status;
      final matchesPlan = _plan == 'all' || tenant.plan.key == _plan;
      return matchesSearch && matchesStatus && matchesPlan;
    }).toList();
    final active = list.where((tenant) => tenant.status == 'active').length;
    final trialing =
        list.where((tenant) => tenant.billingStatus == 'trialing').length;
    final users = list.fold<int>(0, (sum, tenant) => sum + tenant.activeUsers);

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(platformTenantsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 32),
        children: [
          Text(
            'Painel administrativo',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Visão central das empresas, planos e capacidade da plataforma.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.inkMuted,
                ),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 4 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _MetricCard(
                    width: width,
                    icon: Icons.business_outlined,
                    label: 'Empresas',
                    value: '${list.length}',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.verified_outlined,
                    label: 'Ativas',
                    value: '$active',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.timer_outlined,
                    label: 'Em trial',
                    value: '$trialing',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.groups_outlined,
                    label: 'Usuários ativos',
                    value: '$users',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          NeomorphicPanel(
            padding: const EdgeInsets.all(18),
            borderRadius: AppColors.radiusContainer,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final search = SizedBox(
                  width: compact ? double.infinity : 360,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Buscar empresa',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                );
                final status = _FilterSelect(
                  label: 'Status',
                  value: _status,
                  items: const {
                    'all': 'Todos',
                    'active': 'Ativas',
                    'suspended': 'Suspensas',
                    'closed': 'Encerradas',
                  },
                  onChanged: (value) => setState(() => _status = value),
                );
                final plan = _FilterSelect(
                  label: 'Plano',
                  value: _plan,
                  items: const {
                    'all': 'Todos',
                    'starter': 'Starter',
                    'professional': 'Professional',
                    'business': 'Business',
                    'enterprise': 'Enterprise',
                  },
                  onChanged: (value) => setState(() => _plan = value),
                );
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [search, status, plan],
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          if (tenants.isLoading && list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (tenants.hasError)
            _ErrorState(
              message: tenants.error.toString(),
              onRetry: () => ref.invalidate(platformTenantsProvider),
            )
          else if (filtered.isEmpty)
            const _EmptyState()
          else
            ...filtered.map((tenant) => _TenantCard(tenant: tenant)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: NeomorphicInset(
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSelect extends StatelessWidget {
  const _FilterSelect({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: items.entries
            .map((item) =>
                DropdownMenuItem(value: item.key, child: Text(item.value)))
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant});

  final PlatformTenant tenant;

  @override
  Widget build(BuildContext context) {
    final date = tenant.createdAt == null
        ? 'Data não informada'
        : DateFormat('dd/MM/yyyy').format(tenant.createdAt!.toLocal());
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NeomorphicPanel(
        borderRadius: AppColors.radiusContainer,
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 680;
            final heading = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NeomorphicIconWell(
                  icon: Icons.business_outlined,
                  size: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        tenant.slug,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.inkMuted,
                            ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(label: _statusLabel(tenant.status)),
              ],
            );
            final details = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                NeomorphicBadge(
                    icon: Icons.workspace_premium_outlined,
                    label: tenant.plan.label),
                NeomorphicBadge(
                    icon: Icons.groups_outlined,
                    label: '${tenant.activeUsers} usuários'),
                NeomorphicBadge(
                    icon: Icons.location_city_outlined,
                    label: '${tenant.activeUnits} unidades'),
                NeomorphicBadge(
                    icon: Icons.calendar_today_outlined,
                    label: 'Criada em $date'),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 16),
                details,
                if (narrow) ...[
                  const SizedBox(height: 14),
                  Text('Cobrança: ${_billingLabel(tenant.billingStatus)}'),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                        'Cobrança: ${_billingLabel(tenant.billingStatus)}'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'suspended' => 'Suspensa',
        'closed' => 'Encerrada',
        _ => 'Ativa',
      };

  static String _billingLabel(String status) => switch (status) {
        'trialing' => 'Em trial',
        'past_due' => 'Pagamento pendente',
        'canceled' => 'Cancelada',
        _ => 'Ativa',
      };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return NeomorphicBadge(
      icon: Icons.circle,
      label: label,
    );
  }
}

class _AccessDeniedState extends StatelessWidget {
  const _AccessDeniedState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Acesso restrito ao administrador da plataforma.'),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('Nenhuma empresa encontrada com os filtros atuais.'),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
}
