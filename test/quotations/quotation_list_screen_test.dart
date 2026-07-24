import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/quotations/presentation/quotation_list_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('QuotationListScreen mostra titulo e acao de novo orcamento',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const QuotationListScreen(),
        ),
        GoRoute(
          path: '/orcamentos/novo',
          builder: (_, __) => const Scaffold(body: Text('Novo')),
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

    expect(find.text('Orçamentos'), findsOneWidget);
    expect(find.text('Novo orçamento'), findsWidgets);
  });

  testWidgets('QuotationListScreen abre novo orcamento em popup',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const QuotationListScreen(),
        ),
        GoRoute(
          path: '/orcamentos/novo',
          builder: (_, __) => const Scaffold(body: Text('Novo')),
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

    await tester.tap(find.text('Novo orçamento').last);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Novo orçamento'), findsWidgets);
  });
}
