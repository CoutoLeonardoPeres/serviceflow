import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/reports_notifier.dart';
import '../domain/reports_csv_export.dart';
import '../domain/reports_snapshot.dart';
import '../../../core/files/text_file_download.dart';

enum _ReportDetailFilter {
  all('Todos'),
  open('Em aberto'),
  closed('Fechados'),
  financial('Financeiro'),
  schedule('Agenda');

  const _ReportDetailFilter(this.label);

  final String label;
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _searchQuery = '';
  _ReportDetailFilter _detailFilter = _ReportDetailFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reportsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportsProvider);
    final snapshot = state.snapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(reportsProvider.notifier).refresh(),
          ),
          IconButton(
            tooltip: 'Copiar resumo',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: snapshot == null ? null : () => _copySummary(snapshot),
          ),
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: snapshot == null ? null : () => _exportCsv(snapshot),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(reportsProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (state.isLoading && snapshot == null)
              const Padding(
                padding: EdgeInsets.only(top: 96),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null && snapshot == null)
              ErrorView(
                message:
                    state.error?.userMessage ?? 'Erro ao carregar relatorios.',
                onRetry: () => ref.read(reportsProvider.notifier).refresh(),
              )
            else
              _ReportsContent(
                snapshot: snapshot ?? ReportsSnapshot.empty(),
                searchQuery: _searchQuery,
                detailFilter: _detailFilter,
                onSearchChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                onDetailFilterChanged: (value) {
                  setState(() => _detailFilter = value);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copySummary(ReportsSnapshot snapshot) async {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final text = [
      'ServiceFlow - Relatorios (${snapshot.period.label})',
      'Clientes ativos: ${snapshot.activeCustomers}',
      'Chamados abertos: ${snapshot.openServiceRequests}',
      'Agendamentos pendentes: ${snapshot.scheduledAppointments}',
      'OS abertas: ${snapshot.openWorkOrders}',
      'OS concluidas: ${snapshot.doneWorkOrders}',
      'Satisfacao: ${snapshot.satisfactionScoreLabel} (${snapshot.satisfactionCount} avaliacoes, ${snapshot.criticalSatisfactionCount} criticas)',
      'Orcamentos em negociacao: ${snapshot.pendingQuotations} (${currency.format(snapshot.pendingQuotationsCents / 100)})',
      'Orcamentos aprovados: ${snapshot.approvedQuotations} (${currency.format(snapshot.approvedQuotationsCents / 100)})',
      'Financeiro em aberto: ${currency.format(snapshot.openReceivablesCents / 100)}',
      'Financeiro vencido: ${currency.format(snapshot.overdueReceivablesCents / 100)}',
      'Recebido: ${currency.format(snapshot.paidReceivablesCents / 100)}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resumo copiado.')),
    );
  }

  Future<void> _exportCsv(ReportsSnapshot snapshot) async {
    final filteredCustomers = _buildFilteredCustomers(
      snapshot,
      _searchQuery,
      _detailFilter,
    );
    final filteredCategories = _buildFilteredCategories(
      snapshot,
      _searchQuery,
      _detailFilter,
    );
    final filteredTechnicians = _buildFilteredTechnicians(
      snapshot,
      _searchQuery,
      _detailFilter,
    );
    await downloadTextFile(
      fileName: reportsCsvFileName(snapshot),
      content: reportsCsvContent(
        snapshot,
        customerRanking: filteredCustomers,
        categoryRanking: filteredCategories,
        technicianRanking: filteredTechnicians,
        searchQuery: _searchQuery,
        detailFilterLabel: _detailFilter.label,
      ),
      mimeType: 'text/csv;charset=utf-8',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV exportado.')),
    );
  }
}

class _ReportsContent extends StatelessWidget {
  const _ReportsContent({
    required this.snapshot,
    required this.searchQuery,
    required this.detailFilter,
    required this.onSearchChanged,
    required this.onDetailFilterChanged,
  });

  final ReportsSnapshot snapshot;
  final String searchQuery;
  final _ReportDetailFilter detailFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ReportDetailFilter> onDetailFilterChanged;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy HH:mm');
    final filteredCustomers =
        _buildFilteredCustomers(snapshot, searchQuery, detailFilter);
    final filteredCategories =
        _buildFilteredCategories(snapshot, searchQuery, detailFilter);
    final filteredTechnicians =
        _buildFilteredTechnicians(snapshot, searchQuery, detailFilter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeomorphicPanel(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 18,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.30),
                      offset: const Offset(10, 14),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.analytics_outlined,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Painel gerencial',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Atualizado em ${date.format(snapshot.updatedAt)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _PeriodSelector(selected: snapshot.period),
        const SizedBox(height: 18),
        _ReportFilterPanel(
          searchQuery: searchQuery,
          detailFilter: detailFilter,
          resultCount: filteredCustomers.length +
              filteredCategories.length +
              filteredTechnicians.length,
          onSearchChanged: onSearchChanged,
          onDetailFilterChanged: onDetailFilterChanged,
        ),
        const SizedBox(height: 18),
        const _SectionTitle(title: 'Operação'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ReportTile(
              icon: Icons.people_outline,
              label: 'Clientes ativos',
              value: snapshot.activeCustomers.toString(),
              helper: '${snapshot.inactiveCustomers} inativos',
            ),
            _ReportTile(
              icon: Icons.support_agent_outlined,
              label: 'Chamados abertos',
              value: snapshot.openServiceRequests.toString(),
              helper: 'Demandas em andamento',
            ),
            _ReportTile(
              icon: Icons.event_available_outlined,
              label: 'Agendamentos',
              value: snapshot.scheduledAppointments.toString(),
              helper: 'Ainda nao finalizados',
            ),
            _ReportTile(
              icon: Icons.engineering_outlined,
              label: 'OS abertas',
              value: snapshot.openWorkOrders.toString(),
              helper: '${snapshot.doneWorkOrders} concluidas',
            ),
            _ReportTile(
              icon: Icons.star_rate_outlined,
              label: 'Satisfação',
              value: snapshot.satisfactionScoreLabel,
              helper: snapshot.satisfactionCount == 0
                  ? 'Aguardando retorno'
                  : '${snapshot.satisfactionCount} avaliações',
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle(title: 'Orçamentos'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ReportTile(
              icon: Icons.hourglass_top_outlined,
              label: 'Em negociação',
              value: snapshot.pendingQuotations.toString(),
              helper: currency.format(snapshot.pendingQuotationsCents / 100),
            ),
            _ReportTile(
              icon: Icons.check_circle_outline,
              label: 'Aprovados',
              value: snapshot.approvedQuotations.toString(),
              helper: currency.format(snapshot.approvedQuotationsCents / 100),
            ),
            _ReportTile(
              icon: Icons.request_quote_outlined,
              label: 'Pipeline',
              value:
                  currency.format(snapshot.totalQuotationPipelineCents / 100),
              helper: 'Negociação + aprovados',
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle(title: 'Financeiro'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ReportTile(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Em aberto',
              value: currency.format(snapshot.openReceivablesCents / 100),
              helper: 'Saldo a receber',
            ),
            _ReportTile(
              icon: Icons.warning_amber_outlined,
              label: 'Vencido',
              value: currency.format(snapshot.overdueReceivablesCents / 100),
              helper: 'Atrasado',
            ),
            _ReportTile(
              icon: Icons.price_check_outlined,
              label: 'Recebido',
              value: currency.format(snapshot.paidReceivablesCents / 100),
              helper: 'Baixas registradas',
            ),
          ],
        ),
        const SizedBox(height: 22),
        _MonthlyTrendChart(snapshot: snapshot),
        const SizedBox(height: 22),
        _CustomerRanking(ranking: filteredCustomers),
        const SizedBox(height: 22),
        _CategoryRanking(ranking: filteredCategories),
        const SizedBox(height: 22),
        _TechnicianRanking(ranking: filteredTechnicians),
        const SizedBox(height: 22),
        NeomorphicPanel(
          borderRadius: 22,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                Icons.timeline_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LinearProgressIndicator(
                  value: snapshot.workOrderCompletionRate.clamp(0, 1),
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(snapshot.workOrderCompletionRate * 100).round()}% OS concluidas',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

List<CustomerReportPoint> _buildFilteredCustomers(
  ReportsSnapshot snapshot,
  String searchQuery,
  _ReportDetailFilter detailFilter,
) {
  return snapshot.customerRanking
      .where((point) =>
          _matchesText(point.customerName, point.details, searchQuery))
      .map((point) {
        final details = _filteredDetails(point.details, detailFilter);
        return CustomerReportPoint(
          customerId: point.customerId,
          customerName: point.customerName,
          serviceRequests: point.serviceRequests,
          workOrders: point.workOrders,
          receivedCents: point.receivedCents,
          openReceivablesCents: point.openReceivablesCents,
          details: details,
        );
      })
      .where((point) =>
          detailFilter == _ReportDetailFilter.all || point.details.isNotEmpty)
      .toList();
}

List<CategoryReportPoint> _buildFilteredCategories(
  ReportsSnapshot snapshot,
  String searchQuery,
  _ReportDetailFilter detailFilter,
) {
  return snapshot.categoryRanking
      .where((point) =>
          _matchesText(point.categoryName, point.details, searchQuery))
      .map((point) {
        final details = _filteredDetails(point.details, detailFilter);
        return CategoryReportPoint(
          categoryId: point.categoryId,
          categoryName: point.categoryName,
          totalRequests: point.totalRequests,
          openRequests: point.openRequests,
          closedRequests: point.closedRequests,
          details: details,
        );
      })
      .where((point) =>
          detailFilter == _ReportDetailFilter.all || point.details.isNotEmpty)
      .toList();
}

List<TechnicianReportPoint> _buildFilteredTechnicians(
  ReportsSnapshot snapshot,
  String searchQuery,
  _ReportDetailFilter detailFilter,
) {
  return snapshot.technicianRanking
      .where((point) =>
          _matchesText(point.technicianName, point.details, searchQuery))
      .map((point) {
        final details = _filteredDetails(point.details, detailFilter);
        return TechnicianReportPoint(
          technicianId: point.technicianId,
          technicianName: point.technicianName,
          appointments: point.appointments,
          timeEntries: point.timeEntries,
          minutesWorked: point.minutesWorked,
          details: details,
        );
      })
      .where((point) =>
          detailFilter == _ReportDetailFilter.all || point.details.isNotEmpty)
      .toList();
}

bool _matchesText(
  String name,
  List<ReportDetailItem> details,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  if (name.toLowerCase().contains(normalized)) return true;
  return details.any(
    (detail) =>
        detail.title.toLowerCase().contains(normalized) ||
        detail.kind.toLowerCase().contains(normalized) ||
        detail.status.toLowerCase().contains(normalized),
  );
}

List<ReportDetailItem> _filteredDetails(
  List<ReportDetailItem> details,
  _ReportDetailFilter filter,
) {
  if (filter == _ReportDetailFilter.all) return details;
  return details.where((detail) {
    final status = detail.status.toLowerCase();
    return switch (filter) {
      _ReportDetailFilter.open =>
        !{'closed', 'done', 'cancelled', 'paid', 'no_show'}.contains(status),
      _ReportDetailFilter.closed =>
        {'closed', 'done', 'cancelled', 'paid', 'no_show'}.contains(status),
      _ReportDetailFilter.financial => detail.kind == 'Financeiro',
      _ReportDetailFilter.schedule => detail.kind == 'Agenda',
      _ReportDetailFilter.all => true,
    };
  }).toList();
}

class _ReportFilterPanel extends StatelessWidget {
  const _ReportFilterPanel({
    required this.searchQuery,
    required this.detailFilter,
    required this.resultCount,
    required this.onSearchChanged,
    required this.onDetailFilterChanged,
  });

  final String searchQuery;
  final _ReportDetailFilter detailFilter;
  final int resultCount;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ReportDetailFilter> onDetailFilterChanged;

  @override
  Widget build(BuildContext context) {
    return AppFormSection(
      title: 'Filtros de análise',
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormGrid(
            minFieldWidth: 260,
            children: [
              TextFormField(
                initialValue: searchQuery,
                decoration: const InputDecoration(
                  labelText: 'Buscar nos rankings',
                  hintText: 'Cliente, técnico, chamado ou status',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: onSearchChanged,
              ),
              DropdownButtonFormField<_ReportDetailFilter>(
                initialValue: detailFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Situação',
                  prefixIcon: Icon(Icons.filter_alt_outlined),
                ),
                items: _ReportDetailFilter.values
                    .map(
                      (filter) => DropdownMenuItem(
                        value: filter,
                        child: Text(
                          filter.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onDetailFilterChanged(value);
                },
              ),
              NeomorphicInset(
                borderRadius: 18,
                child: Row(
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$resultCount resultados nos rankings',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TechnicianRanking extends StatelessWidget {
  const _TechnicianRanking({required this.ranking});

  final List<TechnicianReportPoint> ranking;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = ranking.fold<int>(
      1,
      (max, point) => point.minutesWorked > max ? point.minutesWorked : max,
    );

    return NeomorphicPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.badge_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Técnicos em campo',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Carga de agenda e horas registradas no período selecionado.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          if (ranking.isEmpty)
            const NeomorphicInset(
              child: Text('Ainda não há atividade técnica neste período.'),
            )
          else
            ...ranking.indexed.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.$1 == ranking.length - 1 ? 0 : 10,
                ),
                child: _TechnicianRankRow(
                  position: entry.$1 + 1,
                  technician: entry.$2,
                  valueFactor: entry.$2.minutesWorked / maxMinutes,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TechnicianRankRow extends StatelessWidget {
  const _TechnicianRankRow({
    required this.position,
    required this.technician,
    required this.valueFactor,
  });

  final int position;
  final TechnicianReportPoint technician;
  final double valueFactor;

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showTechnicianDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF48B7B2),
                    child: Text(
                      position.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      technician.technicianName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${technician.hoursWorked.toStringAsFixed(1)} h',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: valueFactor.clamp(0.04, 1),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NeomorphicBadge(
                    icon: Icons.event_available_outlined,
                    label: '${technician.appointments} agendas',
                  ),
                  NeomorphicBadge(
                    icon: Icons.timer_outlined,
                    label: '${technician.timeEntries} apontamentos',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTechnicianDetails(BuildContext context) {
    return showAppFormDialog<void>(
      context: context,
      title: technician.technicianName,
      maxWidth: 520,
      child: _DetailDialogBody(
        icon: Icons.badge_outlined,
        title: 'Resumo do técnico',
        details: technician.details,
        children: [
          _DetailMetric(
            icon: Icons.event_available_outlined,
            label: 'Agendamentos',
            value: technician.appointments.toString(),
          ),
          _DetailMetric(
            icon: Icons.timer_outlined,
            label: 'Apontamentos',
            value: technician.timeEntries.toString(),
          ),
          _DetailMetric(
            icon: Icons.schedule_outlined,
            label: 'Horas trabalhadas',
            value: '${technician.hoursWorked.toStringAsFixed(1)} h',
          ),
        ],
      ),
    );
  }
}

class _CategoryRanking extends StatelessWidget {
  const _CategoryRanking({required this.ranking});

  final List<CategoryReportPoint> ranking;

  @override
  Widget build(BuildContext context) {
    final maxRequests = ranking.fold<int>(
      1,
      (max, point) => point.totalRequests > max ? point.totalRequests : max,
    );

    return NeomorphicPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.category_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tipos de serviço em alta',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Categorias com mais chamados no período selecionado.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          if (ranking.isEmpty)
            const NeomorphicInset(
              child: Text('Ainda não há chamados classificados neste período.'),
            )
          else
            ...ranking.indexed.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.$1 == ranking.length - 1 ? 0 : 10,
                ),
                child: _CategoryRankRow(
                  position: entry.$1 + 1,
                  category: entry.$2,
                  valueFactor: entry.$2.totalRequests / maxRequests,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryRankRow extends StatelessWidget {
  const _CategoryRankRow({
    required this.position,
    required this.category,
    required this.valueFactor,
  });

  final int position;
  final CategoryReportPoint category;
  final double valueFactor;

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showCategoryDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    position.toString().padLeft(2, '0'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${category.totalRequests} chamados',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: valueFactor.clamp(0.04, 1),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NeomorphicBadge(
                    icon: Icons.pending_actions_outlined,
                    label: '${category.openRequests} abertos',
                  ),
                  NeomorphicBadge(
                    icon: Icons.check_circle_outline,
                    label: '${category.closedRequests} fechados',
                  ),
                  NeomorphicBadge(
                    icon: Icons.trending_up_outlined,
                    label: '${(category.openRate * 100).round()}% em aberto',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCategoryDetails(BuildContext context) {
    return showAppFormDialog<void>(
      context: context,
      title: category.categoryName,
      maxWidth: 520,
      child: _DetailDialogBody(
        icon: Icons.category_outlined,
        title: 'Resumo do tipo de serviço',
        details: category.details,
        children: [
          _DetailMetric(
            icon: Icons.support_agent_outlined,
            label: 'Chamados',
            value: category.totalRequests.toString(),
          ),
          _DetailMetric(
            icon: Icons.pending_actions_outlined,
            label: 'Abertos',
            value: category.openRequests.toString(),
          ),
          _DetailMetric(
            icon: Icons.check_circle_outline,
            label: 'Fechados',
            value: category.closedRequests.toString(),
          ),
          _DetailMetric(
            icon: Icons.trending_up_outlined,
            label: 'Em aberto',
            value: '${(category.openRate * 100).round()}%',
          ),
        ],
      ),
    );
  }
}

class _CustomerRanking extends StatelessWidget {
  const _CustomerRanking({required this.ranking});

  final List<CustomerReportPoint> ranking;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final maxValue = ranking.fold<int>(
      1,
      (max, point) => point.totalCents > max ? point.totalCents : max,
    );

    return NeomorphicPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.leaderboard_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Clientes em destaque',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ranking por recebimentos, saldo em aberto e atividade no período.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          if (ranking.isEmpty)
            const NeomorphicInset(
              child: Text('Ainda não há clientes com movimento neste período.'),
            )
          else
            ...ranking.indexed.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.$1 == ranking.length - 1 ? 0 : 10,
                ),
                child: _CustomerRankRow(
                  position: entry.$1 + 1,
                  customer: entry.$2,
                  valueLabel: currency.format(entry.$2.totalCents / 100),
                  valueFactor: entry.$2.totalCents / maxValue,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerRankRow extends StatelessWidget {
  const _CustomerRankRow({
    required this.position,
    required this.customer,
    required this.valueLabel,
    required this.valueFactor,
  });

  final int position;
  final CustomerReportPoint customer;
  final String valueLabel;
  final double valueFactor;

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showCustomerDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      position.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      customer.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    valueLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: valueFactor.clamp(0.04, 1),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  NeomorphicBadge(
                    icon: Icons.support_agent_outlined,
                    label: '${customer.serviceRequests} chamados',
                  ),
                  NeomorphicBadge(
                    icon: Icons.engineering_outlined,
                    label: '${customer.workOrders} OS',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomerDetails(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    return showAppFormDialog<void>(
      context: context,
      title: customer.customerName,
      maxWidth: 520,
      child: _DetailDialogBody(
        icon: Icons.leaderboard_outlined,
        title: 'Resumo do cliente',
        details: customer.details,
        children: [
          _DetailMetric(
            icon: Icons.support_agent_outlined,
            label: 'Chamados',
            value: customer.serviceRequests.toString(),
          ),
          _DetailMetric(
            icon: Icons.engineering_outlined,
            label: 'Ordens de serviço',
            value: customer.workOrders.toString(),
          ),
          _DetailMetric(
            icon: Icons.price_check_outlined,
            label: 'Recebido',
            value: currency.format(customer.receivedCents / 100),
          ),
          _DetailMetric(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Em aberto',
            value: currency.format(customer.openReceivablesCents / 100),
          ),
        ],
      ),
    );
  }
}

class _DetailDialogBody extends StatelessWidget {
  const _DetailDialogBody({
    required this.icon,
    required this.title,
    required this.children,
    required this.details,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final List<ReportDetailItem> details;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NeomorphicInset(
            borderRadius: 20,
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: children,
          ),
          const SizedBox(height: 18),
          Text(
            'Movimentos recentes',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          if (details.isEmpty)
            const NeomorphicInset(
              child: Text('Ainda nao ha movimentos recentes para este item.'),
            )
          else
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DetailItemRow(detail: detail),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailItemRow extends StatelessWidget {
  const _DetailItemRow({required this.detail});

  final ReportDetailItem detail;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date =
        detail.date == null ? 'Sem data' : dateFormat.format(detail.date!);
    final amount = detail.amountCents == null
        ? null
        : currency.format(detail.amountCents! / 100);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _iconForDetailKind(detail.kind),
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _DetailPill(label: detail.kind),
                  _DetailPill(label: detail.status),
                  _DetailPill(label: date),
                  if (amount != null) _DetailPill(label: amount),
                ],
              ),
            ],
          ),
        ),
        if (detail.routePath != null) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.open_in_new,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );

    return NeomorphicInset(
      borderRadius: 18,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: detail.routePath == null
            ? null
            : () {
                final routePath = detail.routePath!;
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    context.go(routePath);
                  }
                });
              },
        child: content,
      ),
    );
  }

  IconData _iconForDetailKind(String kind) {
    return switch (kind) {
      'Chamado' => Icons.support_agent_outlined,
      'OS' => Icons.engineering_outlined,
      'Financeiro' => Icons.account_balance_wallet_outlined,
      'Agenda' => Icons.event_available_outlined,
      'Horas' => Icons.timer_outlined,
      _ => Icons.insights_outlined,
    };
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
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
      child: NeomorphicPanel(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
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

class _MonthlyTrendChart extends StatelessWidget {
  const _MonthlyTrendChart({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.compactSimpleCurrency(locale: 'pt_BR');
    final month = DateFormat('MMM');
    final points = snapshot.monthlyTrend;
    final maxActivity = points.fold<int>(
      1,
      (max, point) => [
        max,
        point.serviceRequests,
        point.doneWorkOrders,
      ].reduce((a, b) => a > b ? a : b),
    );
    final maxPaid = points.fold<int>(
      1,
      (max, point) =>
          point.paidReceivablesCents > max ? point.paidReceivablesCents : max,
    );

    return NeomorphicPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tendência mensal',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Chamados, OS concluídas e recebimentos no período selecionado.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          if (points.isEmpty)
            const NeomorphicInset(
              child: Text('Ainda não há dados mensais para este período.'),
            )
          else
            SizedBox(
              height: 210,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: points
                    .map(
                      (point) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: _MonthlyBarGroup(
                            label: month.format(point.month),
                            requestsHeight: point.serviceRequests / maxActivity,
                            workOrdersHeight:
                                point.doneWorkOrders / maxActivity,
                            paidHeight: point.paidReceivablesCents / maxPaid,
                            tooltip:
                                '${point.serviceRequests} chamados · ${point.doneWorkOrders} OS · ${currency.format(point.paidReceivablesCents / 100)}',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _LegendDot(color: Color(0xFF6C63FF), label: 'Chamados'),
              _LegendDot(color: Color(0xFF48B7B2), label: 'OS'),
              _LegendDot(color: Color(0xFFB04E7B), label: 'Recebido'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyBarGroup extends StatelessWidget {
  const _MonthlyBarGroup({
    required this.label,
    required this.requestsHeight,
    required this.workOrdersHeight,
    required this.paidHeight,
    required this.tooltip,
  });

  final String label;
  final double requestsHeight;
  final double workOrdersHeight;
  final double paidHeight;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Bar(color: const Color(0xFF6C63FF), value: requestsHeight),
                const SizedBox(width: 4),
                _Bar(color: const Color(0xFF48B7B2), value: workOrdersHeight),
                const SizedBox(width: 4),
                _Bar(color: const Color(0xFFB04E7B), value: paidHeight),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.value});

  final Color color;
  final double value;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: value.clamp(0.04, 1),
      child: Container(
        width: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.30),
              offset: const Offset(4, 8),
              blurRadius: 12,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector({required this.selected});

  final ReportsPeriod selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NeomorphicPanel(
      borderRadius: 22,
      padding: const EdgeInsets.all(12),
      child: SegmentedButton<ReportsPeriod>(
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (values) {
          ref.read(reportsProvider.notifier).changePeriod(values.first);
        },
        segments: ReportsPeriod.values
            .map(
              (period) => ButtonSegment<ReportsPeriod>(
                value: period,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(period.label),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: NeomorphicPanel(
        borderRadius: 22,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              helper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
