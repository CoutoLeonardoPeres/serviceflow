import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/invitation_preview.dart';

class InvitationRepository {
  InvitationRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<InvitationPreview> getPreview(String token) async {
    try {
      final rows = await _db.rpc(
        'get_invitation_preview',
        params: {'p_token': token},
      );
      if ((rows as List).isEmpty) {
        throw const NotFoundError('Convite não encontrado.');
      }
      return InvitationPreview.fromMap(
        Map<String, dynamic>.from(rows.first as Map),
      );
    } on PostgrestException catch (e) {
      if (e.code == '22023') {
        throw const ValidationError('Convite inválido.');
      }
      throw UnexpectedError('Erro ao validar convite.', '${e.code}: ${e.message}');
    } on AppError {
      rethrow;
    } catch (e) {
      throw UnexpectedError('Erro ao validar convite.', e.toString());
    }
  }
}
