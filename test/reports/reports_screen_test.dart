import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/reports/application/reports_notifier.dart';
import 'package:serviceflow/features/reports/domain/reports_snapshot.dart';
import 'package:serviceflow/features/reports/presentation/reports_screen.dart';

void main() {
  testWidgets('ReportsScreen mostra indicadores gerenciais', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final snapshot = ReportsSnapshot(
      period: ReportsPeriod.last30Days,
      monthlyTrend: [
        MonthlyReportPoint(
          month: DateTime(2026, 7),
          serviceRequests: 4,
          doneWorkOrders: 2,
          paidReceivablesCents: 120000,
        ),
      ],
      customerRanking: [
        CustomerReportPoint(
          customerId: 'customer-1',
          customerName: 'Cliente Campeão',
          serviceRequests: 3,
          workOrders: 2,
          receivedCents: 150000,
          openReceivablesCents: 50000,
          details: [
            ReportDetailItem(
              kind: 'Chamado',
              title: '#42 · Manutenção preventiva',
              status: 'open',
              date: DateTime(2026, 7, 21),
              routePath: '/chamados/request-42',
            ),
          ],
        ),
      ],
      categoryRanking: [
        CategoryReportPoint(
          categoryId: 'category-1',
          categoryName: 'Ar-condicionado',
          totalRequests: 7,
          openRequests: 5,
          closedRequests: 2,
          details: [
            ReportDetailItem(
              kind: 'Chamado',
              title: '#18 · Ar não refrigera',
              status: 'closed',
              date: DateTime(2026, 7, 20),
              routePath: '/chamados/request-18',
            ),
          ],
        ),
      ],
      technicianRanking: [
        TechnicianReportPoint(
          technicianId: 'tech-1',
          technicianName: 'Ana Técnica',
          appointments: 4,
          timeEntries: 3,
          minutesWorked: 390,
          details: [
            ReportDetailItem(
              kind: 'Horas',
              title: '2.0 h registradas',
              status: 'apontado',
              date: DateTime(2026, 7, 19),
              routePath: '/ordens-servico/work-order-1',
            ),
          ],
        ),
      ],
      totalCustomers: 12,
      activeCustomers: 10,
      openServiceRequests: 4,
      scheduledAppointments: 3,
      pendingQuotations: 2,
      pendingQuotationsCents: 125000,
      approvedQuotations: 1,
      approvedQuotationsCents: 90000,
      openWorkOrders: 5,
      doneWorkOrders: 15,
      openReceivablesCents: 160000,
      overdueReceivablesCents: 40000,
      paidReceivablesCents: 320000,
      satisfactionCount: 4,
      averageSatisfaction: 4.5,
      criticalSatisfactionCount: 1,
      updatedAt: DateTime(2026, 7, 22, 14, 30),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportsProvider.overrideWith(
            () => _FakeReportsNotifier(
              ReportsState(snapshot: snapshot),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ReportsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Relatórios'), findsWidgets);
    expect(find.text('Painel gerencial'), findsOneWidget);
    expect(find.text('Clientes ativos'), findsOneWidget);
    expect(find.text('Chamados abertos'), findsOneWidget);
    expect(find.text('OS abertas'), findsOneWidget);
    expect(find.text('Satisfação'), findsOneWidget);
    expect(find.text('4.5/5'), findsOneWidget);
    expect(find.text('Financeiro'), findsOneWidget);
    expect(find.text('Tendência mensal'), findsOneWidget);
    expect(find.text('Clientes em destaque'), findsOneWidget);
    expect(find.text('Cliente Campeão'), findsOneWidget);
    expect(find.text('Tipos de serviço em alta'), findsOneWidget);
    expect(find.text('Ar-condicionado'), findsOneWidget);
    expect(find.text('Técnicos em campo'), findsOneWidget);
    expect(find.text('Ana Técnica'), findsOneWidget);
    expect(find.text('Chamados'), findsOneWidget);
    expect(find.text('75% OS concluidas'), findsOneWidget);
    expect(find.text('30 dias'), findsOneWidget);
    expect(find.text('Filtros de análise'), findsOneWidget);
    expect(find.text('3 resultados nos rankings'), findsOneWidget);
    expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);
    expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Ana');
    await tester.pump();
    expect(find.text('Ana Técnica'), findsOneWidget);
    expect(find.text('Cliente Campeão'), findsNothing);

    await tester.enterText(find.byType(TextFormField), '');
    await tester.pump();

    await tester.ensureVisible(find.text('Cliente Campeão'));
    await tester.tap(find.text('Cliente Campeão'));
    await tester.pumpAndSettle();
    expect(find.text('Resumo do cliente'), findsOneWidget);
    expect(find.text('Movimentos recentes'), findsOneWidget);
    expect(find.text('#42 · Manutenção preventiva'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Ar-condicionado'));
    await tester.tap(find.text('Ar-condicionado'));
    await tester.pumpAndSettle();
    expect(find.text('Resumo do tipo de serviço'), findsOneWidget);
    expect(find.text('#18 · Ar não refrigera'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Ana Técnica'));
    await tester.tap(find.text('Ana Técnica'));
    await tester.pumpAndSettle();
    expect(find.text('Resumo do técnico'), findsOneWidget);
    expect(find.text('2.0 h registradas'), findsOneWidget);
  });
}

class _FakeReportsNotifier extends ReportsNotifier {
  _FakeReportsNotifier(this.initialState);

  final ReportsState initialState;

  @override
  ReportsState build() => initialState;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}
}
