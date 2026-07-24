import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:serviceflow/features/auth/presentation/login_screen.dart';
import 'package:serviceflow/features/auth/application/auth_notifier.dart';
import 'package:serviceflow/core/widgets/neomorphic.dart';
import 'package:serviceflow/core/theme/app_theme.dart';

/// Helper: envolve o widget em MaterialApp + GoRouter + ProviderScope para teste.
Widget _wrapInApp(Widget child, {List<Override> overrides = const []}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => child),
      GoRoute(
          path: '/esqueci-senha',
          builder: (_, __) => const Scaffold(body: Text('Esqueci senha'))),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
    ),
  );
}

/// O formulário de login fica dentro de um SingleChildScrollView; no
/// tamanho de tela padrão do flutter_test (800x600) o botão "Entrar" pode
/// ficar fora da área visível, fazendo tester.tap() "errar" o alvo (o
/// widget existe na árvore, mas seu Offset renderizado cai fora do
/// viewport). Aumentamos o viewport antes do pump para evitar isso.
void _enlargeTestViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('LoginScreen — estrutura', () {
    testWidgets('exibe campos de e-mail e senha', (tester) async {
      _enlargeTestViewport(tester);
      await tester.pumpWidget(_wrapInApp(const LoginScreen()));
      await tester.pump();

      expect(find.text('E-mail'), findsOneWidget);
      expect(find.text('Senha'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('Esqueci minha senha'), findsOneWidget);
      expect(find.byType(NeomorphicPanel), findsWidgets);
    });

    testWidgets('exibe erro ao tentar submeter com campos vazios',
        (tester) async {
      _enlargeTestViewport(tester);
      await tester.pumpWidget(_wrapInApp(const LoginScreen()));
      await tester.pump();

      await tester.tap(find.text('Entrar'));
      await tester.pump();

      expect(find.text('Informe o e-mail.'), findsOneWidget);
      expect(find.text('Informe a senha.'), findsOneWidget);
    });

    testWidgets('rejeita e-mail inválido', (tester) async {
      _enlargeTestViewport(tester);
      await tester.pumpWidget(_wrapInApp(const LoginScreen()));
      await tester.pump();

      await tester.enterText(
        find.byType(TextFormField).first,
        'nao-e-email',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pump();

      expect(find.text('E-mail inválido.'), findsOneWidget);
    });

    testWidgets('botão desabilitado durante loading', (tester) async {
      _enlargeTestViewport(tester);
      // Override para manter estado Loading
      final container = ProviderContainer(overrides: [
        authNotifierProvider.overrideWith(() => _LoadingAuthNotifier()),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const LoginScreen(),
          ),
        ),
      );
      await tester.pump();

      final elevatedButton = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(elevatedButton.onPressed, isNull);

      container.dispose();
    });
  });
}

/// Notifier falso que sempre fica em Loading.
class _LoadingAuthNotifier extends AuthNotifier {
  @override
  AuthActionState build() => const AuthActionLoading();
}
