import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/features/work_orders/data/work_order_repository.dart';
import 'package:serviceflow/features/work_orders/application/work_order_list_notifier.dart';
import 'package:serviceflow/features/work_orders/domain/satisfaction_public_context.dart';
import 'package:serviceflow/features/work_orders/presentation/satisfaction_public_screen.dart';

/// Repositório falso — a tela pública não deve tocar em Supabase nos testes.
class _FakeWorkOrderRepository implements WorkOrderRepository {
  _FakeWorkOrderRepository({
    required this.context,
    this.shouldFailContext = false,
  });

  final SatisfactionPublicContext context;
  final bool shouldFailContext;

  int submitCalls = 0;
  int? lastRating;
  String? lastToken;
  String? lastContactName;
  String? lastComment;

  @override
  Future<SatisfactionPublicContext> getPublicSatisfactionContext(
    String token,
  ) async {
    if (shouldFailContext) {
      throw Exception('Link inválido');
    }
    return context;
  }

  @override
  Future<void> submitPublicSatisfaction({
    required String token,
    required int rating,
    String? contactName,
    String? comment,
  }) async {
    submitCalls++;
    lastToken = token;
    lastRating = rating;
    lastContactName = contactName;
    lastComment = comment;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  SatisfactionPublicContext makeContext({
    bool alreadyAnswered = false,
    int? currentRating,
  }) =>
      SatisfactionPublicContext(
        workOrderNumber: 42,
        serviceTitle: 'Troca de compressor',
        companyName: 'Eletroceu',
        alreadyAnswered: alreadyAnswered,
        completedAt: DateTime.utc(2026, 7, 25),
        currentRating: currentRating,
      );

  /// Monta a tela numa viewport alta o bastante para o formulário inteiro.
  ///
  /// Na viewport padrão de teste (800x600) o botão "Enviar avaliação" fica fora
  /// da tela e `tap()` não acerta o alvo — o teste passaria a testar nada.
  Future<void> pumpScreen(
    WidgetTester tester,
    _FakeWorkOrderRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SatisfactionPublicScreen(token: 'tok-123'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra contexto mínimo da OS e as 5 estrelas', (tester) async {
    final repo = _FakeWorkOrderRepository(context: makeContext());

    await pumpScreen(tester, repo);

    expect(find.text('Eletroceu'), findsOneWidget);
    expect(find.text('Como foi o nosso atendimento?'), findsOneWidget);
    expect(find.text('OS 42 — Troca de compressor'), findsOneWidget);
    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
    expect(find.text('Enviar avaliação'), findsOneWidget);
  });

  testWidgets('selecionar estrela mostra o rótulo da nota', (tester) async {
    final repo = _FakeWorkOrderRepository(context: makeContext());

    await pumpScreen(tester, repo);

    // Quarta estrela → nota 4.
    await tester.tap(find.byIcon(Icons.star_outline_rounded).at(3));
    await tester.pumpAndSettle();

    expect(find.text('Satisfeito'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
  });

  testWidgets('enviar sem escolher nota não chama o repositório',
      (tester) async {
    final repo = _FakeWorkOrderRepository(context: makeContext());

    await pumpScreen(tester, repo);

    await tester.tap(find.text('Enviar avaliação'));
    await tester.pumpAndSettle();

    expect(repo.submitCalls, 0);
    expect(find.text('Escolha uma nota de 1 a 5.'), findsOneWidget);
  });

  testWidgets('envia nota e comentário e mostra agradecimento', (tester) async {
    final repo = _FakeWorkOrderRepository(context: makeContext());

    await pumpScreen(tester, repo);

    await tester.tap(find.byIcon(Icons.star_outline_rounded).at(4));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Seu nome (opcional)'),
      'Maria',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Quer contar mais alguma coisa? (opcional)',
      ),
      'Atendimento rápido.',
    );

    await tester.tap(find.text('Enviar avaliação'));
    await tester.pumpAndSettle();

    expect(repo.submitCalls, 1);
    expect(repo.lastToken, 'tok-123');
    expect(repo.lastRating, 5);
    expect(repo.lastContactName, 'Maria');
    expect(repo.lastComment, 'Atendimento rápido.');

    expect(find.text('Obrigado pela sua avaliação!'), findsOneWidget);
    expect(find.text('Enviar avaliação'), findsNothing);
  });

  testWidgets('campos opcionais em branco viram null', (tester) async {
    final repo = _FakeWorkOrderRepository(context: makeContext());

    await pumpScreen(tester, repo);

    await tester.tap(find.byIcon(Icons.star_outline_rounded).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar avaliação'));
    await tester.pumpAndSettle();

    expect(repo.lastRating, 1);
    expect(repo.lastContactName, isNull);
    expect(repo.lastComment, isNull);
  });

  testWidgets('avisa quando a pesquisa já foi respondida', (tester) async {
    final repo = _FakeWorkOrderRepository(
      context: makeContext(alreadyAnswered: true, currentRating: 3),
    );

    await pumpScreen(tester, repo);

    expect(
      find.textContaining('Você já respondeu esta pesquisa'),
      findsOneWidget,
    );
    // Ainda permite corrigir a resposta.
    expect(find.text('Enviar avaliação'), findsOneWidget);
  });

  testWidgets('token inválido mostra mensagem de erro', (tester) async {
    final repo = _FakeWorkOrderRepository(
      context: makeContext(),
      shouldFailContext: true,
    );

    await pumpScreen(tester, repo);

    expect(
      find.text('Link inválido, expirado ou indisponível.'),
      findsOneWidget,
    );
    expect(find.text('Enviar avaliação'), findsNothing);
  });
}
