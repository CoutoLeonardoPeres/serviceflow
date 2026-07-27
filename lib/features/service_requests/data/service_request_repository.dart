import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/service_category.dart';
import '../domain/service_priority.dart';
import '../domain/service_request.dart';

class ServiceRequestFilter {
  const ServiceRequestFilter({
    this.search,
    this.status,
    this.customerId,
    this.categoryId,
    this.priorityId,
  });

  final String? search;
  final ServiceRequestStatus? status;
  final String? customerId;
  final String? categoryId;
  final String? priorityId;

  bool get isEmpty =>
      (search == null || search!.isEmpty) &&
      status == null &&
      customerId == null &&
      categoryId == null &&
      priorityId == null;

  ServiceRequestFilter copyWith({
    String? search,
    ServiceRequestStatus? status,
    String? customerId,
    String? categoryId,
    String? priorityId,
    bool clearSearch = false,
    bool clearStatus = false,
    bool clearCustomer = false,
    bool clearCategory = false,
    bool clearPriority = false,
  }) =>
      ServiceRequestFilter(
        search: clearSearch ? null : search ?? this.search,
        status: clearStatus ? null : status ?? this.status,
        customerId: clearCustomer ? null : customerId ?? this.customerId,
        categoryId: clearCategory ? null : categoryId ?? this.categoryId,
        priorityId: clearPriority ? null : priorityId ?? this.priorityId,
      );
}

class ServiceRequestRepository {
  ServiceRequestRepository(this._client);

  final SupabaseClient? _client;

  static const _table = 'service_requests';
  static const _categoriesTable = 'service_categories';
  static const _prioritiesTable = 'service_priorities';
  static const _historyTable = 'service_request_status_history';
  static const _pageSize = 20;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<({List<ServiceRequest> items, int totalCount})> listPaged({
    ServiceRequestFilter filter = const ServiceRequestFilter(),
    int page = 0,
  }) async {
    try {
      final from = page * _pageSize;
      final to = from + _pageSize - 1;

      var query = _db.from(_table).select(
            '*, customers(name), service_categories(name), service_priorities(name, level)',
          );

      if (filter.search != null && filter.search!.trim().isNotEmpty) {
        query = query.ilike('title', '%${filter.search!.trim()}%');
      }
      if (filter.status != null) {
        query = query.eq('status', filter.status!.value);
      }
      if (filter.customerId != null) {
        query = query.eq('customer_id', filter.customerId!);
      }
      if (filter.categoryId != null) {
        query = query.eq('category_id', filter.categoryId!);
      }
      if (filter.priorityId != null) {
        query = query.eq('priority_id', filter.priorityId!);
      }

      final response =
          await query.order('created_at', ascending: false).range(from, to);

      final rows = (response as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      await _attachRouteAddresses(rows);
      final items = rows.map(serviceRequestFromRow).toList();

      final isLastPage = items.length < _pageSize;
      final totalCount =
          isLastPage ? page * _pageSize + items.length : (page + 2) * _pageSize;

      return (items: items, totalCount: totalCount);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar chamados.', e.toString());
    }
  }

  Future<ServiceRequest> get(String id) async {
    try {
      final row = await _db
          .from(_table)
          .select(
            '*, customers(name), service_categories(name), service_priorities(name, level)',
          )
          .eq('id', id)
          .single();
      final enriched = Map<String, dynamic>.from(row);
      await _attachRouteAddresses([enriched]);
      return serviceRequestFromRow(enriched);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw const NotFoundError('Chamado nao encontrado.');
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar chamado.', e.toString());
    }
  }

  Future<ServiceRequest> create(ServiceRequest request) async {
    try {
      final row = await _db
          .from(_table)
          .insert(request.toInsertPayload())
          .select(
            '*, customers(name), service_categories(name), service_priorities(name, level)',
          )
          .single();
      final enriched = Map<String, dynamic>.from(row);
      await _attachRouteAddresses([enriched]);
      return serviceRequestFromRow(enriched);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao criar chamado.', e.toString());
    }
  }

  Future<ServiceRequest> update(String id, ServiceRequest request) async {
    try {
      final row = await _db
          .from(_table)
          .update(request.toInsertPayload())
          .eq('id', id)
          .select(
            '*, customers(name), service_categories(name), service_priorities(name, level)',
          )
          .single();
      final enriched = Map<String, dynamic>.from(row);
      await _attachRouteAddresses([enriched]);
      return serviceRequestFromRow(enriched);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar chamado.', e.toString());
    }
  }

  Future<ServiceRequest> transitionStatus({
    required String id,
    required ServiceRequestStatus status,
    String? reason,
  }) async {
    try {
      final row = await _db.rpc(
        'transition_service_request',
        params: {
          'p_request_id': id,
          'p_to_status': status.value,
          'p_reason': reason,
        },
      );
      return serviceRequestFromRow(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao alterar status do chamado.', e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> getStatusHistory(String requestId) async {
    try {
      final rows = await _db
          .from(_historyTable)
          .select()
          .eq('request_id', requestId)
          .order('created_at', ascending: false);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar historico.', e.toString());
    }
  }

  Future<List<ServiceCategory>> listCategories() async {
    try {
      final rows = await _db
          .from(_categoriesTable)
          .select()
          .eq('is_active', true)
          .order('name');
      return (rows as List<dynamic>)
          .map((row) => serviceCategoryFromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar categorias.', e.toString());
    }
  }

  Future<List<ServicePriority>> listPriorities() async {
    try {
      final rows = await _db
          .from(_prioritiesTable)
          .select()
          .eq('is_active', true)
          .order('level');
      return (rows as List<dynamic>)
          .map((row) => servicePriorityFromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar prioridades.', e.toString());
    }
  }

  // Sem policy de DELETE nas duas tabelas abaixo (proposital) — "excluir" na
  // UI e sempre um UPDATE de is_active.

  Future<List<ServiceCategory>> listAllCategories() async {
    try {
      final rows =
          await _db.from(_categoriesTable).select().order('name');
      return (rows as List<dynamic>)
          .map((row) => serviceCategoryFromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar categorias.', e.toString());
    }
  }

  Future<ServiceCategory> createCategory({
    required String name,
    String? description,
  }) async {
    try {
      final row = await _db
          .from(_categoriesTable)
          .insert({
            'name': name.trim(),
            'description':
                (description == null || description.trim().isEmpty)
                    ? null
                    : description.trim(),
          })
          .select()
          .single();
      return serviceCategoryFromRow(row);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao criar categoria.', e.toString());
    }
  }

  Future<ServiceCategory> updateCategory({
    required String id,
    required String name,
    String? description,
    required bool isActive,
  }) async {
    try {
      final row = await _db
          .from(_categoriesTable)
          .update({
            'name': name.trim(),
            'description':
                (description == null || description.trim().isEmpty)
                    ? null
                    : description.trim(),
            'is_active': isActive,
          })
          .eq('id', id)
          .select()
          .single();
      return serviceCategoryFromRow(row);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar categoria.', e.toString());
    }
  }

  Future<List<ServicePriority>> listAllPriorities() async {
    try {
      final rows =
          await _db.from(_prioritiesTable).select().order('level');
      return (rows as List<dynamic>)
          .map((row) => servicePriorityFromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar prioridades.', e.toString());
    }
  }

  Future<ServicePriority> createPriority({
    required String name,
    required int level,
    int? slaHours,
  }) async {
    try {
      final row = await _db
          .from(_prioritiesTable)
          .insert({
            'name': name.trim(),
            'level': level,
            'sla_hours': slaHours,
          })
          .select()
          .single();
      return servicePriorityFromRow(row);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao criar prioridade.', e.toString());
    }
  }

  Future<ServicePriority> updatePriority({
    required String id,
    required String name,
    required int level,
    int? slaHours,
    required bool isActive,
  }) async {
    try {
      final row = await _db
          .from(_prioritiesTable)
          .update({
            'name': name.trim(),
            'level': level,
            'sla_hours': slaHours,
            'is_active': isActive,
          })
          .eq('id', id)
          .select()
          .single();
      return servicePriorityFromRow(row);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar prioridade.', e.toString());
    }
  }

  Future<void> uploadPhotoAttachment({
    required String tenantId,
    required String requestId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      final safeName = _safeFileName(fileName);
      final path =
          '$tenantId/$requestId/${DateTime.now().microsecondsSinceEpoch}-$safeName';
      await _db.storage.from('service-request-attachments').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );
      await _db.from('service_request_attachments').insert({
        'request_id': requestId,
        'storage_path': path,
        'mime_type': mimeType,
        'size_bytes': bytes.length,
      });
    } on StorageException catch (e) {
      throw UnexpectedError('Erro ao enviar foto do chamado.', e.message);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        'Erro ao registrar foto do chamado.',
        e.toString(),
      );
    }
  }

  String _safeFileName(String fileName) {
    final trimmed = fileName.trim().isEmpty ? 'foto.jpg' : fileName.trim();
    return trimmed
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  Future<void> _attachRouteAddresses(List<Map<String, dynamic>> rows) async {
    final directIds =
        rows.map((row) => row['address_id']).whereType<String>().toSet();
    final customerIds = rows
        .where((row) => row['address_id'] == null)
        .map((row) => row['customer_id'])
        .whereType<String>()
        .toSet();

    final byId = <String, Map<String, dynamic>>{};
    final byCustomer = <String, Map<String, dynamic>>{};

    if (directIds.isNotEmpty) {
      final addressRows = await _db
          .from('customer_addresses')
          .select()
          .inFilter('id', directIds.toList());
      for (final row in (addressRows as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        byId[map['id'] as String] = map;
      }
    }

    if (customerIds.isNotEmpty) {
      final addressRows = await _db
          .from('customer_addresses')
          .select()
          .inFilter('customer_id', customerIds.toList())
          .eq('is_default', true);
      for (final row in (addressRows as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        byCustomer[map['customer_id'] as String] = map;
      }
    }

    for (final row in rows) {
      final addressId = row['address_id'];
      final customerId = row['customer_id'];
      row['route_address'] = addressId is String
          ? byId[addressId]
          : customerId is String
              ? byCustomer[customerId]
              : null;
    }
  }

  AppError _mapError(PostgrestException e) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Voce nao tem permissao para realizar esta acao.',
      );
    }
    if (e.code == '23514') {
      return const BusinessRuleError('Dados do chamado violam uma regra.');
    }
    return UnexpectedError(
      'Operacao falhou. Tente novamente.',
      '${e.code}: ${e.message}',
    );
  }
}
