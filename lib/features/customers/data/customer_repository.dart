import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/customer.dart';
import '../domain/customer_address.dart';
import '../domain/customer_asset.dart';
import '../domain/customer_contact.dart';

/// Filtros para listagem de clientes.
class CustomerFilter {
  const CustomerFilter({
    this.search,
    this.type,
    this.isActive = true,
  });

  final String? search;
  final CustomerType? type;
  final bool? isActive; // null = todos

  bool get isEmpty =>
      (search == null || search!.isEmpty) && type == null && isActive == null;
}

/// Repositório de clientes — acessa Supabase via PostgREST.
/// Toda verificação de permissão e tenant é feita no banco (RLS).
class CustomerRepository {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'customers';
  static const _contactsTable = 'customer_contacts';
  static const _addressesTable = 'customer_addresses';
  static const _assetsTable = 'customer_assets';
  static const _pageSize = 20;

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

  bool _matchesSearch(Customer customer, String search) {
    final normalizedSearch = search.trim().toLowerCase();
    final numericSearch = _digitsOnly(search);

    final textFields = <String>[
      customer.name,
      customer.tradeName ?? '',
      customer.email ?? '',
    ].map((value) => value.toLowerCase());

    final matchesText = textFields.any(
      (value) => value.contains(normalizedSearch),
    );

    final matchesNumeric = numericSearch.isNotEmpty &&
        <String>[
          customer.phone ?? '',
          customer.document ?? '',
        ].map(_digitsOnly).any((value) => value.contains(numericSearch));

    return matchesText || matchesNumeric;
  }

  Future<({Set<String> documents, Set<String> phones})>
      findExistingDocumentAndPhoneConflicts({
    Set<String> documents = const {},
    Set<String> phones = const {},
  }) async {
    try {
      final foundDocuments = <String>{};
      final foundPhones = <String>{};

      if (documents.isNotEmpty) {
        final rows = await _client
            .from(_table)
            .select('document')
            .inFilter('document', documents.toList());
        for (final row in (rows as List<dynamic>)) {
          final value = (row as Map<String, dynamic>)['document'] as String?;
          if (value != null && value.isNotEmpty) {
            foundDocuments.add(value);
          }
        }
      }

      if (phones.isNotEmpty) {
        final rows = await _client
            .from(_table)
            .select('phone')
            .inFilter('phone', phones.toList());
        for (final row in (rows as List<dynamic>)) {
          final value = (row as Map<String, dynamic>)['phone'] as String?;
          if (value != null && value.isNotEmpty) {
            foundPhones.add(value);
          }
        }
      }

      return (documents: foundDocuments, phones: foundPhones);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        'Erro ao verificar clientes existentes.',
        e.toString(),
      );
    }
  }

  // ── Listagem ──────────────────────────────────────────────────────────────

  /// Lista clientes com paginação.
  /// Para busca textual/numérica, aplica filtro local para evitar inconsistências
  /// entre nome, telefone, CPF/CNPJ e e-mail no PostgREST.
  /// Retorna os itens da página e o total de registros (para controle de paginação).
  Future<({List<Customer> items, int totalCount})> listPaged({
    CustomerFilter filter = const CustomerFilter(),
    int page = 0,
  }) async {
    try {
      var query = _client.from(_table).select('*');
      if (filter.type != null) {
        query = query.eq('type', filter.type!.value);
      }
      if (filter.isActive != null) {
        query = query.eq('is_active', filter.isActive!);
      }

      final response = await query.order('name').range(0, 999);

      var allItems = (response as List<dynamic>)
          .map((r) => customerFromRow(r as Map<String, dynamic>))
          .toList();

      final search = filter.search?.trim();
      if (search != null && search.isNotEmpty) {
        allItems = allItems
            .where((customer) => _matchesSearch(customer, search))
            .toList();
      }

      final totalCount = allItems.length;
      final from = page * _pageSize;
      if (from >= totalCount) {
        return (items: const <Customer>[], totalCount: totalCount);
      }

      final toExclusive = (from + _pageSize).clamp(0, totalCount);
      final items = allItems.sublist(from, toExclusive);

      return (items: items, totalCount: totalCount);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar clientes.', e.toString());
    }
  }

  // ── Leitura ───────────────────────────────────────────────────────────────

  Future<Customer> get(String id) async {
    try {
      final row = await _client.from(_table).select().eq('id', id).single();
      return customerFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw const NotFoundError('Cliente não encontrado.');
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar cliente.', e.toString());
    }
  }

  // ── Escrita ───────────────────────────────────────────────────────────────

  Future<Customer> create(Customer customer) async {
    try {
      final payload = customer.toInsertPayload();
      final row = await _client.from(_table).insert(payload).select().single();
      return customerFromRow(row);
    } on PostgrestException catch (e) {
      final duplicateError = _mapCustomerDuplicateError(e);
      if (duplicateError != null) {
        throw duplicateError;
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao criar cliente.', e.toString());
    }
  }

  Future<Customer> update(String id, Customer customer) async {
    try {
      final payload = customer.toInsertPayload();
      final row = await _client
          .from(_table)
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      return customerFromRow(row);
    } on PostgrestException catch (e) {
      final duplicateError = _mapCustomerDuplicateError(e);
      if (duplicateError != null) {
        throw duplicateError;
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar cliente.', e.toString());
    }
  }

  /// Soft delete — marca is_active = false.
  Future<void> deactivate(String id) async {
    try {
      await _client.from(_table).update({'is_active': false}).eq('id', id);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao desativar cliente.', e.toString());
    }
  }

  Future<void> reactivate(String id) async {
    try {
      await _client.from(_table).update({'is_active': true}).eq('id', id);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao reativar cliente.', e.toString());
    }
  }

  // ── Contatos ──────────────────────────────────────────────────────────────

  Future<List<CustomerContact>> getContacts(String customerId) async {
    try {
      final rows = await _client
          .from(_contactsTable)
          .select()
          .eq('customer_id', customerId)
          .order('is_primary', ascending: false)
          .order('name');
      return (rows as List<dynamic>)
          .map((r) => customerContactFromRow(r as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar contatos.', e.toString());
    }
  }

  Future<CustomerContact> addContact(CustomerContact contact) async {
    try {
      final row = await _client
          .from(_contactsTable)
          .insert(contact.toInsertPayload())
          .select()
          .single();
      return customerContactFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const BusinessRuleError(
          'Este cliente já possui um contato principal.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao adicionar contato.', e.toString());
    }
  }

  Future<CustomerContact> updateContact(CustomerContact contact) async {
    try {
      final row = await _client
          .from(_contactsTable)
          .update(contact.toInsertPayload())
          .eq('id', contact.id)
          .select()
          .single();
      return customerContactFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const BusinessRuleError(
          'Este cliente já possui um contato principal.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar contato.', e.toString());
    }
  }

  Future<void> deleteContact(String contactId) async {
    try {
      await _client.from(_contactsTable).delete().eq('id', contactId);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao remover contato.', e.toString());
    }
  }

  // ── Endereços ─────────────────────────────────────────────────────────────

  Future<List<CustomerAddress>> getAddresses(String customerId) async {
    try {
      final rows = await _client
          .from(_addressesTable)
          .select()
          .eq('customer_id', customerId)
          .order('is_default', ascending: false)
          .order('label');
      return (rows as List<dynamic>)
          .map((r) => customerAddressFromRow(r as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar endereços.', e.toString());
    }
  }

  Future<CustomerAddress> addAddress(CustomerAddress address) async {
    try {
      final row = await _client
          .from(_addressesTable)
          .insert(address.toInsertPayload())
          .select()
          .single();
      return customerAddressFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const BusinessRuleError(
          'Este cliente já possui um endereço padrão.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao adicionar endereço.', e.toString());
    }
  }

  Future<CustomerAddress> updateAddress(CustomerAddress address) async {
    try {
      final row = await _client
          .from(_addressesTable)
          .update(address.toInsertPayload())
          .eq('id', address.id)
          .select()
          .single();
      return customerAddressFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const BusinessRuleError(
          'Este cliente já possui um endereço padrão.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar endereço.', e.toString());
    }
  }

  Future<void> deleteAddress(String addressId) async {
    try {
      await _client.from(_addressesTable).delete().eq('id', addressId);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao remover endereço.', e.toString());
    }
  }

  // ── Ativos ────────────────────────────────────────────────────────────────

  Future<List<CustomerAsset>> getAssets(String customerId) async {
    try {
      final rows = await _client
          .from(_assetsTable)
          .select()
          .eq('customer_id', customerId)
          .eq('is_active', true)
          .order('name');
      return (rows as List<dynamic>)
          .map((r) => customerAssetFromRow(r as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar equipamentos.', e.toString());
    }
  }

  Future<CustomerAsset> addAsset(CustomerAsset asset) async {
    try {
      final row = await _client
          .from(_assetsTable)
          .insert(asset.toInsertPayload())
          .select()
          .single();
      return customerAssetFromRow(row);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao adicionar equipamento.', e.toString());
    }
  }

  // ── Mapeamento de erros ───────────────────────────────────────────────────

  AppError? _mapCustomerDuplicateError(PostgrestException e) {
    if (e.code != '23505') return null;

    final detail =
        '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toLowerCase();

    if (detail.contains('uq_customers_phone_tenant') ||
        detail.contains('(tenant_id, phone)')) {
      return const BusinessRuleError(
        'Já existe um cliente com este telefone cadastrado.',
      );
    }

    if (detail.contains('uq_customers_document_tenant') ||
        detail.contains('(tenant_id, document)')) {
      return const BusinessRuleError(
        'Já existe um cliente com este CPF/CNPJ cadastrado.',
      );
    }

    return const BusinessRuleError(
      'Já existe um cliente com este CPF/CNPJ ou telefone cadastrado.',
    );
  }

  AppError _mapError(PostgrestException e) {
    // 42501 = insufficient_privilege (RLS negou acesso)
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Você não tem permissão para realizar esta ação.',
      );
    }
    return UnexpectedError(
      'Operação falhou. Tente novamente.',
      '${e.code}: ${e.message}',
    );
  }
}
