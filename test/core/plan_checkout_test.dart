import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/plans/plan_checkout.dart';

void main() {
  test('buildAppHashReturnUri monta rota hash com query', () {
    final uri = buildAppHashReturnUri(
      '/assinatura',
      queryParameters: {'checkout': 'success', 'plan': 'business'},
    );

    expect(uri.fragment, '/assinatura?checkout=success&plan=business');
  });

  test(
    'buildPlanCheckoutLink retorna null quando checkout nao estiver configurado',
    () {
      final link = buildPlanCheckoutLink(
        planKey: 'business',
        checkoutSessionId: 'session-123',
        tenantSlug: 'acme',
        source: 'test',
      );

      expect(link, isNull);
    },
  );
}
