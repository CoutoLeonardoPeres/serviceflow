import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/error_view.dart';
import '../application/customer_list_notifier.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';
import 'widgets/customer_type_chip.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  CustomerType? _typeFilter;
  bool? _activeFilter = true; // padrão: apenas ativos

  @override
  void initState() {
    super.initState();
    // Carrega na primeira vez
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerListProvider.notifier).load(
            filter: CustomerFilter(isActive: _activeFilter),
          );
    });

    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >=
          _scrollCtrl.position.maxScrollExtent - 200) {
        ref.read(customerListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _search(String value) {
    ref.read(customerListProvider.notifier).applyFilter(
          CustomerFilter(
            search: value.trim().isEmpty ? null : value.trim(),
            type: _typeFilter,
            isActive: _activeFilter,
          ),
        );
  }

  void _applyTypeFilter(CustomerType? type) {
    setState(() => _typeFilter = type);
    _search(_searchCtrl.text);
  }

  void _applyActiveFilter(bool? active) {
    setState(() => _activeFilter = active);
    _search(_searchCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(customerListProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Atualizar',
            onPressed: () =>
                ref.read(customerListProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Barra de pesquisa ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: 'Buscar por nome…',
              leading: const Icon(Icons.search_outlined),
              trailing: [
                if (_searchCtrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      _search('');
                    },
                  ),
              ],
              onChanged: _search,
            ),
          ),

          // ── Filtros em chips ───────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                // Filtro ativo/inativo
                FilterChip(
                  label: const Text('Apenas ativos'),
                  selected: _activeFilter == true,
                  onSelected: (v) => _applyActiveFilter(v ? true : null),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Inativos'),
                  selected: _activeFilter == false,
                  onSelected: (v) => _applyActiveFilter(v ? false : null),
                ),
                const SizedBox(width: 16),
                // Filtros por tipo
                ...CustomerType.values.map((type) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(type.label),
                        selected: _typeFilter == type,
                        onSelected: (v) =>
                            _applyTypeFilter(v ? type : null),
                        avatar: Icon(
                          _typeIcon(type),
                          size: 16,
                        ),
                      ),
                    )),
              ],
            ),
          ),

          // ── Contagem ───────────────────────────────────────────────────
          if (!listState.isLoading && listState.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${listState.totalCount} cliente(s)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),

          // ── Lista ──────────────────────────────────────────────────────
          Expanded(
            child: _buildBody(context, listState),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.customerNew),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Novo cliente'),
      ),
    );
  }

  Widget _buildBody(BuildContext context, CustomerListState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.items.isEmpty) {
      return ErrorView(
        message: state.error!.userMessage,
        onRetry: () =>
            ref.read(customerListProvider.notifier).refresh(),
      );
    }

    if (state.isEmpty) {
      return EmptyView(
        icon: Icons.people_outline,
        message: 'Nenhum cliente encontrado.',
        action: ElevatedButton.icon(
          onPressed: () => context.push(AppRoutes.customerNew),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Cadastrar cliente'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(customerListProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final customer = state.items[index];
          return _CustomerCard(customer: customer);
        },
      ),
    );
  }

  IconData _typeIcon(CustomerType type) => switch (type) {
        CustomerType.person => Icons.person_outline,
        CustomerType.company => Icons.business_outlined,
        CustomerType.condominium => Icons.apartment_outlined,
        CustomerType.publicEntity => Icons.account_balance_outlined,
      };
}

// ── Card de cliente ───────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.customerDetail(customer.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar com inicial
              CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                child: Text(
                  customer.name[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              // Dados
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customer.tradeName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        customer.tradeName!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CustomerTypeChip(type: customer.type),
                        if (!customer.isActive) ...[
                          const SizedBox(width: 6),
                          Chip(
                            label: const Text('Inativo'),
                            labelStyle:
                                TextStyle(color: colorScheme.onErrorContainer, fontSize: 11),
                            backgroundColor: colorScheme.errorContainer,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                        if (customer.email != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.email_outlined,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                        if (customer.phone != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.phone_outlined,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
