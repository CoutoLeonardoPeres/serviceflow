import 'dart:async';

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
import '../application/work_order_list_notifier.dart';
import '../domain/work_order.dart';
import 'widgets/work_order_status_chip.dart';
import 'work_order_form_screen.dart';

class WorkOrderListScreen extends ConsumerStatefulWidget {
  const WorkOrderListScreen({super.key});

  @override
  ConsumerState<WorkOrderListScreen> createState() =>
      _WorkOrderListScreenState();
}

class _WorkOrderListScreenState extends ConsumerState<WorkOrderListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workOrderListProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openWorkOrderDialog() async {
    final created = await showAppFormDialog<bool>(
      context: context,
      title: 'Nova OS',
      child: const WorkOrderFormScreen(embedded: true),
    );
    if (created == true && mounted) {
      ref.read(workOrderListProvider.notifier).refresh();
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final current = ref.read(workOrderListProvider).filter;
      ref.read(workOrderListProvider.notifier).applyFilter(
            current.copyWith(
              search: value.trim().isEmpty ? null : value.trim(),
              clearSearch: value.trim().isEmpty,
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workOrderListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordens de serviço'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(workOrderListProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openWorkOrderDialog,
        icon: const Icon(Icons.add_task_outlined),
        label: const Text('Nova OS'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(workOrderListProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            NeomorphicPanel(
              borderRadius: 22,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        child: const Icon(Icons.engineering_outlined),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${state.items.length} OS em execução',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SearchBar(
                    controller: _searchController,
                    hintText: 'Buscar OS',
                    leading: const Icon(Icons.search),
                    onChanged: _onSearch,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!state.isLoading && state.error == null && !state.isEmpty) ...[
              FieldRoutePanel<WorkOrder>(
                title: 'Roteiro sugerido das OS',
                items: state.items,
                destinationFor: _workOrderDestination,
                labelFor: (workOrder) =>
                    '${workOrder.displayNumber} · ${workOrder.customerName ?? workOrder.title}',
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
                message: state.error?.userMessage ?? 'Erro ao carregar OS.',
                onRetry: () =>
                    ref.read(workOrderListProvider.notifier).refresh(),
              )
            else if (state.isEmpty)
              EmptyView(
                message:
                    'Nenhuma OS encontrada. Crie uma ordem para iniciar a execução do serviço.',
                actionLabel: 'Nova OS',
                action: _openWorkOrderDialog,
              )
            else
              ...state.items.map(
                (workOrder) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WorkOrderCard(workOrder: workOrder),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({required this.workOrder});

  final WorkOrder workOrder;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go(AppRoutes.workOrderDetail(workOrder.id)),
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
                      '${workOrder.displayNumber} · ${workOrder.customerName ?? 'Cliente'}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  WorkOrderStatusChip(status: workOrder.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(workOrder.title),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.payments_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currency.format(workOrder.totalCents / 100),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (workOrder.scheduledStart != null)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        DateFormat('dd/MM HH:mm').format(
                          workOrder.scheduledStart!.toLocal(),
                        ),
                      ),
                    ),
                  if (workOrder.routeAddress != null)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.place_outlined, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          workOrder.routeAddress!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  RouteActions(
                    destination: _workOrderDestination(workOrder),
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

RouteDestination _workOrderDestination(WorkOrder workOrder) => RouteDestination(
      label:
          '${workOrder.displayNumber} · ${workOrder.customerName ?? workOrder.title}',
      address: workOrder.routeAddress,
      latitude: workOrder.routeLatitude,
      longitude: workOrder.routeLongitude,
      priorityLevel: switch (workOrder.status) {
        WorkOrderStatus.inProgress => 5,
        WorkOrderStatus.scheduled => 4,
        WorkOrderStatus.awaitingCustomer => 2,
        WorkOrderStatus.paused => 2,
        WorkOrderStatus.done => 1,
        WorkOrderStatus.cancelled => 1,
        _ => 3,
      },
      scheduledAt: workOrder.scheduledStart,
    );
