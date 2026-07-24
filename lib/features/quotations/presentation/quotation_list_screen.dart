import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/routing/field_route.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/field_route_panel.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../core/widgets/route_actions.dart';
import '../application/quotation_list_notifier.dart';
import '../domain/quotation.dart';
import 'quotation_form_screen.dart';
import 'widgets/quotation_status_chip.dart';

class QuotationListScreen extends ConsumerStatefulWidget {
  const QuotationListScreen({super.key});

  @override
  ConsumerState<QuotationListScreen> createState() =>
      _QuotationListScreenState();
}

class _QuotationListScreenState extends ConsumerState<QuotationListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(quotationListProvider.notifier).load();
    });
  }

  Future<void> _openQuotationDialog() async {
    final created = await showAppFormDialog<bool>(
      context: context,
      title: 'Novo orçamento',
      maxWidth: 940,
      child: const QuotationFormScreen(embedded: true),
    );
    if (created == true && mounted) {
      ref.read(quotationListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quotationListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orçamentos'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(quotationListProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQuotationDialog,
        icon: const Icon(Icons.add),
        label: const Text('Novo orçamento'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(quotationListProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            NeomorphicPanel(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.request_quote_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${state.items.length} orçamento(s) no radar',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!state.isLoading && state.error == null && !state.isEmpty) ...[
              FieldRoutePanel<Quotation>(
                title: 'Roteiro sugerido dos orçamentos',
                items: state.items,
                destinationFor: _quotationDestination,
                labelFor: (quote) =>
                    '${quote.displayNumber} · ${quote.customerName ?? 'Cliente'}',
              ),
              const SizedBox(height: 16),
            ],
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 96),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null)
              ErrorView(
                message:
                    state.error?.userMessage ?? 'Erro ao carregar orçamentos.',
                onRetry: () =>
                    ref.read(quotationListProvider.notifier).refresh(),
              )
            else if (state.isEmpty)
              EmptyView(
                message:
                    'Nenhum orçamento encontrado. Crie uma proposta para enviar ao cliente.',
                actionLabel: 'Novo orçamento',
                action: _openQuotationDialog,
              )
            else
              ...state.items.map(
                (quotation) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _QuotationCard(quotation: quotation),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuotationCard extends StatelessWidget {
  const _QuotationCard({required this.quotation});

  final Quotation quotation;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go(AppRoutes.quotationDetail(quotation.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${quotation.displayNumber} · ${quotation.customerName ?? 'Cliente'}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  QuotationStatusChip(status: quotation.status),
                ],
              ),
              if (quotation.requestTitle != null) ...[
                const SizedBox(height: 6),
                Text(quotation.requestTitle!),
              ],
              const SizedBox(height: 12),
              Text(
                currency.format(quotation.totalCents / 100),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (quotation.routeAddress != null)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.place_outlined, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          quotation.routeAddress!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  RouteActions(
                    destination: _quotationDestination(quotation),
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

RouteDestination _quotationDestination(Quotation quotation) => RouteDestination(
      label:
          '${quotation.displayNumber} · ${quotation.customerName ?? 'Cliente'}',
      address: quotation.routeAddress,
      latitude: quotation.routeLatitude,
      longitude: quotation.routeLongitude,
      priorityLevel: quotation.status == QuotationStatus.approved ? 4 : 2,
      scheduledAt: quotation.validUntil,
    );
