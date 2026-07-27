import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/audit_log_event.dart';

class AuditLogRepository {
  AuditLogRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    final c = _client;
    if (c == null) throw StateError('SupabaseClient não configurado.');
    return c;
  }

  Future<List<AuditLogEvent>> listEvents({
    int limit = 50,
    String? entity,
    String? action,
  }) async {
    try {
      final result = await _db.rpc<dynamic>(
        'list_audit_events',
        params: {
          'p_limit': limit,
          if (entity != null) 'p_entity': entity,
          if (action != null) 'p_action': action,
        },
      );

      final rows = (result as List).cast<Map<String, dynamic>>();
      return rows.map(auditLogEventFromRow).toList();
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const PermissionError('Sem acesso à trilha de auditoria.');
      throw UnexpectedError('Erro ao carregar auditoria', e.message);
    } catch (e) {
      throw UnexpectedError('Erro inesperado', e.toString());
    }
  }
}
