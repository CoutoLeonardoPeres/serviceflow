import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/shared/providers/tenant_provider.dart';

void main() {
  test('pickActiveMembership escolhe a primeira membership ativa', () {
    final rows = [
      {
        'id': 'membership-1',
        'tenant_id': 'tenant-1',
        'status': 'active',
      },
      {
        'id': 'membership-2',
        'tenant_id': 'tenant-2',
        'status': 'active',
      },
    ];

    expect(pickActiveMembership(rows)?['tenant_id'], 'tenant-1');
  });

  test('pickActiveMembership retorna null quando nao ha empresa ativa', () {
    expect(pickActiveMembership(const []), isNull);
  });
}
