// ignore_for_file: avoid_print
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:serviceflow/core/error/app_error.dart';
import 'package:serviceflow/features/customers/application/customer_form_notifier.dart';
import 'package:serviceflow/features/customers/application/customer_list_notifier.dart';
import 'package:serviceflow/features/customers/data/customer_repository.dart';
import 'package:serviceflow/features/customers/domain/customer.dart';

@GenerateMocks([CustomerRepository])
import 'customer_form_notifier_test.mocks.dart';

Customer _mockCustomer({
  String id = 'cid-001',
  CustomerType type = CustomerType.company,
  String name = 'Empresa Alpha Ltda',
}) =>
    Customer(
      id: id,
      tenantId: 'tid-001',
      type: type,
      name: name,
      isActive: true,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

void main() {
  late MockCustomerRepository mockRepo;

  setUp(() {
    mockRepo = MockCustomerRepository();
  });

  ProviderContainer _makeContainer() => ProviderContainer(
        overrides: [
          customerRepositoryProvider.overrideWithValue(mockRepo),
          // Lista provider: stub vazio para evitar chamada real
          customerListProvider.overrideWith(CustomerListNotifier.new),
        ],
      );

  group('CustomerFormNotifier — estado inicial', () {
    test('começa em idle', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      expect(container.read(customerFormProvider), isA<CustomerFormIdle>());
    });
  });

  group('CustomerFormNotifier — criar cliente', () {
    test('sucesso: transita para CustomerFormSuccess com isCreate=true',
        () async {
      final created = _mockCustomer();
      when(mockRepo.create(any)).thenAnswer((_) async => created);

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(customerFormProvider.notifier).createCustomer(
            type: CustomerType.company,
            name: 'Empresa Alpha Ltda',
          );

      final state = container.read(customerFormProvider);
      expect(state, isA<CustomerFormSuccess>());
      final success = state as CustomerFormSuccess;
      expect(success.isCreate, isTrue);
      expect(success.customer.name, 'Empresa Alpha Ltda');
    });

    test('falha de permissão: transita para CustomerFormError com PermissionError',
        () async {
      when(mockRepo.create(any)).thenThrow(
        const PermissionError(
            userMessage: 'Você não tem permissão para realizar esta ação.'),
      );

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(customerFormProvider.notifier).createCustomer(
            type: CustomerType.person,
            name: 'João Silva',
          );

      final state = container.read(customerFormProvider);
      expect(state, isA<CustomerFormError>());
      final error = (state as CustomerFormError).error;
      expect(error, isA<PermissionError>());
    });

    test('falha de documento duplicado: transita para CustomerFormError com BusinessRuleError',
        () async {
      when(mockRepo.create(any)).thenThrow(
        const BusinessRuleError(
            userMessage: 'Já existe um cliente com este CPF/CNPJ cadastrado.'),
      );

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(customerFormProvider.notifier).createCustomer(
            type: CustomerType.company,
            name: 'Empresa Beta',
            document: '11222333000181',
          );

      final state = container.read(customerFormProvider);
      expect(state, isA<CustomerFormError>());
      expect((state as CustomerFormError).error, isA<BusinessRuleError>());
    });
  });

  group('CustomerFormNotifier — editar cliente', () {
    test('sucesso: transita para CustomerFormSuccess com isCreate=false',
        () async {
      final original = _mockCustomer();
      final updated = _mockCustomer(name: 'Alpha Services Ltda');
      when(mockRepo.update(original.id, any))
          .thenAnswer((_) async => updated);

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(customerFormProvider.notifier).updateCustomer(
            original: original,
            type: CustomerType.company,
            name: 'Alpha Services Ltda',
          );

      final state = container.read(customerFormProvider);
      expect(state, isA<CustomerFormSuccess>());
      final success = state as CustomerFormSuccess;
      expect(success.isCreate, isFalse);
      expect(success.customer.name, 'Alpha Services Ltda');
    });
  });

  group('CustomerFormNotifier — desativar cliente', () {
    test('sucesso: chama deactivate e transita para CustomerFormSuccess',
        () async {
      final customer = _mockCustomer();
      when(mockRepo.deactivate(customer.id)).thenAnswer((_) async {});

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(customerFormProvider.notifier)
          .deactivateCustomer(customer);

      final state = container.read(customerFormProvider);
      expect(state, isA<CustomerFormSuccess>());
      verify(mockRepo.deactivate(customer.id)).called(1);
    });
  });

  group('CustomerFormNotifier — reset', () {
    test('volta a idle após chamar reset()', () async {
      final customer = _mockCustomer();
      when(mockRepo.create(any)).thenAnswer((_) async => customer);

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(customerFormProvider.notifier).createCustomer(
            type: CustomerType.company,
            name: 'Empresa Gamma',
          );

      container.read(customerFormProvider.notifier).reset();
      expect(container.read(customerFormProvider), isA<CustomerFormIdle>());
    });
  });

  group('CustomerType', () {
    test('usesCpf é true apenas para person', () {
      expect(CustomerType.person.usesCpf, isTrue);
      expect(CustomerType.company.usesCpf, isFalse);
      expect(CustomerType.condominium.usesCpf, isFalse);
      expect(CustomerType.publicEntity.usesCpf, isFalse);
    });

    test('fromValue e value são simétricos', () {
      for (final t in CustomerType.values) {
        expect(CustomerType.fromValue(t.value), t);
      }
    });

    test('fromValue com valor desconhecido lança ArgumentError', () {
      expect(() => CustomerType.fromValue('unknown'), throwsArgumentError);
    });
  });
}
