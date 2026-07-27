import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/stock/application/stock_notifier.dart';
import 'package:serviceflow/features/stock/domain/product.dart';
import 'package:serviceflow/features/stock/domain/stock_balance.dart';
import 'package:serviceflow/features/stock/domain/warehouse.dart';
import 'package:serviceflow/features/stock/presentation/stock_list_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  StockBalance makeBalance({
    String productId = 'p1',
    String productName = 'Cabo flexível 2.5mm',
    String? sku = 'CB-25',
    double quantity = 150,
    double minQuantity = 10,
    int totalValueCents = 45000,
    int averageUnitCostCents = 300,
    bool belowMinimum = false,
  }) =>
      StockBalance(
        productId: productId,
        productName: productName,
        sku: sku,
        unit: ProductUnit.m,
        warehouseId: 'w1',
        warehouseName: 'Depósito Central',
        quantity: quantity,
        minQuantity: minQuantity,
        totalValueCents: totalValueCents,
        averageUnitCostCents: averageUnitCostCents,
        belowMinimum: belowMinimum,
        updatedAt: DateTime.utc(2026, 7, 26),
      );

  Warehouse makeWarehouse() => Warehouse(
        id: 'w1',
        tenantId: 't1',
        name: 'Depósito Central',
        isDefault: true,
        isActive: true,
        createdAt: DateTime.utc(2026),
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<StockBalance> balances,
    int belowMinCount = 0,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stockBalancesProvider.overrideWith((ref) async => balances),
          warehousesProvider.overrideWith((ref) async => [makeWarehouse()]),
          belowMinimumCountProvider.overrideWith((ref) async => belowMinCount),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const StockListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra saldo, custo médio e valor total', (tester) async {
    await pumpScreen(tester, balances: [makeBalance()]);

    expect(find.text('CB-25 — Cabo flexível 2.5mm'), findsOneWidget);
    expect(find.text('Depósito Central'), findsWidgets);
    expect(find.text('150 m'), findsOneWidget);
    // Custo médio 300 centavos e total 45000 centavos.
    expect(find.textContaining('3,00'), findsOneWidget);
    expect(find.textContaining('450,00'), findsOneWidget);
  });

  testWidgets('oferece ações de entrada, saída e extrato', (tester) async {
    await pumpScreen(tester, balances: [makeBalance()]);

    expect(find.text('Saída'), findsOneWidget);
    expect(find.text('Extrato'), findsOneWidget);
    // "Entrada" aparece no card e no FAB.
    expect(find.text('Entrada'), findsNWidgets(2));
  });

  testWidgets('destaca item abaixo do mínimo', (tester) async {
    await pumpScreen(
      tester,
      balances: [makeBalance(quantity: 5, belowMinimum: true)],
      belowMinCount: 1,
    );

    expect(find.text('5 m'), findsOneWidget);
    expect(find.text('mín. 10'), findsOneWidget);
    expect(find.textContaining('1 item está abaixo do mínimo'), findsOneWidget);
  });

  testWidgets('banner de mínimo usa plural corretamente', (tester) async {
    await pumpScreen(
      tester,
      balances: [
        makeBalance(belowMinimum: true, quantity: 5),
        makeBalance(
          productId: 'p2',
          productName: 'Disjuntor',
          sku: 'DJ-20',
          belowMinimum: true,
          quantity: 1,
        ),
      ],
      belowMinCount: 2,
    );

    expect(
      find.textContaining('2 itens estão abaixo do mínimo'),
      findsOneWidget,
    );
  });

  testWidgets('sem itens abaixo do mínimo, não mostra o banner',
      (tester) async {
    await pumpScreen(tester, balances: [makeBalance()], belowMinCount: 0);

    expect(find.textContaining('abaixo do mínimo'), findsNothing);
  });

  testWidgets('lista vazia orienta a cadastrar produto', (tester) async {
    await pumpScreen(tester, balances: []);

    expect(
      find.textContaining('Nenhum saldo de estoque ainda'),
      findsOneWidget,
    );
    expect(find.text('Cadastrar produto'), findsOneWidget);
  });

  testWidgets('filtro de depósito mostra Todos e o depósito do tenant',
      (tester) async {
    await pumpScreen(tester, balances: [makeBalance()]);

    expect(find.widgetWithText(ChoiceChip, 'Todos'), findsOneWidget);
    expect(
      find.widgetWithText(ChoiceChip, 'Depósito Central'),
      findsOneWidget,
    );
  });
}
