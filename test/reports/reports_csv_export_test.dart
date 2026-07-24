import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/reports/domain/reports_csv_export.dart';
import 'package:serviceflow/features/reports/domain/reports_snapshot.dart';

void main() {
  test('reportsCsvContent gera CSV com indicadores principais', () {
    final snapshot = ReportsSnapshot(
      period: ReportsPeriod.currentMonth,
      monthlyTrend: [
        MonthlyReportPoint(
          month: DateTime(2026, 7),
          serviceRequests: 2,
          doneWorkOrders: 1,
          paidReceivablesCents: 99000,
        ),
      ],
      customerRanking: const [
        CustomerReportPoint(
          customerId: 'customer-1',
          customerName: 'Cliente A',
          serviceRequests: 2,
          workOrders: 1,
          receivedCents: 99000,
          openReceivablesCents: 25000,
        ),
      ],
      categoryRanking: const [
        CategoryReportPoint(
          categoryId: 'category-1',
          categoryName: 'Elétrica',
          totalRequests: 4,
          openRequests: 3,
          closedRequests: 1,
        ),
      ],
      technicianRanking: const [
        TechnicianReportPoint(
          technicianId: 'tech-1',
          technicianName: 'Ana Técnica',
          appointments: 3,
          timeEntries: 2,
          minutesWorked: 150,
        ),
      ],
      totalCustomers: 8,
      activeCustomers: 6,
      openServiceRequests: 2,
      scheduledAppointments: 3,
      pendingQuotations: 1,
      pendingQuotationsCents: 12345,
      approvedQuotations: 2,
      approvedQuotationsCents: 67890,
      openWorkOrders: 4,
      doneWorkOrders: 6,
      openReceivablesCents: 25000,
      overdueReceivablesCents: 10000,
      paidReceivablesCents: 99000,
      satisfactionCount: 3,
      averageSatisfaction: 4.333,
      criticalSatisfactionCount: 1,
      updatedAt: DateTime(2026, 7, 22, 14, 30),
    );

    final csv = reportsCsvContent(snapshot);

    expect(csv, contains('indicador;valor;periodo;atualizado_em'));
    expect(csv, contains('Clientes ativos;6;Mês atual;22/07/2026 14:30'));
    expect(
        csv, contains('Financeiro recebido;990.00;Mês atual;22/07/2026 14:30'));
    expect(csv,
        contains('Percentual OS concluidas;60%;Mês atual;22/07/2026 14:30'));
    expect(
        csv, contains('Satisfacao - media;4.3/5;Mês atual;22/07/2026 14:30'));
    expect(csv, contains('Satisfacao - criticas;1;Mês atual;22/07/2026 14:30'));
    expect(csv, contains('Mensal - recebido;990.00;07/2026;22/07/2026 14:30'));
    expect(
        csv, contains('Cliente - recebido;990.00;Cliente A;22/07/2026 14:30'));
    expect(csv,
        contains('Tipo de servico - chamados;4;Elétrica;22/07/2026 14:30'));
    expect(csv, contains('Tecnico - horas;2.5;Ana Técnica;22/07/2026 14:30'));
  });

  test('reportsCsvContent respeita rankings e filtros ativos informados', () {
    final snapshot = ReportsSnapshot(
      period: ReportsPeriod.currentMonth,
      monthlyTrend: const [],
      customerRanking: const [
        CustomerReportPoint(
          customerId: 'customer-1',
          customerName: 'Cliente A',
          serviceRequests: 2,
          workOrders: 1,
          receivedCents: 99000,
          openReceivablesCents: 25000,
        ),
        CustomerReportPoint(
          customerId: 'customer-2',
          customerName: 'Cliente B',
          serviceRequests: 1,
          workOrders: 0,
          receivedCents: 0,
          openReceivablesCents: 15000,
        ),
      ],
      categoryRanking: const [
        CategoryReportPoint(
          categoryId: 'category-1',
          categoryName: 'Elétrica',
          totalRequests: 4,
          openRequests: 3,
          closedRequests: 1,
        ),
        CategoryReportPoint(
          categoryId: 'category-2',
          categoryName: 'Hidráulica',
          totalRequests: 2,
          openRequests: 1,
          closedRequests: 1,
        ),
      ],
      technicianRanking: const [
        TechnicianReportPoint(
          technicianId: 'tech-1',
          technicianName: 'Ana Técnica',
          appointments: 3,
          timeEntries: 2,
          minutesWorked: 150,
        ),
        TechnicianReportPoint(
          technicianId: 'tech-2',
          technicianName: 'Bruno Técnico',
          appointments: 1,
          timeEntries: 1,
          minutesWorked: 60,
        ),
      ],
      totalCustomers: 8,
      activeCustomers: 6,
      openServiceRequests: 2,
      scheduledAppointments: 3,
      pendingQuotations: 1,
      pendingQuotationsCents: 12345,
      approvedQuotations: 2,
      approvedQuotationsCents: 67890,
      openWorkOrders: 4,
      doneWorkOrders: 6,
      openReceivablesCents: 25000,
      overdueReceivablesCents: 10000,
      paidReceivablesCents: 99000,
      satisfactionCount: 3,
      averageSatisfaction: 4.333,
      criticalSatisfactionCount: 1,
      updatedAt: DateTime(2026, 7, 22, 14, 30),
    );

    final csv = reportsCsvContent(
      snapshot,
      customerRanking: const [
        CustomerReportPoint(
          customerId: 'customer-1',
          customerName: 'Cliente A',
          serviceRequests: 2,
          workOrders: 1,
          receivedCents: 99000,
          openReceivablesCents: 25000,
        ),
      ],
      categoryRanking: const [
        CategoryReportPoint(
          categoryId: 'category-2',
          categoryName: 'Hidráulica',
          totalRequests: 2,
          openRequests: 1,
          closedRequests: 1,
        ),
      ],
      technicianRanking: const [
        TechnicianReportPoint(
          technicianId: 'tech-1',
          technicianName: 'Ana Técnica',
          appointments: 3,
          timeEntries: 2,
          minutesWorked: 150,
        ),
      ],
      searchQuery: 'Ana',
      detailFilterLabel: 'Agenda',
    );

    expect(csv, contains('Filtro - busca;Ana;Mês atual;22/07/2026 14:30'));
    expect(
        csv, contains('Filtro - situação;Agenda;Mês atual;22/07/2026 14:30'));
    expect(csv,
        contains('Filtro - clientes no ranking;1;Mês atual;22/07/2026 14:30'));
    expect(
        csv, contains('Cliente - recebido;990.00;Cliente A;22/07/2026 14:30'));
    expect(csv,
        isNot(contains('Cliente - recebido;0.00;Cliente B;22/07/2026 14:30')));
    expect(csv,
        contains('Tipo de servico - chamados;2;Hidráulica;22/07/2026 14:30'));
    expect(
        csv,
        isNot(contains(
            'Tipo de servico - chamados;4;Elétrica;22/07/2026 14:30')));
    expect(csv, contains('Tecnico - horas;2.5;Ana Técnica;22/07/2026 14:30'));
    expect(csv,
        isNot(contains('Tecnico - horas;1.0;Bruno Técnico;22/07/2026 14:30')));
  });

  test('reportsCsvFileName inclui periodo e data', () {
    final snapshot = ReportsSnapshot.empty(
      period: ReportsPeriod.currentYear,
      updatedAt: DateTime(2026, 7, 22, 14, 30),
    );

    expect(
      reportsCsvFileName(snapshot),
      'serviceflow_relatorios_currentYear_20260722_1430.csv',
    );
  });
}
