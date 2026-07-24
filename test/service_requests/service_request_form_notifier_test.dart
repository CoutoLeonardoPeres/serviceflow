import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:serviceflow/core/error/app_error.dart';
import 'package:serviceflow/features/service_requests/application/service_request_form_notifier.dart';
import 'package:serviceflow/features/service_requests/application/service_request_list_notifier.dart';
import 'package:serviceflow/features/service_requests/data/service_request_repository.dart';
import 'package:serviceflow/features/service_requests/domain/service_request.dart';

class _FakeServiceRequestRepository extends ServiceRequestRepository {
  _FakeServiceRequestRepository({
    this.created,
    this.error,
  }) : super(null);

  final ServiceRequest? created;
  final Object? error;
  ServiceRequest? lastCreateInput;

  @override
  Future<ServiceRequest> create(ServiceRequest request) async {
    lastCreateInput = request;
    if (error != null) throw error!;
    return created!;
  }
}

ServiceRequest _request({
  String id = 'sr-001',
  String title = 'Disjuntor desarmando',
}) =>
    ServiceRequest(
      id: id,
      tenantId: 'tenant-001',
      number: 12,
      customerId: 'customer-001',
      title: title,
      description: 'Cliente relata queda intermitente de energia.',
      channel: ServiceRequestChannel.phone,
      status: ServiceRequestStatus.opened,
      createdAt: DateTime(2026, 7, 21),
      updatedAt: DateTime(2026, 7, 21),
    );

void main() {
  ProviderContainer makeContainer(ServiceRequestRepository repo) =>
      ProviderContainer(
        overrides: [
          serviceRequestRepositoryProvider.overrideWithValue(repo),
          serviceRequestListProvider
              .overrideWith(ServiceRequestListNotifier.new),
        ],
      );

  group('ServiceRequestFormNotifier', () {
    test('comeca em idle', () {
      final container = makeContainer(
        _FakeServiceRequestRepository(created: _request()),
      );
      addTearDown(container.dispose);

      expect(
        container.read(serviceRequestFormProvider),
        isA<ServiceRequestFormIdle>(),
      );
    });

    test('cria chamado com campos normalizados e estado de sucesso', () async {
      final repo = _FakeServiceRequestRepository(created: _request());
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(serviceRequestFormProvider.notifier).createRequest(
            customerId: 'customer-001',
            title: '  Disjuntor desarmando  ',
            description: '  Cliente relata queda intermitente de energia.  ',
            channel: ServiceRequestChannel.phone,
          );

      final state = container.read(serviceRequestFormProvider);
      expect(state, isA<ServiceRequestFormSuccess>());
      expect((state as ServiceRequestFormSuccess).isCreate, isTrue);
      expect(repo.lastCreateInput?.title, 'Disjuntor desarmando');
      expect(
        repo.lastCreateInput?.description,
        'Cliente relata queda intermitente de energia.',
      );
      expect(repo.lastCreateInput?.status, ServiceRequestStatus.opened);
    });

    test('falha de permissao vira estado de erro', () async {
      final repo = _FakeServiceRequestRepository(
        error: const PermissionError(
          'Voce nao tem permissao para criar chamados.',
        ),
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(serviceRequestFormProvider.notifier).createRequest(
            customerId: 'customer-001',
            title: 'Disjuntor desarmando',
            description: 'Cliente relata queda intermitente de energia.',
            channel: ServiceRequestChannel.phone,
          );

      final state = container.read(serviceRequestFormProvider);
      expect(state, isA<ServiceRequestFormError>());
      expect((state as ServiceRequestFormError).error, isA<PermissionError>());
    });
  });
}
