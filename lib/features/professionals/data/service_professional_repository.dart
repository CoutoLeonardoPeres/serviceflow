import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/service_professional.dart';

class ServiceProfessionalRepository {
  ServiceProfessionalRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<List<ServiceProfessional>> list() async {
    try {
      final rows = await _db
          .from('service_professionals')
          .select()
          .order('is_active', ascending: false)
          .order('category')
          .order('name');
      return (rows as List<dynamic>)
          .map((row) => serviceProfessionalFromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar profissionais.');
    } catch (e) {
      throw UnexpectedError('Erro ao carregar profissionais.', e.toString());
    }
  }

  Future<List<TechnicianUserOption>> listInternalUsers() async {
    try {
      final rows = await _db.rpc('list_tenant_technician_users');
      return (rows as List<dynamic>)
          .map(
              (row) => technicianUserOptionFromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar usuários internos.');
    } catch (e) {
      throw UnexpectedError(
        'Erro ao carregar usuários internos.',
        e.toString(),
      );
    }
  }

  Future<ServiceProfessional> create(ServiceProfessional professional) async {
    try {
      final row = await _db
          .from('service_professionals')
          .insert(professional.toInsertPayload())
          .select()
          .single();
      return serviceProfessionalFromRow(row);
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao cadastrar profissional.');
    } catch (e) {
      throw UnexpectedError('Erro ao cadastrar profissional.', e.toString());
    }
  }

  Future<ServiceProfessional> update(ServiceProfessional professional) async {
    try {
      final row = await _db
          .from('service_professionals')
          .update(professional.toUpdatePayload())
          .eq('id', professional.id)
          .select()
          .single();
      return serviceProfessionalFromRow(row);
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao atualizar profissional.');
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar profissional.', e.toString());
    }
  }

  AppError _mapError(PostgrestException e, String fallback) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Voce nao tem permissao para gerenciar profissionais.',
      );
    }
    if (e.code == '23505') {
      return const BusinessRuleError(
        'Este usuário interno já está vinculado a outro profissional.',
      );
    }
    return UnexpectedError(fallback, '${e.code}: ${e.message}');
  }
}
