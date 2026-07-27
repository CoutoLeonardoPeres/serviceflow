import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/communication_log.dart';
import '../domain/message_template.dart';

class CommunicationRepository {
  CommunicationRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    final c = _client;
    if (c == null) throw StateError('SupabaseClient não configurado.');
    return c;
  }

  // ── Templates ──────────────────────────────────────────────────────────────

  Future<List<MessageTemplate>> listTemplates({
    MessageChannel? channel,
    bool activeOnly = true,
  }) async {
    try {
      // Filters must be applied before order/limit (postgrest-dart 2.x)
      var query = _db.from('message_templates').select();

      if (activeOnly) {
        query = query.eq('is_active', true);
      }
      if (channel != null) {
        query = query.eq('channel', channel.name);
      }

      final rows = await query.order('channel').order('name');
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(messageTemplateFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw UnexpectedError('Erro ao listar templates', e.message);
    }
  }

  Future<MessageTemplate> createTemplate({
    required String name,
    required MessageChannel channel,
    required String body,
    String? subject,
  }) async {
    try {
      final row = await _db
          .from('message_templates')
          .insert({
            'name': name.trim(),
            'channel': channel.name,
            'body': body.trim(),
            if (subject != null && subject.trim().isNotEmpty)
              'subject': subject.trim(),
          })
          .select()
          .single();
      return messageTemplateFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const PermissionError();
      throw UnexpectedError('Erro ao criar template', e.message);
    }
  }

  Future<void> updateTemplate(
    String id, {
    String? name,
    String? body,
    String? subject,
    bool? isActive,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
        if (name != null) 'name': name.trim(),
        if (body != null) 'body': body.trim(),
        if (subject != null) 'subject': subject.trim(),
        if (isActive != null) 'is_active': isActive,
      };
      await _db.from('message_templates').update(updates).eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const PermissionError();
      throw UnexpectedError('Erro ao atualizar template', e.message);
    }
  }

  Future<void> deleteTemplate(String id) async {
    try {
      await _db.from('message_templates').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const PermissionError();
      throw UnexpectedError('Erro ao excluir template', e.message);
    }
  }

  Future<void> seedDefaultTemplates() async {
    try {
      await _db.rpc('seed_default_message_templates', params: {
        'p_tenant_id': _db.auth.currentSession?.user.userMetadata?['tenant_id'],
      });
    } catch (_) {
      // Silencioso — não crítico
    }
  }

  // ── Logs ───────────────────────────────────────────────────────────────────

  Future<List<CommunicationLog>> listLogs({
    String? customerId,
    String? relatedEntity,
    String? relatedEntityId,
    int limit = 30,
  }) async {
    try {
      // Filters must be applied before order/limit (postgrest-dart 2.x)
      var query = _db.from('communication_logs').select();

      if (customerId != null) {
        query = query.eq('customer_id', customerId);
      }
      if (relatedEntity != null) {
        query = query.eq('related_entity', relatedEntity);
      }
      if (relatedEntityId != null) {
        query = query.eq('related_entity_id', relatedEntityId);
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(communicationLogFromRow)
          .toList();
    } on PostgrestException catch (e) {
      throw UnexpectedError('Erro ao listar comunicações', e.message);
    }
  }

  Future<String> logCommunication({
    required String customerId,
    required MessageChannel channel,
    String? bodyPreview,
    String? subject,
    String? relatedEntity,
    String? relatedEntityId,
    String? templateId,
    String status = 'sent',
  }) async {
    try {
      final result = await _db.rpc<dynamic>('log_communication', params: {
        'p_customer_id': customerId,
        'p_channel': channel.name,
        if (bodyPreview != null) 'p_body_preview': bodyPreview,
        if (subject != null) 'p_subject': subject,
        if (relatedEntity != null) 'p_related_entity': relatedEntity,
        if (relatedEntityId != null) 'p_related_entity_id': relatedEntityId,
        if (templateId != null) 'p_template_id': templateId,
        'p_status': status,
      });
      return result as String;
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const PermissionError();
      throw UnexpectedError('Erro ao registrar comunicação', e.message);
    }
  }
}
