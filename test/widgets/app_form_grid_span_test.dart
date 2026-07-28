import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/widgets/app_form_layout.dart';

/// Guarda o cálculo de largura do [AppFormGrid].
///
/// Existe porque um campo de duas colunas com `baseWidth * 2` fica estreito
/// demais: falta o espaçamento que existiria entre as colunas. Estreito
/// demais é o que fazia o conteúdo do dropdown estourar a célula.
void main() {
  testWidgets('campo com columns: 2 ocupa duas colunas mais o espaçamento',
      (tester) async {
    const gridWidth = 536.0;
    const spacing = 16.0;
    const minFieldWidth = 160.0;
    // 536 / 160 = 3 colunas; base = (536 - 16*2) / 3 = 168
    const expectedBase = (gridWidth - spacing * 2) / 3;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: gridWidth,
            child: AppFormGrid(
              minFieldWidth: minFieldWidth,
              spacing: spacing,
              children: const [
                AppFormFieldSpan(
                  columns: 2,
                  child: SizedBox(key: Key('largo'), height: 10),
                ),
                SizedBox(key: Key('normal'), height: 10),
              ],
            ),
          ),
        ),
      ),
    );

    final largo = tester.getSize(
      find.ancestor(
        of: find.byKey(const Key('largo')),
        matching: find.byType(SizedBox),
      ).last,
    );
    final normal = tester.getSize(
      find.ancestor(
        of: find.byKey(const Key('normal')),
        matching: find.byType(SizedBox),
      ).last,
    );

    expect(normal.width, closeTo(expectedBase, 0.01));
    expect(largo.width, closeTo(expectedBase * 2 + spacing, 0.01));

    // Os dois juntos cabem na linha, sem estourar a grade.
    expect(largo.width + spacing + normal.width, lessThanOrEqualTo(gridWidth));
  });

  testWidgets('columns maior que a grade não estoura a largura disponível',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: AppFormGrid(
              minFieldWidth: 160,
              children: const [
                AppFormFieldSpan(
                  columns: 6,
                  child: SizedBox(key: Key('exagerado'), height: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(
      find.ancestor(
        of: find.byKey(const Key('exagerado')),
        matching: find.byType(SizedBox),
      ).last,
    );
    expect(size.width, lessThanOrEqualTo(300));
  });
}
