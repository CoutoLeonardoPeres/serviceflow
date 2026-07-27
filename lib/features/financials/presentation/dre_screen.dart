import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/financial_list_notifier.dart';
import '../domain/dre_month.dart';

/// DRE simples (F4-P2, ADR-026): regime de caixa, sem plano de contas.
/// Um ano por vez — reaproveita `get_dre_monthly`, que já devolve só os
/// meses com movimento.
final dreYearProvider = StateProvider.autoDispose<int>(
  (ref) => DateTime.now().year,
);

final dreMonthlyProvider = FutureProvider.autoDispose<List<DreMonth>>((ref) {
  final year = ref.watch(dreYearProvider);
  return ref.read(financialRepositoryProvider).getDreMonthly(year);
});

class DreScreen extends ConsumerWidget {
  const DreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = ref.watch(dreYearProvider);
    final async = ref.watch(dreMonthlyProvider);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final monthFormat = DateFormat('MMMM/yyyy', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('DRE'),
        actions: [
          IconButton(
            tooltip: 'Ano anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => ref.read(dreYearProvider.notifier).state = year - 1,
          ),
          Center(child: Text('$year')),
          IconButton(
            tooltip: 'Próximo ano',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => ref.read(dreYearProvider.notifier).state = year + 1,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          message: 'Erro ao carregar o DRE.',
          onRetry: () => ref.invalidate(dreMonthlyProvider),
        ),
        data: (months) {
          if (months.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum pagamento registrado neste ano.\n'
                  'Regime de caixa: mês sem recebimento nem pagamento não aparece aqui.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final totalRevenue =
              months.fold<int>(0, (t, m) => t + m.revenueCents);
          final totalExpense =
              months.fold<int>(0, (t, m) => t + m.expenseCents);
          final totalResult = totalRevenue - totalExpense;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              NeomorphicPanel(
                borderRadius: 24,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryTile(
                      icon: Icons.trending_up,
                      label: 'Receita do ano',
                      value: currency.format(totalRevenue / 100),
                    ),
                    _SummaryTile(
                      icon: Icons.trending_down,
                      label: 'Despesa do ano',
                      value: currency.format(totalExpense / 100),
                    ),
                    _SummaryTile(
                      icon: Icons.summarize_outlined,
                      label: 'Resultado do ano',
                      value: currency.format(totalResult / 100),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...months.map(
                (m) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _capitalize(monthFormat.format(m.monthStart)),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            NeomorphicBadge(
                              icon: Icons.trending_up,
                              label: 'Receita ${currency.format(m.revenueCents / 100)}',
                            ),
                            NeomorphicBadge(
                              icon: Icons.trending_down,
                              label: 'Despesa ${currency.format(m.expenseCents / 100)}',
                            ),
                            NeomorphicBadge(
                              icon: m.resultCents >= 0
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_outlined,
                              label: 'Resultado ${currency.format(m.resultCents / 100)}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
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
                  Text(label),
                  const SizedBox(height: 2),
                  Text(
                    value,
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

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
