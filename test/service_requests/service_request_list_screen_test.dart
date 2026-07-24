import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/customers/application/customer_list_notifier.dart';
import 'package:serviceflow/features/customers/data/customer_repository.dart';
import 'package:serviceflow/features/customers/domain/customer.dart';
import 'package:serviceflow/features/service_requests/application/service_request_list_notifier.dart';
import 'package:serviceflow/features/service_requests/data/service_request_repository.dart';
import 'package:serviceflow/features/service_requests/domain/service_request.dart';
import 'package:serviceflow/features/service_requests/presentation/service_request_list_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeServiceRequestRepository extends ServiceRequestRepository {
  _FakeServiceRequestRepository() : super(null);

  @override
  Future<({List<ServiceRequest> items, int totalCount})> listPaged({
    ServiceRequestFilter filter = const ServiceRequestFilter(),
    int page = 0,
  }) async =>
      (items: <ServiceRequest>[], totalCount: 0);
}

class _NoopSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository() : super(_NoopSupabaseClient());

  @override
  Future<({List<Customer> items, int totalCount})> listPaged({
    CustomerFilter filter = const CustomerFilter(),
    int page = 0,
  }) async {
    if (page > 0) return (items: <Customer>[], totalCount: 2);
    return (
      items: [
        Customer(
          id: 'customer-001',
          tenantId: 'tenant-001',
          type: CustomerType.person,
          name: 'João Silva',
          document: '12345678909',
          phone: '11988887777',
          isActive: true,
          createdAt: DateTime(2026, 7, 22),
          updatedAt: DateTime(2026, 7, 22),
        ),
        Customer(
          id: 'customer-002',
          tenantId: 'tenant-001',
          type: CustomerType.company,
          name: 'Alpha Refrigeração',
          document: '11222333000181',
          phone: '1133334444',
          isActive: true,
          createdAt: DateTime(2026, 7, 22),
          updatedAt: DateTime(2026, 7, 22),
        ),
      ],
      totalCount: 2,
    );
  }
}

void main() {
  testWidgets('ServiceRequestListScreen mostra titulo e campo de busca',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRequestRepositoryProvider.overrideWithValue(
            _FakeServiceRequestRepository(),
          ),
          customerRepositoryProvider
              .overrideWithValue(_FakeCustomerRepository()),
        ],
        child: const MaterialApp(
          home: ServiceRequestListScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Chamados'), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.text('Buscar chamados'), findsOneWidget);
  });

  testWidgets('ServiceRequestListScreen abre novo chamado em popup',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRequestRepositoryProvider.overrideWithValue(
            _FakeServiceRequestRepository(),
          ),
          customerRepositoryProvider
              .overrideWithValue(_FakeCustomerRepository()),
        ],
        child: const MaterialApp(
          home: ServiceRequestListScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Novo chamado').last);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Novo chamado'), findsWidgets);
    expect(find.text('Buscar por nome, CPF/CNPJ ou telefone'), findsOneWidget);
    expect(
      find.text('Cliente não cadastrado? Novo cliente'),
      findsOneWidget,
    );
  });

  testWidgets('campo Cliente filtra a lista por telefone e documento',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serviceRequestRepositoryProvider.overrideWithValue(
            _FakeServiceRequestRepository(),
          ),
          customerRepositoryProvider
              .overrideWithValue(_FakeCustomerRepository()),
        ],
        child: const MaterialApp(
          home: ServiceRequestListScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Novo chamado').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(Autocomplete<Customer>),
      '1198888',
    );
    await tester.pumpAndSettle();

    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text('Alpha Refrigeração'), findsNothing);

    await tester.enterText(
      find.byType(Autocomplete<Customer>),
      '11222333000181',
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha Refrigeração'), findsOneWidget);
  });
}
