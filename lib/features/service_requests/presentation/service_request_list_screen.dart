import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/routing/field_route.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/field_route_panel.dart';
import '../../../core/widgets/route_actions.dart';
import '../application/service_request_list_notifier.dart';
import '../domain/service_request.dart';
import 'service_request_form_screen.dart';
import 'widgets/service_request_status_chip.dart';

class ServiceRequestListScreen extends ConsumerStatefulWidget {
  const ServiceRequestListScreen({super.key});

  @override
  ConsumerState<ServiceRequestListScreen> createState() =>
      _ServiceRequestListScreenState();
}

class _ServiceRequestListScreenState
    extends ConsumerState<ServiceRequestListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(serviceRequestListProvider.notifier).load();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(serviceRequestListProvider.notifier).loadMore();
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final current = ref.read(serviceRequestListProvider).filter;
      ref.read(serviceRequestListProvider.notifier).applyFilter(
            current.copyWith(
              search: value.trim().isEmpty ? null : value.trim(),
              clearSearch: value.trim().isEmpty,
            ),
          );
    });
  }

  Future<void> _openServiceRequestDialog() async {
    final created = await showAppFormDialog<bool>(
      context: context,
      title: 'Novo chamado',
      maxWidth: 1100,
      child: const ServiceRequestFormScreen(embedded: true),
    );
    if (created == true && mounted) {
      ref.read(serviceRequestListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serviceRequestListProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chamados'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(serviceRequestListProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openServiceRequestDialog,
        icon: const Icon(Icons.add),
        label: const Text('Novo chamado'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(serviceRequestListProvider.notifier).refresh(),
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.08),
                    offset: const Offset(8, 10),
                    blurRadius: 22,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.75),
                    offset: const Offset(-6, -6),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SearchBar(
                      controller: _searchController,
                      hintText: 'Buscar chamados',
                      leading: const Icon(Icons.search),
                      onChanged: _onSearch,
                    ),
                    const SizedBox(height: 12),
                    _StatusFilters(
                      selected: state.filter.status,
                      onSelected: (status) {
                        final current =
                            ref.read(serviceRequestListProvider).filter;
                        ref
                            .read(serviceRequestListProvider.notifier)
                            .applyFilter(
                              current.copyWith(
                                status: status,
                                clearStatus: status == null,
                              ),
                            );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!state.isLoading && state.error == null && !state.isEmpty) ...[
              FieldRoutePanel<ServiceRequest>(
                title: 'Roteiro sugerido dos chamados',
                items: state.items,
                destinationFor: _serviceRequestDestination,
                labelFor: (request) =>
                    '${request.displayNumber} · ${request.customerName ?? request.title}',
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
                    state.error?.userMessage ?? 'Erro ao carregar chamados.',
                onRetry: () =>
                    ref.read(serviceRequestListProvider.notifier).refresh(),
              )
            else if (state.isEmpty)
              EmptyView(
                message:
                    'Nenhum chamado encontrado. Crie o primeiro chamado para iniciar o atendimento.',
                actionLabel: 'Novo chamado',
                action: _openServiceRequestDialog,
              )
            else
              ...state.items.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ServiceRequestCard(request: request),
                ),
              ),
            if (state.isLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.selected,
    required this.onSelected,
  });

  final ServiceRequestStatus? selected;
  final ValueChanged<ServiceRequestStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    const statuses = [
      ServiceRequestStatus.opened,
      ServiceRequestStatus.triage,
      ServiceRequestStatus.awaitingCustomer,
      ServiceRequestStatus.scheduled,
      ServiceRequestStatus.cancelled,
      ServiceRequestStatus.closed,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          selected: selected == null,
          label: const Text('Todos'),
          onSelected: (_) => onSelected(null),
        ),
        ...statuses.map(
          (status) => FilterChip(
            selected: selected == status,
            label: Text(status.label),
            onSelected: (_) => onSelected(selected == status ? null : status),
          ),
        ),
      ],
    );
  }
}

class _ServiceRequestCard extends StatelessWidget {
  const _ServiceRequestCard({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(AppRoutes.serviceRequestDetail(request.id)),
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
                      '${request.displayNumber} · ${request.title}',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ServiceRequestStatusChip(status: request.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                request.customerName ?? 'Cliente não informado',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                request.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    icon: Icons.forum_outlined,
                    label: request.channel.label,
                  ),
                  if (request.categoryName != null)
                    _MetaChip(
                      icon: Icons.build_circle_outlined,
                      label: request.categoryName!,
                    ),
                  if (request.priorityName != null)
                    _MetaChip(
                      icon: Icons.flag_outlined,
                      label: request.priorityName!,
                    ),
                  if (request.routeAddress != null)
                    _MetaChip(
                      icon: Icons.place_outlined,
                      label: request.routeAddress!,
                    ),
                  RouteActions(
                    destination: _serviceRequestDestination(request),
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

RouteDestination _serviceRequestDestination(ServiceRequest request) =>
    RouteDestination(
      label: '${request.displayNumber} · ${request.title}',
      address: request.routeAddress,
      latitude: request.routeLatitude,
      longitude: request.routeLongitude,
      priorityLevel: request.priorityLevel,
    );

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
