import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/platform_tenant.dart';

class PlatformAdminRepository {
  PlatformAdminRepository(this._client);

  final SupabaseClient _client;

  Future<bool> isPlatformAdmin() async {
    try {
      return await _client.rpc('is_platform_admin') as bool? ?? false;
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Não foi possível validar o acesso administrativo.');
    } catch (e) {
      throw UnexpectedError(
        'Não foi possível validar o acesso administrativo.',
        e.toString(),
      );
    }
  }

  Future<List<PlatformTenant>> listTenants() async {
    try {
      final rows = await _client.rpc('list_platform_tenants');
      return (rows as List)
          .map((row) =>
              PlatformTenant.fromMap(Map<String, dynamic>.from(row as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Não foi possível carregar as empresas.');
    } catch (e) {
      throw UnexpectedError(
          'Não foi possível carregar as empresas.', e.toString());
    }
  }

  AppError _mapError(PostgrestException e, String fallback) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Você não tem permissão para acessar o painel administrativo.',
      );
    }
    return UnexpectedError(fallback, '${e.code}: ${e.message}');
  }
}
