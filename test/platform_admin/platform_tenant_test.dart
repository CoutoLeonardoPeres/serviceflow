import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/platform_admin/domain/platform_tenant.dart';

void main() {
  test('converte uma empresa retornada pelo painel master', () {
    final tenant = PlatformTenant.fromMap({
      'id': 'tenant-1',
      'name': 'Minha Empresa',
      'slug': 'minha-empresa',
      'status': 'active',
      'plan_key': 'business',
      'billing_status': 'trialing',
      'trial_ends_at': '2026-10-01T12:00:00Z',
      'plan_selected_at': null,
      'created_at': '2026-09-24T12:00:00Z',
      'active_users': 4,
      'active_units': 2,
    });

    expect(tenant.name, 'Minha Empresa');
    expect(tenant.plan.key, 'business');
    expect(tenant.billingStatus, 'trialing');
    expect(tenant.activeUsers, 4);
    expect(tenant.activeUnits, 2);
  });
}
