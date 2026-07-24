import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/customers/application/customer_list_notifier.dart';
import 'package:serviceflow/features/customers/data/customer_repository.dart';
import 'package:serviceflow/features/customers/domain/customer.dart';
import 'package:serviceflow/features/customers/presentation/customer_list_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _NoopSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository({this.items = const []})
      : super(_NoopSupabaseClient());

  final List<Customer> items;

  @override
  Future<({List<Customer> items, int totalCount})> listPaged({
    CustomerFilter filter = const CustomerFilter(),
    int page = 0,
  }) async =>
      (items: page == 0 ? items : <Customer>[], totalCount: items.length);
}

Customer _customer() => Customer(
      id: 'customer-001',
      tenantId: 'tenant-001',
      type: CustomerType.company,
      name: 'Alpha Refrigeração',
      tradeName: 'Alpha',
      document: '11222333000181',
      email: 'contato@alpha.com',
      phone: '11999999999',
      isActive: true,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 22),
    );

void main() {
  testWidgets('CustomerListScreen abre cadastro em popup', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider
              .overrideWithValue(_FakeCustomerRepository()),
        ],
        child: const MaterialApp(home: CustomerListScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Novo cliente'), findsWidgets);
    expect(find.text('Pessoa de contato'), findsOneWidget);
    expect(find.text('Endereço padrão'), findsOneWidget);
    expect(find.text('CEP *'), findsOneWidget);
  });

  testWidgets('CustomerListScreen mostra botão editar e abre popup de edição',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider.overrideWithValue(
            _FakeCustomerRepository(items: [_customer()]),
          ),
        ],
        child: const MaterialApp(home: CustomerListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha Refrigeração'), findsOneWidget);
    expect(find.byTooltip('Editar cliente'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar cliente'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Editar cliente'), findsWidgets);
    expect(find.text('Salvar alterações'), findsOneWidget);
  });
}
