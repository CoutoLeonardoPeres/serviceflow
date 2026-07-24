import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:serviceflow/core/router/app_router.dart';
import 'package:serviceflow/main.dart';

void main() {
  testWidgets(
    'ServiceFlowApp renderiza rota configurada',
    (WidgetTester tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              body: Text('ServiceFlow'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
          ],
          child: const ServiceFlowApp(),
        ),
      );

      expect(
        find.text('ServiceFlow'),
        findsOneWidget,
      );
    },
  );
}
