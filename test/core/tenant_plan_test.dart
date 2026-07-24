import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/plans/tenant_plan.dart';

void main() {
  group('resolveTenantPlan', () {
    test('retorna enterprise como fallback seguro', () {
      expect(resolveTenantPlan(null).key, enterprisePlan.key);
      expect(resolveTenantPlan('desconhecido').key, enterprisePlan.key);
    });

    test('retorna starter quando plano for starter', () {
      expect(resolveTenantPlan('starter').key, starterPlan.key);
      expect(resolveTenantPlan('starter').hasFeature(TenantFeature.reports),
          isFalse);
    });

    test('business inclui pagamentos e fiscal', () {
      final plan = resolveTenantPlan('business');

      expect(plan.hasFeature(TenantFeature.payments), isTrue);
      expect(plan.hasFeature(TenantFeature.fiscal), isTrue);
      expect(plan.userLimit, 50);
      expect(plan.unitLimit, 10);
    });
  });
}
