import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/plans/tenant_plan.dart';
import '../../../core/error/app_error.dart';
import '../domain/schedule_models.dart';
import '../domain/tenant_billing_event.dart';
import '../domain/tenant_billing_webhook_event.dart';
import '../domain/tenant_checkout_session.dart';

class CompanyScheduleSettings {
  const CompanyScheduleSettings({
    required this.weeklySchedule,
    required this.closures,
  });

  final Map<String, DaySchedule> weeklySchedule;
  final List<AgendaClosure> closures;
}

class PlanUpdateResult {
  const PlanUpdateResult({
    required this.plan,
    required this.billingStatus,
    required this.trialEndsAt,
    required this.planSelectedAt,
  });

  final TenantPlanDefinition plan;
  final String billingStatus;
  final DateTime? trialEndsAt;
  final DateTime? planSelectedAt;
}

class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<CompanyScheduleSettings> loadCompanySettings(String tenantId) async {
    try {
      final rows = await _db
          .from('tenant_settings')
          .select('settings')
          .eq('tenant_id', tenantId)
          .limit(1);
      if ((rows as List).isEmpty) {
        await _upsertDefaultSettings(tenantId);
        return CompanyScheduleSettings(
          weeklySchedule: defaultWeeklySchedule(),
          closures: const [],
        );
      }
      final row = Map<String, dynamic>.from(rows.first as Map);
      final settings = Map<String, dynamic>.from(
        (row['settings'] as Map?) ?? <String, dynamic>{},
      );
      return CompanyScheduleSettings(
        weeklySchedule: weeklyScheduleFromJson(settings['business_hours']),
        closures: closuresFromJson(settings['agenda_closures']),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar configurações.');
    } catch (e) {
      throw UnexpectedError('Erro ao carregar configurações.', e.toString());
    }
  }

  Future<void> saveCompanySettings({
    required String tenantId,
    required Map<String, DaySchedule> weeklySchedule,
    required List<AgendaClosure> closures,
  }) async {
    try {
      final rows = await _db
          .from('tenant_settings')
          .select('settings')
          .eq('tenant_id', tenantId)
          .limit(1);
      final currentSettings = rows.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              (rows.first['settings'] as Map?) ?? <String, dynamic>{},
            );
      currentSettings['business_hours'] = weeklyScheduleToJson(weeklySchedule);
      currentSettings['agenda_closures'] = closuresToJson(closures);
      await _db.from('tenant_settings').upsert({
        'tenant_id': tenantId,
        'settings': currentSettings,
      }, onConflict: 'tenant_id');
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao salvar configurações.');
    } catch (e) {
      throw UnexpectedError('Erro ao salvar configurações.', e.toString());
    }
  }

  Future<void> _upsertDefaultSettings(String tenantId) {
    return _db.from('tenant_settings').upsert({
      'tenant_id': tenantId,
      'settings': {
        'business_hours': weeklyScheduleToJson(defaultWeeklySchedule()),
        'agenda_closures': const [],
      },
    }, onConflict: 'tenant_id');
  }

  Future<PlanUpdateResult> updateTenantPlan({required String planKey}) async {
    try {
      final row = await _db.rpc(
        'update_current_tenant_plan',
        params: {'p_plan_key': planKey},
      );
      final data = Map<String, dynamic>.from(row as Map);
      return PlanUpdateResult(
        plan: resolveTenantPlan(data['plan_key'] as String?),
        billingStatus: data['billing_status'] as String? ?? 'active',
        trialEndsAt: data['trial_ends_at'] == null
            ? null
            : DateTime.tryParse(data['trial_ends_at'] as String),
        planSelectedAt: data['plan_selected_at'] == null
            ? null
            : DateTime.tryParse(data['plan_selected_at'] as String),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao atualizar plano.');
    } catch (e) {
      throw UnexpectedError('Erro ao atualizar plano.', e.toString());
    }
  }

  Future<PlanUpdateResult> completeInitialPlanSelection({
    required String planKey,
  }) async {
    try {
      final row = await _db.rpc(
        'complete_current_tenant_plan_selection',
        params: {'p_plan_key': planKey},
      );
      final data = Map<String, dynamic>.from(row as Map);
      return PlanUpdateResult(
        plan: resolveTenantPlan(data['plan_key'] as String?),
        billingStatus: data['billing_status'] as String? ?? 'active',
        trialEndsAt: data['trial_ends_at'] == null
            ? null
            : DateTime.tryParse(data['trial_ends_at'] as String),
        planSelectedAt: data['plan_selected_at'] == null
            ? null
            : DateTime.tryParse(data['plan_selected_at'] as String),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao confirmar plano inicial.');
    } catch (e) {
      throw UnexpectedError('Erro ao confirmar plano inicial.', e.toString());
    }
  }

  Future<PlanUpdateResult> updateBillingStatus({
    required String billingStatus,
    String? note,
    DateTime? trialEndsAt,
  }) async {
    try {
      final row = await _db.rpc(
        'update_current_tenant_billing_status',
        params: {
          'p_billing_status': billingStatus,
          'p_note': note,
          'p_trial_ends_at': trialEndsAt?.toIso8601String(),
        },
      );
      final data = Map<String, dynamic>.from(row as Map);
      return PlanUpdateResult(
        plan: resolveTenantPlan(data['plan_key'] as String?),
        billingStatus: data['billing_status'] as String? ?? 'active',
        trialEndsAt: data['trial_ends_at'] == null
            ? null
            : DateTime.tryParse(data['trial_ends_at'] as String),
        planSelectedAt: data['plan_selected_at'] == null
            ? null
            : DateTime.tryParse(data['plan_selected_at'] as String),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao atualizar status da assinatura.');
    } catch (e) {
      throw UnexpectedError(
        'Erro ao atualizar status da assinatura.',
        e.toString(),
      );
    }
  }

  Future<List<TenantBillingEvent>> listBillingEvents(String tenantId) async {
    try {
      final rows = await _db
          .from('tenant_billing_events')
          .select(
            'id, event_type, plan_key, previous_plan_key, billing_status, previous_billing_status, note, actor_user_id, occurred_at',
          )
          .eq('tenant_id', tenantId)
          .order('occurred_at', ascending: false)
          .limit(20);
      return (rows as List)
          .map(
            (row) => TenantBillingEvent.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar histórico da assinatura.');
    } catch (e) {
      throw UnexpectedError(
        'Erro ao carregar histórico da assinatura.',
        e.toString(),
      );
    }
  }

  Future<TenantCheckoutSession> createCheckoutSession({
    required String planKey,
    required String source,
    String? returnUrl,
    String? provider,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final row = await _db.rpc(
        'create_current_tenant_checkout_session',
        params: {
          'p_plan_key': planKey,
          'p_source': source,
          'p_return_url': returnUrl,
          'p_provider': provider,
          'p_metadata': metadata ?? const <String, dynamic>{},
        },
      );
      return TenantCheckoutSession.fromMap(
        Map<String, dynamic>.from(row as Map),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao iniciar checkout.');
    } catch (e) {
      throw UnexpectedError('Erro ao iniciar checkout.', e.toString());
    }
  }

  Future<TenantCheckoutSession> registerCheckoutReturn({
    required String checkoutSessionId,
    String? providerReference,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final row = await _db.rpc(
        'register_current_tenant_checkout_return',
        params: {
          'p_checkout_session_id': checkoutSessionId,
          'p_provider_reference': providerReference,
          'p_metadata': metadata ?? const <String, dynamic>{},
        },
      );
      return TenantCheckoutSession.fromMap(
        Map<String, dynamic>.from(row as Map),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao registrar retorno do checkout.');
    } catch (e) {
      throw UnexpectedError(
        'Erro ao registrar retorno do checkout.',
        e.toString(),
      );
    }
  }

  Future<List<TenantCheckoutSession>> listCheckoutSessions(
    String tenantId, {
    int limit = 12,
  }) async {
    try {
      final rows = await _db
          .from('tenant_checkout_sessions')
          .select(
            'id, plan_key, source, status, provider, provider_reference, return_url, created_at, updated_at, returned_at, confirmed_at, canceled_at, expires_at',
          )
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map(
            (row) => TenantCheckoutSession.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar sessões de checkout.');
    } catch (e) {
      throw UnexpectedError(
        'Erro ao carregar sessões de checkout.',
        e.toString(),
      );
    }
  }

  Future<PlanUpdateResult> confirmCheckoutSession({
    required String checkoutSessionId,
    String? note,
    String? providerReference,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final row = await _db.rpc(
        'confirm_current_tenant_checkout_session',
        params: {
          'p_checkout_session_id': checkoutSessionId,
          'p_note': note,
          'p_provider_reference': providerReference,
          'p_metadata': metadata ?? const <String, dynamic>{},
        },
      );
      final data = Map<String, dynamic>.from(row as Map);
      return PlanUpdateResult(
        plan: resolveTenantPlan(data['plan_key'] as String?),
        billingStatus: data['billing_status'] as String? ?? 'active',
        trialEndsAt: data['trial_ends_at'] == null
            ? null
            : DateTime.tryParse(data['trial_ends_at'] as String),
        planSelectedAt: data['plan_selected_at'] == null
            ? null
            : DateTime.tryParse(data['plan_selected_at'] as String),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao confirmar checkout.');
    } catch (e) {
      throw UnexpectedError('Erro ao confirmar checkout.', e.toString());
    }
  }

  Future<TenantCheckoutSession> closeCheckoutSession({
    required String checkoutSessionId,
    required String targetStatus,
    String? note,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final row = await _db.rpc(
        'close_current_tenant_checkout_session',
        params: {
          'p_checkout_session_id': checkoutSessionId,
          'p_target_status': targetStatus,
          'p_note': note,
          'p_metadata': metadata ?? const <String, dynamic>{},
        },
      );
      return TenantCheckoutSession.fromMap(
        Map<String, dynamic>.from(row as Map),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao encerrar checkout.');
    } catch (e) {
      throw UnexpectedError('Erro ao encerrar checkout.', e.toString());
    }
  }

  Future<List<TenantBillingWebhookEvent>> listBillingWebhookEvents(
    String tenantId, {
    int limit = 12,
  }) async {
    try {
      final rows = await _db
          .from('tenant_billing_webhook_events')
          .select(
            'id, provider, provider_event_id, provider_reference, event_type, processing_status, processing_note, checkout_session_id, received_at, processed_at',
          )
          .eq('tenant_id', tenantId)
          .order('received_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map(
            (row) => TenantBillingWebhookEvent.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao carregar webhooks de cobrança.');
    } catch (e) {
      throw UnexpectedError(
        'Erro ao carregar webhooks de cobrança.',
        e.toString(),
      );
    }
  }

  Future<TenantBillingWebhookEvent> registerBillingWebhookEvent({
    required String provider,
    required String eventType,
    String? providerEventId,
    String? checkoutSessionId,
    String? providerReference,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final row = await _db.rpc(
        'register_current_tenant_billing_webhook_event',
        params: {
          'p_provider': provider,
          'p_event_type': eventType,
          'p_provider_event_id': providerEventId,
          'p_checkout_session_id': checkoutSessionId,
          'p_provider_reference': providerReference,
          'p_payload': payload ?? const <String, dynamic>{},
        },
      );
      return TenantBillingWebhookEvent.fromMap(
        Map<String, dynamic>.from(row as Map),
      );
    } on PostgrestException catch (e) {
      throw _mapError(e, 'Erro ao registrar webhook.');
    } catch (e) {
      throw UnexpectedError('Erro ao registrar webhook.', e.toString());
    }
  }

  AppError _mapError(PostgrestException e, String fallback) {
    final message = e.message.trim();
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Voce nao tem permissao para editar configurações.',
      );
    }
    if (e.code == '22023') {
      return const ValidationError('Plano inválido.');
    }
    if (e.code == 'P0001') {
      return BusinessRuleError(message);
    }
    if (message.isNotEmpty) {
      if (message.contains('sem permissão') ||
          message.contains('sem permissao')) {
        return const PermissionError(
          'Voce nao tem permissao para editar configurações.',
        );
      }
      if (message.contains('Não é possível') ||
          message.contains('Nao e possivel') ||
          message.contains('Plano inválido') ||
          message.contains('Plano invalido')) {
        return BusinessRuleError(message);
      }
    }
    return UnexpectedError(fallback, '${e.code}: $message');
  }
}
