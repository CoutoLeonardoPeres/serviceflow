import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/tenant_invitation.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_role_option.dart';

class InvitationCreateResult {
  const InvitationCreateResult({
    required this.id,
    required this.token,
    required this.expiresAt,
  });

  final String id;
  final String token;
  final DateTime expiresAt;
}

class MemberManagementRepository {
  MemberManagementRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<List<TenantMember>> listMembers() async {
    try {
      final rows = await _db.rpc('list_tenant_members');
      return (rows as List)
          .map((row) => TenantMember.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar membros.');
    } catch (e) {
      throw UnexpectedError('Erro ao carregar membros.', e.toString());
    }
  }

  Future<List<TenantInvitation>> listInvitations(String tenantId) async {
    try {
      final rows = await _db
          .from('user_invitations')
          .select(
              'id, email, expires_at, created_at, accepted_at, revoked_at, roles(id, key, name)')
          .eq('tenant_id', tenantId)
          .isFilter('accepted_at', null)
          .isFilter('revoked_at', null)
          .order('created_at', ascending: false);
      return (rows as List)
          .map(
              (row) => TenantInvitation.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar convites.');
    } catch (e) {
      throw UnexpectedError('Erro ao carregar convites.', e.toString());
    }
  }

  Future<List<TenantRoleOption>> listRoles() async {
    try {
      final rows = await _db
          .from('roles')
          .select('id, key, name')
          .neq('key', 'platform_admin')
          .neq('key', 'customer_portal_user')
          .order('name');
      return (rows as List)
          .map(
              (row) => TenantRoleOption.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar papéis.');
    } catch (e) {
      throw UnexpectedError('Erro ao carregar papéis.', e.toString());
    }
  }

  Future<InvitationCreateResult> createInvitation({
    required String email,
    required String roleKey,
    int expiresInDays = 7,
  }) async {
    try {
      final rows = await _db.rpc(
        'create_tenant_invitation',
        params: {
          'p_email': email,
          'p_role_key': roleKey,
          'p_expires_in_days': expiresInDays,
        },
      );
      final row = Map<String, dynamic>.from((rows as List).first as Map);
      return InvitationCreateResult(
        id: row['invitation_id'] as String,
        token: row['invitation_token'] as String,
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao criar convite.');
    } catch (e) {
      throw UnexpectedError('Erro ao criar convite.', e.toString());
    }
  }

  Future<void> revokeInvitation(String invitationId) async {
    try {
      await _db.rpc(
        'revoke_tenant_invitation',
        params: {'p_invitation_id': invitationId},
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao revogar convite.');
    } catch (e) {
      throw UnexpectedError('Erro ao revogar convite.', e.toString());
    }
  }

  Future<void> setMembershipStatus({
    required String membershipId,
    required String status,
  }) async {
    try {
      await _db.rpc(
        'set_tenant_membership_status',
        params: {
          'p_membership_id': membershipId,
          'p_status': status,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao atualizar membro.');
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar membro.', e.toString());
    }
  }

  AppError _mapError(PostgrestException e, String fallback) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Voce nao tem permissao para gerenciar membros.',
      );
    }
    if (e.code == '22023') {
      return ValidationError(e.message);
    }
    if (e.code == 'P0001' || e.code == 'P0002') {
      return BusinessRuleError(e.message);
    }
    return UnexpectedError(fallback, '${e.code}: ${e.message}');
  }
}
