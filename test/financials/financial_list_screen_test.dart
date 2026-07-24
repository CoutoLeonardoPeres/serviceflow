import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/financials/application/financial_list_notifier.dart';
import 'package:serviceflow/features/financials/domain/receipt.dart';
import 'package:serviceflow/features/financials/domain/receivable.dart';
import 'package:serviceflow/features/financials/presentation/financial_list_screen.dart';

void main() {
  testWidgets('FinancialListScreen mostra recebiveis e abre popup de pagamento',
      (tester) async {
    final receivable = Receivable(
      id: 'rec-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      description: 'OS #00012 - Troca de compressor',
      amountCents: 250000,
      balanceCents: 150000,
      status: ReceivableStatus.partiallyPaid,
      dueDate: DateTime(2026, 7, 30),
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
      workOrderNumber: 12,
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
          home: const FinancialListScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Financeiro'), findsWidgets);
    expect(find.text('Cliente Teste'), findsOneWidget);
    expect(find.text('Saldo em aberto'), findsOneWidget);
    expect(find.text('Registrar pagamento'), findsOneWidget);

    await tester.tap(find.text('Registrar pagamento'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Baixa manual'), findsWidgets);
    expect(find.text('Forma de pagamento'), findsOneWidget);
  });

  testWidgets('FinancialListScreen mostra acao para visualizar recibo',
      (tester) async {
    final receivable = Receivable(
      id: 'rec-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      description: 'OS #00012 - Troca de compressor',
      amountCents: 250000,
      balanceCents: 0,
      status: ReceivableStatus.paid,
      dueDate: DateTime(2026, 7, 30),
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
      customerName: 'Cliente Teste',
      workOrderNumber: 12,
      latestReceipt: Receipt(
        id: 'receipt-1',
        tenantId: 'tenant-1',
        number: 23,
        receivableId: 'rec-1',
        paymentId: 'pay-1',
        customerId: 'customer-1',
        amountCents: 250000,
        issuedAt: DateTime(2026, 7, 22),
        customerName: 'Cliente Teste',
        receivableDescription: 'OS #00012 - Troca de compressor',
        paymentMethod: 'pix_manual',
      ),
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
          home: const FinancialListScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Visualizar recibo'), findsOneWidget);
  });
}

class _FakeFinancialListNotifier extends FinancialListNotifier {
  _FakeFinancialListNotifier(this.initialState);

  final FinancialListState initialState;

  @override
  FinancialListState build() => initialState;

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}
}
