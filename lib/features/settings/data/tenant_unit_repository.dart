import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/tenant_unit.dart';

class TenantUnitRepository {
  TenantUnitRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<List<TenantUnit>> list(String tenantId) async {
    try {
      final rows = await _db
          .from('tenant_units')
          .select()
          .eq('tenant_id', tenantId)
          .order('is_primary', ascending: false)
          .order('name');
      return (rows as List)
          .map((row) => TenantUnit.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } catch (e) {
      throw UnexpectedError('Erro ao carregar unidades.', e.toString());
    }
  }

  Future<void> create({
    required String tenantId,
    required TenantUnit unit,
  }) async {
    try {
      await _db.from('tenant_units').insert(unit.toInsertMap(tenantId));
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao criar unidade.');
    } catch (e) {
      throw UnexpectedError('Erro ao criar unidade.', e.toString());
    }
  }

  Future<void> update(TenantUnit unit) async {
    try {
      await _db
          .from('tenant_units')
          .update(unit.toUpdateMap())
          .eq('id', unit.id);
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao atualizar unidade.');
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar unidade.', e.toString());
    }
  }

  AppError _mapError(PostgrestException e, String fallback) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Voce nao tem permissao para gerenciar unidades.',
      );
    }
    if (e.code == 'P0001') {
      return BusinessRuleError(e.message);
    }
    return UnexpectedError(fallback, '${e.code}: ${e.message}');
  }
}
