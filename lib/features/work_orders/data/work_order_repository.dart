import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../../../core/error/app_error.dart';
import '../../../core/files/stored_attachment.dart';
import '../domain/work_order.dart';
import '../domain/work_order_satisfaction.dart';

class WorkOrderFilter {
  const WorkOrderFilter({
    this.search,
    this.status,
    this.customerId,
  });

  final String? search;
  final WorkOrderStatus? status;
  final String? customerId;

  WorkOrderFilter copyWith({
    String? search,
    WorkOrderStatus? status,
    String? customerId,
    bool clearSearch = false,
    bool clearStatus = false,
    bool clearCustomer = false,
  }) =>
      WorkOrderFilter(
        search: clearSearch ? null : search ?? this.search,
        status: clearStatus ? null : status ?? this.status,
        customerId: clearCustomer ? null : customerId ?? this.customerId,
      );
}

class WorkOrderRepository {
  WorkOrderRepository(this._client);

  final SupabaseClient? _client;
  static const _table = 'work_orders';
  static const _pageSize = 20;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<({List<WorkOrder> items, int totalCount})> listPaged({
    WorkOrderFilter filter = const WorkOrderFilter(),
    int page = 0,
  }) async {
    try {
      final from = page * _pageSize;
      final to = from + _pageSize - 1;
      var query = _db.from(_table).select(
            '*, customers(name), service_requests(title), quotations(number)',
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

      final rows =
          await query.order('created_at', ascending: false).range(from, to);
      final enrichedRows = (rows as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      await _attachRouteAddresses(enrichedRows);
      final items = enrichedRows.map(workOrderFromRow).toList();
      final isLastPage = items.length < _pageSize;
      final totalCount =
          isLastPage ? page * _pageSize + items.length : (page + 2) * _pageSize;
      return (items: items, totalCount: totalCount);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
          'Erro ao carregar ordens de servico.', e.toString());
    }
  }

  Future<WorkOrder> get(String id) async {
    try {
      final row = await _db
          .from(_table)
          .select(
              '*, customers(name), service_requests(title), quotations(number)')
          .eq('id', id)
          .single();
      final enriched = Map<String, dynamic>.from(row);
      await _attachRouteAddresses([enriched]);
      return workOrderFromRow(enriched);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw const NotFoundError('OS nao encontrada.');
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar OS.', e.toString());
    }
  }

  Future<WorkOrder> create(
    WorkOrder workOrder, {
    List<WorkOrderDraftItem> items = const [],
  }) async {
    try {
      final row = await _db
          .from(_table)
          .insert(workOrder.toInsertPayload())
          .select(
              '*, customers(name), service_requests(title), quotations(number)')
          .single();
      final enriched = Map<String, dynamic>.from(row);
      final workOrderId = enriched['id'] as String;
      if (items.isNotEmpty) {
        await _db.from('work_order_items').insert(
              items
                  .map((item) => item.toInsertPayload(workOrderId))
                  .toList(growable: false),
            );
      }
      await _attachRouteAddresses([enriched]);
      return workOrderFromRow(enriched);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao criar OS.', e.toString());
    }
  }

  Future<WorkOrder> convertApprovedQuotation(String quotationId) async {
    try {
      final row = await _db.rpc(
        'convert_approved_quotation_to_work_order',
        params: {'p_quotation_id': quotationId},
      );
      final enriched = Map<String, dynamic>.from(row as Map);
      await _attachRouteAddresses([enriched]);
      return workOrderFromRow(enriched);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao converter orcamento em OS.', e.toString());
    }
  }

  Future<WorkOrder> transitionStatus({
    required String id,
    required WorkOrderStatus status,
    String? notes,
  }) async {
    try {
      final row = await _db.rpc(
        'transition_work_order',
        params: {
          'p_work_order_id': id,
          'p_to_status': status.value,
          'p_notes': notes,
        },
      );
      final enriched = Map<String, dynamic>.from(row as Map);
      await _attachRouteAddresses([enriched]);
      return workOrderFromRow(enriched);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar status da OS.', e.toString());
    }
  }

  Future<void> recordTimeEntry({
    required String workOrderId,
    required DateTime startedAt,
    required DateTime endedAt,
    String? notes,
  }) async {
    try {
      await _db.rpc(
        'record_work_order_time_entry',
        params: {
          'p_work_order_id': workOrderId,
          'p_started_at': startedAt.toUtc().toIso8601String(),
          'p_ended_at': endedAt.toUtc().toIso8601String(),
          'p_notes': notes,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao registrar horas da OS.', e.toString());
    }
  }

  Future<void> addMaterial({
    required String workOrderId,
    required String description,
    required double quantity,
    required int unitCostCents,
    required int unitPriceCents,
  }) async {
    try {
      await _db.rpc(
        'add_work_order_material',
        params: {
          'p_work_order_id': workOrderId,
          'p_description': description,
          'p_quantity': quantity,
          'p_unit_cost_cents': unitCostCents,
          'p_unit_price_cents': unitPriceCents,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao adicionar material da OS.', e.toString());
    }
  }

  Future<void> recordAcceptance({
    required String workOrderId,
    required String signerName,
    String? signerDocumentPartial,
    String? comments,
  }) async {
    try {
      await _db.rpc(
        'record_work_order_acceptance',
        params: {
          'p_work_order_id': workOrderId,
          'p_signer_name': signerName,
          'p_signer_document_partial': signerDocumentPartial,
          'p_comments': comments,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao registrar aceite da OS.', e.toString());
    }
  }

  Future<void> addExpense({
    required String workOrderId,
    required String kind,
    required int amountCents,
    String? description,
  }) async {
    try {
      await _db.rpc(
        'add_work_order_expense',
        params: {
          'p_work_order_id': workOrderId,
          'p_kind': kind,
          'p_amount_cents': amountCents,
          'p_description': description,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao registrar despesa da OS.', e.toString());
    }
  }

  Future<void> uploadEvidence({
    required String tenantId,
    required String workOrderId,
    required String kind,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      final safeName = _safeFileName(fileName);
      final path =
          '$tenantId/$workOrderId/${DateTime.now().microsecondsSinceEpoch}-$safeName';
      await _db.storage.from('work-order-evidence').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );
      await _db.rpc(
        'record_work_order_evidence',
        params: {
          'p_work_order_id': workOrderId,
          'p_kind': kind,
          'p_storage_path': path,
          'p_mime_type': mimeType,
          'p_size_bytes': bytes.length,
        },
      );
    } on StorageException catch (e) {
      throw UnexpectedError(
        'Erro ao enviar evidência da OS.',
        e.message,
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao registrar evidência da OS.', e.toString());
    }
  }

  Future<List<StoredAttachment>> listEvidence(String workOrderId) async {
    try {
      final rows = await _db
          .from('work_order_evidence')
          .select('id, kind, storage_path, mime_type, size_bytes, created_at')
          .eq('work_order_id', workOrderId)
          .order('created_at', ascending: false);
      return (rows as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (row) => StoredAttachment(
              id: row['id'] as String,
              kind: row['kind'] as String?,
              storagePath: row['storage_path'] as String,
              mimeType: row['mime_type'] as String,
              sizeBytes: (row['size_bytes'] as num).toInt(),
              createdAt: DateTime.parse(row['created_at'] as String),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar anexos da OS.', e.toString());
    }
  }

  Future<List<WorkOrderItem>> listItems(String workOrderId) async {
    try {
      final rows = await _db
          .from('work_order_items')
          .select()
          .eq('work_order_id', workOrderId)
          .order('created_at');
      return (rows as List<dynamic>)
          .map((row) => workOrderItemFromRow(Map<String, dynamic>.from(row)))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar itens da OS.', e.toString());
    }
  }

  Future<String> createEvidenceSignedUrl(String storagePath) async {
    try {
      return await _db.storage
          .from('work-order-evidence')
          .createSignedUrl(storagePath, 3600);
    } on StorageException catch (e) {
      throw UnexpectedError(
        'Erro ao gerar acesso ao anexo da OS.',
        e.message,
      );
    } catch (e) {
      throw UnexpectedError('Erro ao abrir anexo da OS.', e.toString());
    }
  }

  Future<void> createReceivableFromWorkOrder(String workOrderId) async {
    try {
      await _db.rpc(
        'create_receivable_from_work_order',
        params: {'p_work_order_id': workOrderId},
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao gerar cobranca da OS.', e.toString());
    }
  }

  Future<WorkOrderSatisfaction?> getSatisfaction(String workOrderId) async {
    try {
      final rows = await _db
          .from('work_order_satisfaction')
          .select()
          .eq('work_order_id', workOrderId)
          .limit(1);
      if ((rows as List<dynamic>).isEmpty) return null;
      return workOrderSatisfactionFromRow(
        rows.first,
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        'Erro ao carregar satisfação da OS.',
        e.toString(),
      );
    }
  }

  Future<WorkOrderSatisfaction> recordSatisfaction({
    required String workOrderId,
    required int rating,
    String? contactName,
    String? comment,
  }) async {
    try {
      final row = await _db.rpc(
        'record_work_order_satisfaction',
        params: {
          'p_work_order_id': workOrderId,
          'p_rating': rating,
          'p_contact_name': contactName,
          'p_comment': comment,
        },
      );
      return workOrderSatisfactionFromRow(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        'Erro ao registrar satisfação da OS.',
        e.toString(),
      );
    }
  }

  String _safeFileName(String fileName) {
    final trimmed = fileName.trim().isEmpty ? 'evidencia.bin' : fileName.trim();
    return trimmed
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  Future<void> _attachRouteAddresses(List<Map<String, dynamic>> rows) async {
    final directIds =
        rows.map((row) => row['address_id']).whereType<String>().toSet();
    final requestIds = rows
        .where((row) => row['address_id'] == null)
        .map((row) => row['request_id'])
        .whereType<String>()
        .toSet();
    final customerIds = rows
        .where((row) => row['address_id'] == null)
        .map((row) => row['customer_id'])
        .whereType<String>()
        .toSet();
    final byId = <String, Map<String, dynamic>>{};
    final byRequest = <String, Map<String, dynamic>>{};
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

    if (requestIds.isNotEmpty) {
      final requestRows = await _db
          .from('service_requests')
          .select('id, address_id')
          .inFilter('id', requestIds.toList());
      final addressIds = (requestRows as List<dynamic>)
          .map((row) => (row as Map)['address_id'])
          .whereType<String>()
          .toSet();
      if (addressIds.isNotEmpty) {
        final addressRows = await _db
            .from('customer_addresses')
            .select()
            .inFilter('id', addressIds.toList());
        final requestAddressById = <String, Map<String, dynamic>>{};
        for (final row in (addressRows as List<dynamic>)) {
          final map = Map<String, dynamic>.from(row as Map);
          requestAddressById[map['id'] as String] = map;
        }
        for (final row in requestRows) {
          final map = row as Map;
          final requestId = map['id'];
          final addressId = map['address_id'];
          if (requestId is String && addressId is String) {
            final address = requestAddressById[addressId];
            if (address != null) byRequest[requestId] = address;
          }
        }
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
      final requestId = row['request_id'];
      final customerId = row['customer_id'];
      row['route_address'] = addressId is String
          ? byId[addressId]
          : requestId is String
              ? byRequest[requestId] ??
                  (customerId is String ? byCustomer[customerId] : null)
              : customerId is String
                  ? byCustomer[customerId]
                  : null;
    }
  }

  AppError _mapError(PostgrestException e) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Voce nao tem permissao para acessar ordens de servico.',
      );
    }
    if (e.code == '23514' || e.code == 'P0001') {
      return const BusinessRuleError('Revise os dados da OS.');
    }
    return UnexpectedError(
      'Operacao de OS falhou. Tente novamente.',
      '${e.code}: ${e.message}',
    );
  }
}
