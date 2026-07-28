import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/files/stored_attachment.dart';
import '../domain/quotation.dart';
import '../domain/quotation_version.dart';

class QuotationFilter {
  const QuotationFilter({
    this.search,
    this.status,
    this.customerId,
    this.requestId,
  });

  final String? search;
  final QuotationStatus? status;
  final String? customerId;
  final String? requestId;

  QuotationFilter copyWith({
    String? search,
    QuotationStatus? status,
    String? customerId,
    String? requestId,
    bool clearSearch = false,
    bool clearStatus = false,
  }) =>
      QuotationFilter(
        search: clearSearch ? null : search ?? this.search,
        status: clearStatus ? null : status ?? this.status,
        customerId: customerId ?? this.customerId,
        requestId: requestId ?? this.requestId,
      );
}

class QuotationRepository {
  QuotationRepository(this._client);

  final SupabaseClient? _client;
  static const _table = 'quotations';
  static const _pageSize = 20;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<({List<Quotation> items, int totalCount})> listPaged({
    QuotationFilter filter = const QuotationFilter(),
    int page = 0,
  }) async {
    try {
      final from = page * _pageSize;
      final to = from + _pageSize - 1;
      var query = _db.from(_table).select(
            '*, customers(name), service_requests(title)',
          );

      if (filter.status != null) {
        query = query.eq('status', filter.status!.value);
      }
      if (filter.customerId != null) {
        query = query.eq('customer_id', filter.customerId!);
      }
      if (filter.requestId != null) {
        query = query.eq('request_id', filter.requestId!);
      }

      final rows =
          await query.order('created_at', ascending: false).range(from, to);
      final enrichedRows = (rows as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      await _attachRouteAddresses(enrichedRows);
      final items = enrichedRows.map(quotationFromRow).toList();
      final isLastPage = items.length < _pageSize;
      final totalCount =
          isLastPage ? page * _pageSize + items.length : (page + 2) * _pageSize;
      return (items: items, totalCount: totalCount);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar orcamentos.', e.toString());
    }
  }

  Future<Quotation> get(String id) async {
    try {
      final row = await _db
          .from(_table)
          .select('*, customers(name), service_requests(title)')
          .eq('id', id)
          .single();
      final enriched = Map<String, dynamic>.from(row);
      await _attachRouteAddresses([enriched]);
      return quotationFromRow(enriched);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw const NotFoundError('Orcamento nao encontrado.');
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar orcamento.', e.toString());
    }
  }

  Future<List<QuotationItem>> listItems(
    String quotationId, {
    String? versionId,
  }) async {
    try {
      var query =
          _db.from('quotation_items').select().eq('quotation_id', quotationId);
      if (versionId != null && versionId.isNotEmpty) {
        query = query.eq('version_id', versionId);
      }
      final rows = await query.order('created_at');
      return (rows as List<dynamic>)
          .map((row) => _quotationItemFromRow(Map<String, dynamic>.from(row)))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
          'Erro ao carregar itens do orcamento.', e.toString());
    }
  }

  Future<Quotation> create({
    required Quotation quotation,
    required List<QuotationDraftItem> items,
  }) async {
    try {
      final row = await _db.rpc(
        'create_quotation',
        params: {
          'p_customer_id': quotation.customerId,
          'p_request_id': quotation.requestId,
          'p_valid_until': quotation.validUntil?.toUtc().toIso8601String(),
          'p_notes': quotation.notes,
          'p_terms': quotation.terms,
          'p_items': items.map((item) => item.toPayload()).toList(),
        },
      );
      final enriched = Map<String, dynamic>.from(row as Map);
      await _attachRouteAddresses([enriched]);
      return quotationFromRow(enriched);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao criar orcamento.', e.toString());
    }
  }

  // ── Versionamento ─────────────────────────────────────────────────────────

  /// Lista todas as versões do orçamento em ordem decrescente.
  Future<List<QuotationVersion>> listVersions(String quotationId) async {
    try {
      final rows = await _db.rpc(
        'list_quotation_versions',
        params: {'p_quotation_id': quotationId},
      );
      return (rows as List<dynamic>)
          .map((row) =>
              quotationVersionFromRow(Map<String, dynamic>.from(row as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
          'Erro ao carregar versoes do orcamento.', e.toString());
    }
  }

  /// Cria nova versão do orçamento com os itens fornecidos.
  /// Retorna o novo versionId, versionNumber e totalCents.
  Future<({String versionId, int versionNumber, int totalCents})>
      createNewVersion({
    required String quotationId,
    required List<QuotationDraftItem> items,
    String? notes,
  }) async {
    try {
      final result = await _db.rpc(
        'create_new_quotation_version',
        params: {
          'p_quotation_id': quotationId,
          'p_items': items.map((i) => i.toPayload()).toList(),
          'p_notes': notes,
        },
      );
      final map = Map<String, dynamic>.from(result as Map);
      return (
        versionId: map['version_id'] as String,
        versionNumber: (map['version_number'] as num).toInt(),
        totalCents: (map['total_cents'] as num).toInt(),
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const PermissionError(
          'Voce nao tem permissao para revisar este orcamento.',
        );
      }
      if (e.code == 'P0001' || e.code == 'check_violation') {
        throw BusinessRuleError(
          e.message.isNotEmpty ? e.message : 'Operacao nao permitida.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
          'Erro ao criar versao do orcamento.', e.toString());
    }
  }

  // ── Histórico de status ────────────────────────────────────────────────────

  /// Lista o histórico de status do orçamento, mais recente primeiro.
  Future<List<QuotationStatusEvent>> listStatusHistory(
      String quotationId) async {
    try {
      final rows = await _db
          .from('quotation_status_history')
          .select('id, status, notes, changed_at')
          .eq('quotation_id', quotationId)
          .order('changed_at', ascending: false);
      return (rows as List<dynamic>)
          .map((row) => quotationStatusEventFromRow(
              Map<String, dynamic>.from(row as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
          'Erro ao carregar historico do orcamento.', e.toString());
    }
  }

  /// Cancela o orçamento com motivo obrigatório.
  /// Não é possível cancelar orçamentos com status [approved] ou [cancelled].
  Future<void> cancel(String quotationId, String reason) async {
    try {
      await _db.rpc(
        'cancel_quotation',
        params: {
          'p_quotation_id': quotationId,
          'p_reason': reason.trim(),
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const PermissionError(
          'Voce nao tem permissao para cancelar este orcamento.',
        );
      }
      if (e.code == 'P0001') {
        throw BusinessRuleError(
          e.message.isNotEmpty ? e.message : 'Operacao nao permitida.',
        );
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao cancelar orcamento.', e.toString());
    }
  }

  Future<String> createPublicLink(String quotationId) async {
    try {
      final token = await _db.rpc(
        'create_quotation_public_link',
        params: {'p_quotation_id': quotationId},
      );
      return token as String;
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao gerar link do orcamento.', e.toString());
    }
  }

  Future<int> revokePublicLinks(String quotationId) async {
    try {
      final count = await _db.rpc(
        'revoke_quotation_public_links',
        params: {'p_quotation_id': quotationId},
      );
      return count as int;
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao revogar link do orcamento.', e.toString());
    }
  }

  /// Orçamento e linhas de um link público, para visitante não autenticado.
  ///
  /// Tudo vem da RPC (SECURITY DEFINER, valida o token). Não dá para
  /// enriquecer com consultas diretas aqui: elas rodariam como `anon`, que não
  /// passa pelas policies — era o que fazia a página falhar por inteiro.
  Future<({Quotation quotation, List<QuotationItem> items})> getPublicByToken(
    String token,
  ) async {
    try {
      final row = await _db.rpc(
        'get_public_quotation',
        params: {'p_token': token},
      );
      final map = Map<String, dynamic>.from(row as Map);
      final rawItems = map['quotation_items'];
      final items = rawItems is List
          ? rawItems
              .map(
                (item) =>
                    _quotationItemFromRow(Map<String, dynamic>.from(item as Map)),
              )
              .toList()
          : <QuotationItem>[];
      return (quotation: quotationFromRow(map), items: items);
    } on PostgrestException catch (e) {
      // Sem o codigo/mensagem do banco aqui, qualquer falha do link publico
      // vira "link invalido" e nao da para saber se foi token, schema ou RLS.
      throw BusinessRuleError(
        'Nao foi possivel abrir o orcamento: ${e.code ?? ''} ${e.message}'
            .trim(),
      );
    } catch (e) {
      throw UnexpectedError('Erro ao abrir orcamento publico.', e.toString());
    }
  }

  /// Registra a resposta do cliente pelo próprio sistema — quando ele
  /// respondeu por telefone, WhatsApp ou pessoalmente, sem usar o link.
  /// Reabre orçamento recusado ou expirado dentro da janela de 30 dias
  /// (migration 0058). Devolve o chamado junto.
  Future<void> reopen({
    required String quotationId,
    String? reason,
  }) async {
    try {
      await _db.rpc(
        'reopen_quotation',
        params: {
          'p_quotation_id': quotationId,
          'p_reason':
              (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao reabrir o orcamento.', e.toString());
    }
  }

  Future<void> decideInternal({
    required String quotationId,
    required QuotationPublicDecision decision,
    required String approverName,
    String? comments,
  }) async {
    try {
      await _db.rpc(
        'decide_quotation',
        params: {
          'p_quotation_id': quotationId,
          'p_decision': decision.value,
          'p_approver_name': approverName.trim(),
          'p_comments':
              (comments == null || comments.trim().isEmpty) ? null : comments.trim(),
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao registrar a decisao.', e.toString());
    }
  }

  Future<void> decidePublic({
    required String token,
    required QuotationPublicDecision decision,
    required String approverName,
    String? comments,
  }) async {
    try {
      await _db.rpc(
        'decide_public_quotation',
        params: {
          'p_token': token,
          'p_decision': decision.value,
          'p_approver_name': approverName,
          'p_comments': comments,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao responder orcamento.', e.toString());
    }
  }

  Future<void> uploadAttachment({
    required String tenantId,
    required String quotationId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      final safeName = _safeFileName(fileName);
      final path =
          '$tenantId/$quotationId/${DateTime.now().microsecondsSinceEpoch}-$safeName';
      await _db.storage.from('quotation-attachments').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );
      await _db.from('quotation_attachments').insert({
        'quotation_id': quotationId,
        'storage_path': path,
        'mime_type': mimeType,
        'size_bytes': bytes.length,
      });
    } on StorageException catch (e) {
      throw UnexpectedError('Erro ao enviar anexo do orcamento.', e.message);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        'Erro ao registrar anexo do orcamento.',
        e.toString(),
      );
    }
  }

  Future<List<StoredAttachment>> listAttachments(String quotationId) async {
    try {
      final rows = await _db
          .from('quotation_attachments')
          .select('id, storage_path, mime_type, size_bytes, created_at')
          .eq('quotation_id', quotationId)
          .order('created_at', ascending: false);
      return (rows as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (row) => StoredAttachment(
              id: row['id'] as String,
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
      throw UnexpectedError(
        'Erro ao carregar anexos do orcamento.',
        e.toString(),
      );
    }
  }

  Future<String> createAttachmentSignedUrl(String storagePath) async {
    try {
      return await _db.storage
          .from('quotation-attachments')
          .createSignedUrl(storagePath, 3600);
    } on StorageException catch (e) {
      throw UnexpectedError(
        'Erro ao gerar acesso ao anexo do orcamento.',
        e.message,
      );
    } catch (e) {
      throw UnexpectedError(
        'Erro ao abrir anexo do orcamento.',
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
    final requestIds =
        rows.map((row) => row['request_id']).whereType<String>().toSet();
    final customerIds =
        rows.map((row) => row['customer_id']).whereType<String>().toSet();
    final requestAddressByRequest = <String, Map<String, dynamic>>{};
    final byCustomer = <String, Map<String, dynamic>>{};

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
        final byId = <String, Map<String, dynamic>>{};
        for (final row in (addressRows as List<dynamic>)) {
          final map = Map<String, dynamic>.from(row as Map);
          byId[map['id'] as String] = map;
        }
        for (final row in requestRows) {
          final map = row as Map;
          final addressId = map['address_id'];
          final requestId = map['id'];
          if (requestId is String && addressId is String) {
            final address = byId[addressId];
            if (address != null) requestAddressByRequest[requestId] = address;
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
      final requestId = row['request_id'];
      final customerId = row['customer_id'];
      row['route_address'] = requestId is String
          ? requestAddressByRequest[requestId] ??
              (customerId is String ? byCustomer[customerId] : null)
          : customerId is String
              ? byCustomer[customerId]
              : null;
    }
  }

  AppError _mapError(PostgrestException e) {
    // Mesma correcao aplicada em work_order_repository: a mensagem do banco ja
    // e especifica e em portugues; substitui-la por um texto generico apaga a
    // unica informacao util que o usuario tinha.
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return PermissionError(
        e.message.isNotEmpty
            ? e.message
            : 'Voce nao tem permissao para esta acao no orcamento.',
      );
    }
    if (e.code == '23514' || e.code == 'P0001') {
      return BusinessRuleError(
        e.message.isNotEmpty ? e.message : 'Revise os itens do orcamento.',
      );
    }
    return UnexpectedError(
      'Operacao de orcamento falhou. Tente novamente.',
      '${e.code}: ${e.message}',
    );
  }
}

QuotationItem _quotationItemFromRow(Map<String, dynamic> row) => QuotationItem(
      id: row['id'] as String,
      quotationId: row['quotation_id'] as String,
      versionId: row['version_id'] as String,
      kind: QuotationItemKind.fromValue(row['kind'] as String),
      description: row['description'] as String,
      quantity: row['quantity'] as num,
      unitPriceCents: (row['unit_price_cents'] as num).toInt(),
      unitCostCents: (row['unit_cost_cents'] as num).toInt(),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
