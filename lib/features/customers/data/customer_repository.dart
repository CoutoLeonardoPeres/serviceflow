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

  static const _table          = 'customers';
  static const _contactsTable  = 'customer_contacts';
  static const _addressesTable = 'customer_addresses';
  static const _assetsTable    = 'customer_assets';
  static const _pageSize       = 20;

  // ── Listagem ──────────────────────────────────────────────────────────────

  /// Lista clientes com paginação e filtros server-side.
  /// Retorna os itens da página e o total de registros (para controle de paginação).
  Future<({List<Customer> items, int totalCount})> listPaged({
    CustomerFilter filter = const CustomerFilter(),
    int page = 0,
  }) async {
    try {
      final from = page * _pageSize;
      final to   = from + _pageSize - 1;

      // supabase_flutter 2.x: PostgrestFilterBuilder suporta encadeamento.
      // FetchOptions(count: exact) faz o PostgREST retornar Content-Range.
      var query = _client
          .from(_table)
          .select('*', const FetchOptions(count: CountOption.exact));

      if (filter.search != null && filter.search!.isNotEmpty) {
        query = query.ilike('name', '%${filter.search!}%');
      }
      if (filter.type != null) {
        query = query.eq('type', filter.type!.value);
      }
      if (filter.isActive != null) {
        query = query.eq('is_active', filter.isActive!);
      }

      final response = await query.order('name').range(from, to);

      final items = (response as List<dynamic>)
          .map((r) => customerFromRow(r as Map<String, dynamic>))
          .toList();

      // Estimativa conservadora de total:
      // se retornou uma página cheia, o total é ao menos (page+1)*pageSize.
      // O count real virá no cabeçalho Content-Range em chamadas HEAD — para MVP
      // usamos a heurística: se items < pageSize, chegamos ao fim.
      final isLastPage = items.length < _pageSize;
      final totalCount = isLastPage
          ? page * _pageSize + items.length
          : (page + 2) * _pageSize; // estimativa: há ao menos mais uma página

      return (items: items, totalCount: totalCount);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao carregar clientes.',
        internalDetail: e.toString(),
      );
    }
  }

  // ── Leitura ───────────────────────────────────────────────────────────────

  Future<Customer> get(String id) async {
    try {
      final row = await _client
          .from(_table)
          .select()
          .eq('id', id)
          .single();
      return customerFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw NotFoundError(userMessage: 'Cliente não encontrado.');
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao carregar cliente.',
        internalDetail: e.toString(),
      );
    }
  }

  // ── Escrita ───────────────────────────────────────────────────────────────

  Future<Customer> create(Customer customer) async {
    try {
      final payload = customer.toInsertPayload();
      final row = await _client
          .from(_table)
          .insert(payload)
          .select()
          .single();
      return customerFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // uq_customers_document_tenant
        throw BusinessRuleError(
          userMessage: 'Já existe um cliente com este CPF/CNPJ cadastrado.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao criar cliente.',
        internalDetail: e.toString(),
      );
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
      if (e.code == '23505') {
        throw BusinessRuleError(
          userMessage: 'Já existe um cliente com este CPF/CNPJ cadastrado.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao atualizar cliente.',
        internalDetail: e.toString(),
      );
    }
  }

  /// Soft delete — marca is_active = false.
  Future<void> deactivate(String id) async {
    try {
      await _client
          .from(_table)
          .update({'is_active': false})
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao desativar cliente.',
        internalDetail: e.toString(),
      );
    }
  }

  Future<void> reactivate(String id) async {
    try {
      await _client
          .from(_table)
          .update({'is_active': true})
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao reativar cliente.',
        internalDetail: e.toString(),
      );
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
      throw UnexpectedError(
        userMessage: 'Erro ao carregar contatos.',
        internalDetail: e.toString(),
      );
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
        throw BusinessRuleError(
          userMessage: 'Este cliente já possui um contato principal.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao adicionar contato.',
        internalDetail: e.toString(),
      );
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
        throw BusinessRuleError(
          userMessage: 'Este cliente já possui um contato principal.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao atualizar contato.',
        internalDetail: e.toString(),
      );
    }
  }

  Future<void> deleteContact(String contactId) async {
    try {
      await _client.from(_contactsTable).delete().eq('id', contactId);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao remover contato.',
        internalDetail: e.toString(),
      );
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
      throw UnexpectedError(
        userMessage: 'Erro ao carregar endereços.',
        internalDetail: e.toString(),
      );
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
        throw BusinessRuleError(
          userMessage: 'Este cliente já possui um endereço padrão.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao adicionar endereço.',
        internalDetail: e.toString(),
      );
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
        throw BusinessRuleError(
          userMessage: 'Este cliente já possui um endereço padrão.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao atualizar endereço.',
        internalDetail: e.toString(),
      );
    }
  }

  Future<void> deleteAddress(String addressId) async {
    try {
      await _client.from(_addressesTable).delete().eq('id', addressId);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        userMessage: 'Erro ao remover endereço.',
        internalDetail: e.toString(),
      );
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
      throw UnexpectedError(
        userMessage: 'Erro ao carregar equipamentos.',
        internalDetail: e.toString(),
      );
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
      throw UnexpectedError(
        userMessage: 'Erro ao adicionar equipamento.',
        internalDetail: e.toString(),
      );
    }
  }

  // ── Mapeamento de erros ───────────────────────────────────────────────────

  AppError _mapError(PostgrestException e) {
    // 42501 = insufficient_privilege (RLS negou acesso)
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        userMessage: 'Você não tem permissão para realizar esta ação.',
      );
    }
    return UnexpectedError(
      userMessage: 'Operação falhou. Tente novamente.',
      internalDetail: '${e.code}: ${e.message}',
    );
  }
}
