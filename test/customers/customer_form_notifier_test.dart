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
import 'package:serviceflow/features/customers/domain/customer_address.dart';
import 'package:serviceflow/features/customers/domain/customer_contact.dart';

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

CustomerContact _mockContact({String customerId = 'cid-001'}) =>
    CustomerContact(
      id: 'contact-001',
      tenantId: 'tid-001',
      customerId: customerId,
      name: 'Maria Operacao',
      phone: '11999999999',
      whatsapp: '11999999999',
      email: 'maria@alpha.com',
      isPrimary: true,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

CustomerAddress _mockAddress({String customerId = 'cid-001'}) =>
    CustomerAddress(
      id: 'address-001',
      tenantId: 'tid-001',
      customerId: customerId,
      label: 'Principal',
      cep: '01310100',
      street: 'Avenida Paulista',
      number: '1000',
      district: 'Bela Vista',
      city: 'Sao Paulo',
      state: 'SP',
      isDefault: true,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

void main() {
  late MockCustomerRepository mockRepo;

  setUp(() {
    mockRepo = MockCustomerRepository();
  });

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          customerRepositoryProvider.overrideWithValue(mockRepo),
          // Lista provider: stub vazio para evitar chamada real
          customerListProvider.overrideWith(CustomerListNotifier.new),
        ],
      );

  group('CustomerFormNotifier — estado inicial', () {
    test('começa em idle', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      expect(container.read(customerFormProvider), isA<CustomerFormIdle>());
    });
  });

  group('CustomerFormNotifier — criar cliente', () {
    test('sucesso: transita para CustomerFormSuccess com isCreate=true',
        () async {
      final created = _mockCustomer();
      when(mockRepo.create(any)).thenAnswer((_) async => created);

      final container = makeContainer();
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

    test(
        'sucesso: cria contato principal e endereço padrão no primeiro cadastro',
        () async {
      final created = _mockCustomer();
      when(mockRepo.create(any)).thenAnswer((_) async => created);
      when(mockRepo.addContact(any))
          .thenAnswer((_) async => _mockContact(customerId: created.id));
      when(mockRepo.addAddress(any))
          .thenAnswer((_) async => _mockAddress(customerId: created.id));

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(customerFormProvider.notifier).createCustomer(
            type: CustomerType.company,
            name: 'Empresa Alpha Ltda',
            phone: '(11) 99999-9999',
            contactName: 'Maria Operacao',
            contactPhone: '(11) 99999-9999',
            contactEmail: 'maria@alpha.com',
            addressCep: '01310-100',
            addressStreet: 'Avenida Paulista',
            addressNumber: '1000',
            addressDistrict: 'Bela Vista',
            addressCity: 'Sao Paulo',
            addressState: 'SP',
          );

      final contact = verify(mockRepo.addContact(captureAny)).captured.single
          as CustomerContact;
      expect(contact.customerId, created.id);
      expect(contact.name, 'Maria Operacao');
      expect(contact.phone, '11999999999');
      expect(contact.isPrimary, isTrue);

      final address = verify(mockRepo.addAddress(captureAny)).captured.single
          as CustomerAddress;
      expect(address.customerId, created.id);
      expect(address.cep, '01310100');
      expect(address.street, 'Avenida Paulista');
      expect(address.isDefault, isTrue);
    });

    test(
        'falha de permissão: transita para CustomerFormError com PermissionError',
        () async {
      when(mockRepo.create(any)).thenThrow(
        const PermissionError(
          'Você não tem permissão para realizar esta ação.',
        ),
      );

      final container = makeContainer();
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

    test(
        'falha de documento duplicado: transita para CustomerFormError com BusinessRuleError',
        () async {
      when(mockRepo.create(any)).thenThrow(
        const BusinessRuleError(
          'Já existe um cliente com este CPF/CNPJ cadastrado.',
        ),
      );

      final container = makeContainer();
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

    test(
        'falha de telefone duplicado: transita para CustomerFormError com BusinessRuleError',
        () async {
      when(mockRepo.create(any)).thenThrow(
        const BusinessRuleError(
          'Já existe um cliente com este telefone cadastrado.',
        ),
      );

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(customerFormProvider.notifier).createCustomer(
            type: CustomerType.company,
            name: 'Empresa Beta',
            phone: '(11) 99999-9999',
          );

      final state = container.read(customerFormProvider);
      expect(state, isA<CustomerFormError>());
      expect((state as CustomerFormError).error, isA<BusinessRuleError>());
      expect(state.error.userMessage,
          'Já existe um cliente com este telefone cadastrado.');
    });
  });

  group('CustomerFormNotifier — editar cliente', () {
    test('sucesso: transita para CustomerFormSuccess com isCreate=false',
        () async {
      final original = _mockCustomer();
      final updated = _mockCustomer(name: 'Alpha Services Ltda');
      when(mockRepo.update(original.id, any)).thenAnswer((_) async => updated);

      final container = makeContainer();
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

      final container = makeContainer();
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

      final container = makeContainer();
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
