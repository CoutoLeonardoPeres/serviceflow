import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/service_requests/domain/service_request.dart';

void main() {
  group('ServiceRequestStatus', () {
    test('fromValue e value sao simetricos', () {
      for (final status in ServiceRequestStatus.values) {
        expect(ServiceRequestStatus.fromValue(status.value), status);
      }
    });

    test('fromValue com valor desconhecido lanca ArgumentError', () {
      expect(
        () => ServiceRequestStatus.fromValue('invalid'),
        throwsArgumentError,
      );
    });

    test('identifica estados terminais', () {
      expect(ServiceRequestStatus.cancelled.isTerminal, isTrue);
      expect(ServiceRequestStatus.closed.isTerminal, isTrue);
      expect(ServiceRequestStatus.opened.isTerminal, isFalse);
    });
  });

  group('ServiceRequest', () {
    test('toInsertPayload omite tenant_id, number e metadados server-side', () {
      final request = ServiceRequest(
        id: 'sr-001',
        tenantId: 'tenant-001',
        number: 42,
        customerId: 'customer-001',
        title: 'Ar-condicionado sem refrigerar',
        description: 'Cliente relata baixa eficiencia apos limpeza.',
        channel: ServiceRequestChannel.whatsapp,
        status: ServiceRequestStatus.opened,
        createdAt: DateTime(2026, 7, 21),
        updatedAt: DateTime(2026, 7, 21),
        createdBy: 'user-001',
      );

      final payload = request.toInsertPayload();

      expect(payload['customer_id'], 'customer-001');
      expect(payload['title'], 'Ar-condicionado sem refrigerar');
      expect(payload['channel'], 'whatsapp');
      expect(payload.containsKey('tenant_id'), isFalse);
      expect(payload.containsKey('number'), isFalse);
      expect(payload.containsKey('created_by'), isFalse);
      expect(payload.containsKey('updated_at'), isFalse);
    });
  });
}
