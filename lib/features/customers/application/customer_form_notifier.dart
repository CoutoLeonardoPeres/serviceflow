import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_address.dart';
import '../domain/customer_contact.dart';
import 'customer_list_notifier.dart';

// ── Estado do formulário ──────────────────────────────────────────────────────

sealed class CustomerFormState {
  const CustomerFormState();
}

final class CustomerFormIdle extends CustomerFormState {
  const CustomerFormIdle();
}

final class CustomerFormLoading extends CustomerFormState {
  const CustomerFormLoading();
}

final class CustomerFormSuccess extends CustomerFormState {
  const CustomerFormSuccess({required this.customer, required this.isCreate});
  final Customer customer;
  final bool isCreate;
}

final class CustomerFormError extends CustomerFormState {
  const CustomerFormError({required this.error});
  final AppError error;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class CustomerFormNotifier extends Notifier<CustomerFormState> {
  @override
  CustomerFormState build() => const CustomerFormIdle();

  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  /// Cria um novo cliente e atualiza a lista.
  Future<void> createCustomer({
    required CustomerType type,
    required String name,
    String? tradeName,
    String? document,
    String? email,
    String? phone,
    String? notes,
    String? payerCustomerId,
  }) async {
    state = const CustomerFormLoading();

    final customer = Customer(
      id: '',           // servidor gera
      tenantId: '',     // servidor deriva da membership (trigger)
      type: type,
      name: name.trim(),
      tradeName: tradeName?.trim().isEmpty == true ? null : tradeName?.trim(),
      document: document?.replaceAll(RegExp(r'\D'), '').isEmpty == true
          ? null
          : document?.replaceAll(RegExp(r'\D'), ''),
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      phone: phone?.replaceAll(RegExp(r'\D'), '').isEmpty == true
          ? null
          : phone?.replaceAll(RegExp(r'\D'), ''),
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      isActive: true,
      payerCustomerId: payerCustomerId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final created = await _repo.create(customer);
      // Atualiza lista sem recarregar
      ref.read(customerListProvider.notifier).load();
      state = CustomerFormSuccess(customer: created, isCreate: true);
    } on AppError catch (e) {
      state = CustomerFormError(error: e);
    } catch (e) {
      state = CustomerFormError(
        error: UnexpectedError(
          userMessage: 'Erro ao criar cliente.',
          internalDetail: e.toString(),
        ),
      );
    }
  }

  /// Edita um cliente existente.
  Future<void> updateCustomer({
    required Customer original,
    required CustomerType type,
    required String name,
    String? tradeName,
    String? document,
    String? email,
    String? phone,
    String? notes,
    String? payerCustomerId,
  }) async {
    state = const CustomerFormLoading();

    final updated = original.copyWith(
      type: type,
      name: name.trim(),
      tradeName: tradeName?.trim().isEmpty == true ? null : tradeName?.trim(),
      document: document?.replaceAll(RegExp(r'\D'), '').isEmpty == true
          ? null
          : document?.replaceAll(RegExp(r'\D'), ''),
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      phone: phone?.replaceAll(RegExp(r'\D'), '').isEmpty == true
          ? null
          : phone?.replaceAll(RegExp(r'\D'), ''),
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      payerCustomerId: payerCustomerId,
    );

    try {
      final saved = await _repo.update(original.id, updated);
      ref.read(customerListProvider.notifier).updateInList(saved);
      state = CustomerFormSuccess(customer: saved, isCreate: false);
    } on AppError catch (e) {
      state = CustomerFormError(error: e);
    } catch (e) {
      state = CustomerFormError(
        error: UnexpectedError(
          userMessage: 'Erro ao atualizar cliente.',
          internalDetail: e.toString(),
        ),
      );
    }
  }

  /// Desativa um cliente (soft delete).
  Future<void> deactivateCustomer(Customer customer) async {
    state = const CustomerFormLoading();
    try {
      await _repo.deactivate(customer.id);
      ref.read(customerListProvider.notifier).removeFromList(customer.id);
      state = CustomerFormSuccess(customer: customer, isCreate: false);
    } on AppError catch (e) {
      state = CustomerFormError(error: e);
    } catch (e) {
      state = CustomerFormError(
        error: UnexpectedError(
          userMessage: 'Erro ao desativar cliente.',
          internalDetail: e.toString(),
        ),
      );
    }
  }

  void reset() => state = const CustomerFormIdle();
}

// ── Notifier de contatos ──────────────────────────────────────────────────────

sealed class ContactFormState {
  const ContactFormState();
}

final class ContactFormIdle extends ContactFormState {
  const ContactFormIdle();
}

final class ContactFormLoading extends ContactFormState {
  const ContactFormLoading();
}

final class ContactFormSuccess extends ContactFormState {
  const ContactFormSuccess({required this.contact});
  final CustomerContact contact;
}

final class ContactFormError extends ContactFormState {
  const ContactFormError({required this.error});
  final AppError error;
}

class CustomerContactFormNotifier extends Notifier<ContactFormState> {
  @override
  ContactFormState build() => const ContactFormIdle();

  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  Future<void> save({
    CustomerContact? existing,
    required String customerId,
    required String name,
    String? role,
    String? phone,
    String? whatsapp,
    String? email,
    required bool isPrimary,
  }) async {
    state = const ContactFormLoading();

    final contact = CustomerContact(
      id: existing?.id ?? '',
      tenantId: existing?.tenantId ?? '',
      customerId: customerId,
      name: name.trim(),
      role: role?.trim().isEmpty == true ? null : role?.trim(),
      phone: phone?.replaceAll(RegExp(r'\D'), '').isEmpty == true
          ? null
          : phone?.replaceAll(RegExp(r'\D'), ''),
      whatsapp: whatsapp?.replaceAll(RegExp(r'\D'), '').isEmpty == true
          ? null
          : whatsapp?.replaceAll(RegExp(r'\D'), ''),
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      isPrimary: isPrimary,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: existing?.createdBy,
    );

    try {
      final saved = existing == null
          ? await _repo.addContact(contact)
          : await _repo.updateContact(contact);
      state = ContactFormSuccess(contact: saved);
    } on AppError catch (e) {
      state = ContactFormError(error: e);
    } catch (e) {
      state = ContactFormError(
        error: UnexpectedError(
          userMessage: 'Erro ao salvar contato.',
          internalDetail: e.toString(),
        ),
      );
    }
  }

  void reset() => state = const ContactFormIdle();
}

// ── Notifier de endereços ─────────────────────────────────────────────────────

sealed class AddressFormState {
  const AddressFormState();
}

final class AddressFormIdle extends AddressFormState {
  const AddressFormIdle();
}

final class AddressFormLoading extends AddressFormState {
  const AddressFormLoading();
}

final class AddressFormSuccess extends AddressFormState {
  const AddressFormSuccess({required this.address});
  final CustomerAddress address;
}

final class AddressFormError extends AddressFormState {
  const AddressFormError({required this.error});
  final AppError error;
}

class CustomerAddressFormNotifier extends Notifier<AddressFormState> {
  @override
  AddressFormState build() => const AddressFormIdle();

  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  Future<void> save({
    CustomerAddress? existing,
    required String customerId,
    required String label,
    required String cep,
    required String street,
    required String number,
    String? complement,
    required String district,
    required String city,
    required String state_,
    String? reference,
    required bool isDefault,
  }) async {
    state = const AddressFormLoading();

    final address = CustomerAddress(
      id: existing?.id ?? '',
      tenantId: existing?.tenantId ?? '',
      customerId: customerId,
      label: label.trim(),
      cep: cep.replaceAll(RegExp(r'\D'), ''),
      street: street.trim(),
      number: number.trim(),
      complement: complement?.trim().isEmpty == true ? null : complement?.trim(),
      district: district.trim(),
      city: city.trim(),
      state: state_,
      reference: reference?.trim().isEmpty == true ? null : reference?.trim(),
      isDefault: isDefault,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: existing?.createdBy,
    );

    try {
      final saved = existing == null
          ? await _repo.addAddress(address)
          : await _repo.updateAddress(address);
      state = AddressFormSuccess(address: saved);
    } on AppError catch (e) {
      state = AddressFormError(error: e);
    } catch (e) {
      state = AddressFormError(
        error: UnexpectedError(
          userMessage: 'Erro ao salvar endereço.',
          internalDetail: e.toString(),
        ),
      );
    }
  }

  void reset() => state = const AddressFormIdle();
}

// ── Providers ─────────────────────────────────────────────────────────────────

final customerFormProvider =
    NotifierProvider<CustomerFormNotifier, CustomerFormState>(
  CustomerFormNotifier.new,
);

final customerContactFormProvider =
    NotifierProvider<CustomerContactFormNotifier, ContactFormState>(
  CustomerContactFormNotifier.new,
);

final customerAddressFormProvider =
    NotifierProvider<CustomerAddressFormNotifier, AddressFormState>(
  CustomerAddressFormNotifier.new,
);
