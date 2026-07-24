import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/dashboard/presentation/dashboard_screen.dart';
import 'package:serviceflow/features/financials/application/financial_list_notifier.dart';
import 'package:serviceflow/features/financials/domain/receivable.dart';

void main() {
  testWidgets('DashboardScreen mostra resumo financeiro minimo',
      (tester) async {
    final receivable = Receivable(
      id: 'rec-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      description: 'OS #00012',
      amountCents: 250000,
      balanceCents: 150000,
      status: ReceivableStatus.partiallyPaid,
      dueDate: DateTime(2026, 7, 30),
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financialListProvider.overrideWith(
            () => _FakeFinancialListNotifier(
              FinancialListState(items: [receivable], totalCount: 1),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Resumo financeiro'), findsOneWidget);
    expect(find.text('Saldo em aberto'), findsOneWidget);
    expect(find.text('Financeiro'), findsWidgets);
  });
}

class _FakeFinancialListNotifier extends FinancialListNotifier {
  _FakeFinancialListNotifier(this.initialState);

  final FinancialListState initialState;

  @override
  FinancialListState build() => initialState;

  @override
  Future<void> load() async {}
}
