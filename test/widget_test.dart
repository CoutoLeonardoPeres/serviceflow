import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/main.dart';

void main() {
  testWidgets(
    'exibe a tela inicial do ServiceFlow',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ServiceFlowApp());

      expect(
        find.text('ServiceFlow'),
        findsOneWidget,
      );

      expect(
        find.text('ServiceFlow iniciado com sucesso!'),
        findsOneWidget,
      );
    },
  );
}
