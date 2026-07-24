import 'package:intl/intl.dart';

import 'reports_snapshot.dart';

String reportsCsvFileName(ReportsSnapshot snapshot) {
  final date = DateFormat('yyyyMMdd_HHmm').format(snapshot.updatedAt);
  return 'serviceflow_relatorios_${snapshot.period.name}_$date.csv';
}

String reportsCsvContent(
  ReportsSnapshot snapshot, {
  List<CustomerReportPoint>? customerRanking,
  List<CategoryReportPoint>? categoryRanking,
  List<TechnicianReportPoint>? technicianRanking,
  String? searchQuery,
  String? detailFilterLabel,
}) {
  final updatedAt = DateFormat('dd/MM/yyyy HH:mm').format(snapshot.updatedAt);
  final selectedCustomers = customerRanking ?? snapshot.customerRanking;
  final selectedCategories = categoryRanking ?? snapshot.categoryRanking;
  final selectedTechnicians = technicianRanking ?? snapshot.technicianRanking;
  final rows = <List<String>>[
    ['indicador', 'valor', 'periodo', 'atualizado_em'],
    [
      'Clientes ativos',
      snapshot.activeCustomers.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Clientes inativos',
      snapshot.inactiveCustomers.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Chamados abertos',
      snapshot.openServiceRequests.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Agendamentos pendentes',
      snapshot.scheduledAppointments.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'OS abertas',
      snapshot.openWorkOrders.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'OS concluidas',
      snapshot.doneWorkOrders.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Orcamentos em negociacao',
      snapshot.pendingQuotations.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Orcamentos em negociacao - valor',
      _money(snapshot.pendingQuotationsCents),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Orcamentos aprovados',
      snapshot.approvedQuotations.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Orcamentos aprovados - valor',
      _money(snapshot.approvedQuotationsCents),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Financeiro em aberto',
      _money(snapshot.openReceivablesCents),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Financeiro vencido',
      _money(snapshot.overdueReceivablesCents),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Financeiro recebido',
      _money(snapshot.paidReceivablesCents),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Percentual OS concluidas',
      '${(snapshot.workOrderCompletionRate * 100).round()}%',
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Satisfacao - media',
      snapshot.satisfactionScoreLabel,
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Satisfacao - avaliacoes',
      snapshot.satisfactionCount.toString(),
      snapshot.period.label,
      updatedAt,
    ],
    [
      'Satisfacao - criticas',
      snapshot.criticalSatisfactionCount.toString(),
      snapshot.period.label,
      updatedAt,
    ],
  ];

  if ((searchQuery != null && searchQuery.trim().isNotEmpty) ||
      (detailFilterLabel != null && detailFilterLabel.trim().isNotEmpty)) {
    rows.addAll([
      [
        'Filtro - busca',
        searchQuery?.trim().isNotEmpty == true
            ? searchQuery!.trim()
            : 'sem filtro',
        snapshot.period.label,
        updatedAt,
      ],
      [
        'Filtro - situação',
        detailFilterLabel?.trim().isNotEmpty == true
            ? detailFilterLabel!.trim()
            : 'Todos',
        snapshot.period.label,
        updatedAt,
      ],
      [
        'Filtro - clientes no ranking',
        selectedCustomers.length.toString(),
        snapshot.period.label,
        updatedAt,
      ],
      [
        'Filtro - categorias no ranking',
        selectedCategories.length.toString(),
        snapshot.period.label,
        updatedAt,
      ],
      [
        'Filtro - tecnicos no ranking',
        selectedTechnicians.length.toString(),
        snapshot.period.label,
        updatedAt,
      ],
    ]);
  }

  for (final point in snapshot.monthlyTrend) {
    final month = DateFormat('MM/yyyy').format(point.month);
    rows.addAll([
      ['Mensal - chamados', point.serviceRequests.toString(), month, updatedAt],
      [
        'Mensal - OS concluidas',
        point.doneWorkOrders.toString(),
        month,
        updatedAt
      ],
      [
        'Mensal - recebido',
        _money(point.paidReceivablesCents),
        month,
        updatedAt,
      ],
    ]);
  }

  for (final customer in selectedCustomers) {
    rows.addAll([
      [
        'Cliente - chamados',
        customer.serviceRequests.toString(),
        customer.customerName,
        updatedAt,
      ],
      [
        'Cliente - OS',
        customer.workOrders.toString(),
        customer.customerName,
        updatedAt,
      ],
      [
        'Cliente - recebido',
        _money(customer.receivedCents),
        customer.customerName,
        updatedAt,
      ],
      [
        'Cliente - em aberto',
        _money(customer.openReceivablesCents),
        customer.customerName,
        updatedAt,
      ],
    ]);
  }

  for (final category in selectedCategories) {
    rows.addAll([
      [
        'Tipo de servico - chamados',
        category.totalRequests.toString(),
        category.categoryName,
        updatedAt,
      ],
      [
        'Tipo de servico - abertos',
        category.openRequests.toString(),
        category.categoryName,
        updatedAt,
      ],
      [
        'Tipo de servico - fechados',
        category.closedRequests.toString(),
        category.categoryName,
        updatedAt,
      ],
    ]);
  }

  for (final technician in selectedTechnicians) {
    rows.addAll([
      [
        'Tecnico - agendamentos',
        technician.appointments.toString(),
        technician.technicianName,
        updatedAt,
      ],
      [
        'Tecnico - apontamentos',
        technician.timeEntries.toString(),
        technician.technicianName,
        updatedAt,
      ],
      [
        'Tecnico - horas',
        technician.hoursWorked.toStringAsFixed(1),
        technician.technicianName,
        updatedAt,
      ],
    ]);
  }

  return rows.map((row) => row.map(_escapeCsv).join(';')).join('\n');
}

String _money(int cents) => (cents / 100).toStringAsFixed(2);

String _escapeCsv(String value) {
  final escaped = value.replaceAll('"', '""');
  if (escaped.contains(';') ||
      escaped.contains('\n') ||
      escaped.contains('"')) {
    return '"$escaped"';
  }
  return escaped;
}
