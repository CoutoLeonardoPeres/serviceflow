import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/core/widgets/neomorphic.dart';

void main() {
  testWidgets('neomorphic button exposes an accessible label and action',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NeomorphicButton(
            label: 'Salvar',
            icon: Icons.save_outlined,
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Salvar'), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    expect(tapped, isTrue);
  });

  testWidgets('icon well keeps a compact rounded footprint', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: NeomorphicIconWell(icon: Icons.settings_outlined),
        ),
      ),
    );

    final size = tester.getSize(find.byType(NeomorphicIconWell));
    expect(size.width, 56);
    expect(size.height, 56);
  });
}
