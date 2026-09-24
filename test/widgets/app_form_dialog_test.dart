import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/core/widgets/app_form_dialog.dart';

void main() {
  testWidgets('form dialog keeps rounded clipping around its content',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAppFormDialog<void>(
                context: context,
                title: 'Novo cadastro',
                child: const SizedBox(height: 120, child: Text('Conteúdo')),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(ClipRRect), findsWidgets);
    expect(find.text('Novo cadastro'), findsOneWidget);
  });
}
