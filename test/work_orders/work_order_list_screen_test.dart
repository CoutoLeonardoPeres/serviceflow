import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/work_orders/presentation/work_order_list_screen.dart';

void main() {
  testWidgets('WorkOrderListScreen mostra titulo e acao de nova OS',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const WorkOrderListScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ordens de serviço'), findsOneWidget);
    expect(find.text('Nova OS'), findsWidgets);
  });

  testWidgets('WorkOrderListScreen abre nova OS em popup', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const WorkOrderListScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Nova OS').last);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Nova OS'), findsWidgets);
    expect(find.text('Cliente *'), findsOneWidget);
  });
}
