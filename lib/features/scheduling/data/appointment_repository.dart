import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/appointment.dart';
import '../domain/appointment_event.dart';
import '../domain/technician.dart';

class AppointmentFilter {
  const AppointmentFilter({
    this.status,
    this.from,
    this.to,
    this.technicianUserId,
    this.serviceRequestId,
  });

  final AppointmentStatus? status;
  final DateTime? from;
  final DateTime? to;
  final String? technicianUserId;
  final String? serviceRequestId;
}

class AppointmentRepository {
  AppointmentRepository(this._client);

  final SupabaseClient? _client;

  static const _table = 'appointments';

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<List<Appointment>> list({
    AppointmentFilter filter = const AppointmentFilter(),
  }) async {
    try {
      var query = _db.from(_table).select(
            '*, customers(name), appointment_assignments!inner(technician_user_id, professional_id, revoked_at, profiles(full_name, phone), service_professionals(name, category))',
          );

      if (filter.status != null) {
        query = query.eq('status', filter.status!.value);
      }
      if (filter.from != null) {
        query = query.gte(
            'scheduled_start', filter.from!.toUtc().toIso8601String());
      }
      if (filter.to != null) {
        query =
            query.lt('scheduled_start', filter.to!.toUtc().toIso8601String());
      }
      if (filter.serviceRequestId != null) {
        query = query
            .eq('kind', AppointmentKind.visit.value)
            .eq('reference_id', filter.serviceRequestId!);
      }
      if (filter.technicianUserId != null) {
        query = query.eq(
          'appointment_assignments.technician_user_id',
          filter.technicianUserId!,
        );
      }

      final rows = (await query.order('scheduled_start') as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      await _attachReferenceTitles(rows);
      return rows.map(appointmentFromRow).toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar agenda.', e.toString());
    }
  }

  Future<Appointment> get(String id) async {
    try {
      final row = await _db
          .from(_table)
          .select(
            '*, customers(name), appointment_assignments(technician_user_id, professional_id, revoked_at, profiles(full_name, phone), service_professionals(name, category))',
          )
          .eq('id', id)
          .single();
      final enriched = Map<String, dynamic>.from(row);
      await _attachReferenceTitles([enriched]);
      return appointmentFromRow(enriched);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw const NotFoundError('Agendamento nao encontrado.');
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar agendamento.', e.toString());
    }
  }

  /// Preenche `service_requests.title` em cada linha.
  ///
  /// Não dá para usar embed do PostgREST aqui: `reference_id` aponta para
  /// `service_requests` **ou** `work_orders` conforme o `kind`, e a 0051
  /// removeu a FK fixa para `service_requests` justamente por isso. Sem FK o
  /// PostgREST não infere o relacionamento e responde PGRST200.
  Future<void> _attachReferenceTitles(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;

    final requestIds = <String>{};
    final workOrderIds = <String>{};
    for (final row in rows) {
      final id = row['reference_id'];
      if (id is! String) continue;
      if (row['kind'] == AppointmentKind.workOrder.value) {
        workOrderIds.add(id);
      } else {
        requestIds.add(id);
      }
    }

    final titles = <String, String>{};

    if (requestIds.isNotEmpty) {
      final found = await _db
          .from('service_requests')
          .select('id, title')
          .inFilter('id', requestIds.toList());
      for (final row in (found as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        titles[map['id'] as String] = map['title'] as String? ?? '';
      }
    }

    if (workOrderIds.isNotEmpty) {
      final found = await _db
          .from('work_orders')
          .select('id, title')
          .inFilter('id', workOrderIds.toList());
      for (final row in (found as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        titles[map['id'] as String] = map['title'] as String? ?? '';
      }
    }

    for (final row in rows) {
      final title = titles[row['reference_id']];
      row['service_requests'] = title == null ? null : {'title': title};
    }
  }

  Future<Appointment> schedule({
    required Appointment appointment,
    required String professionalId,
    String? technicianUserId,
  }) async {
    try {
      final appointmentId = await _db.rpc(
        'schedule_appointment',
        params: appointment.toScheduleParams(
          professionalId: professionalId,
          technicianUserId: technicianUserId,
        ),
      );
      return get(appointmentId as String);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao agendar atendimento.', e.toString());
    }
  }

  /// Cancela e devolve o item para a fila de todos os profissionais da
  /// categoria. Aceita tanto quem tem appointments.write quanto o próprio
  /// técnico atribuído — a checagem é feita no banco.
  Future<void> cancel({
    required String appointmentId,
    String? reason,
  }) async {
    try {
      await _db.rpc(
        'cancel_appointment',
        params: {
          'p_appointment_id': appointmentId,
          'p_reason': (reason == null || reason.trim().isEmpty)
              ? null
              : reason.trim(),
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao cancelar atendimento.', e.toString());
    }
  }

  /// Acrescenta um profissional ao atendimento. Pode ser de outra categoria —
  /// um serviço pode exigir eletricista mais ajudante. Idempotente.
  Future<void> assignTechnician({
    required String appointmentId,
    required String professionalId,
  }) async {
    try {
      await _db.rpc(
        'assign_technician',
        params: {
          'p_appointment_id': appointmentId,
          'p_professional_id': professionalId,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao atribuir profissional.', e.toString());
    }
  }

  /// Remove um profissional. O banco recusa remover o último — para esvaziar
  /// o horário use [cancel], que devolve o item para a fila.
  Future<void> unassignTechnician({
    required String appointmentId,
    required String professionalId,
  }) async {
    try {
      await _db.rpc(
        'unassign_technician',
        params: {
          'p_appointment_id': appointmentId,
          'p_professional_id': professionalId,
        },
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao remover profissional.', e.toString());
    }
  }

  /// Marca o atendimento como realizado. O trigger de `appointments` registra
  /// o `status_changed` no histórico — não precisa de RPC própria.
  Future<void> markDone(String appointmentId) async {
    try {
      await _db
          .from(_table)
          .update({'status': AppointmentStatus.done.value})
          .eq('id', appointmentId);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao confirmar atendimento.', e.toString());
    }
  }

  /// Histórico de um agendamento, do mais recente para o mais antigo.
  Future<List<AppointmentEvent>> listEvents(String appointmentId) async {
    try {
      final rows = await _db
          .from('appointment_events')
          .select('*, profiles(full_name)')
          .eq('appointment_id', appointmentId)
          .order('created_at', ascending: false)
          .order('id', ascending: false);
      return (rows as List<dynamic>)
          .map((row) => appointmentEventFromRow(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar histórico.', e.toString());
    }
  }

  /// Chaves 'kind:reference_id' com agendamento ativo (não cancelado). Serve
  /// para tirar da fila o que já foi agendado para algum profissional.
  Future<Set<String>> listScheduledReferenceKeys() async {
    try {
      final rows = await _db
          .from(_table)
          .select('kind, reference_id')
          .neq('status', AppointmentStatus.cancelled.value);
      return {
        for (final row in (rows as List<dynamic>))
          '${(row as Map)['kind']}:${row['reference_id']}',
      };
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar agendamentos.', e.toString());
    }
  }

  Future<List<Technician>> listTechnicians() async {
    try {
      final rows = await _db
          .from('service_professionals')
          .select(
            'id, linked_user_id, name, email, phone, category, kind',
          )
          .eq('is_active', true)
          .order('category')
          .order('name');
      return (rows as List<dynamic>)
          .map(
            (row) => technicianFromRow(
              <String, dynamic>{
                'professional_id': row['id'],
                'user_id': row['linked_user_id'],
                'name': row['name'],
                'email': row['email'],
                'phone': row['phone'],
                'category': row['category'],
                'kind': row['kind'],
              },
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar tecnicos.', e.toString());
    }
  }

  AppError _mapError(PostgrestException e) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError('Voce nao tem permissao para esta agenda.');
    }
    // Coluna/relacionamento/função que o app usa e o banco não tem: o schema
    // está atrás do código. Sem esta ramificação vira "operação falhou, tente
    // novamente" — e tentar de novo nunca resolve.
    if (e.code == '42703' || // coluna inexistente
        e.code == '42883' || // função inexistente
        e.code == 'PGRST200' || // relacionamento não encontrado
        e.code == 'PGRST202' || // RPC não encontrada
        e.code == 'PGRST203') {
      // RPC ambígua (dois overloads)
      return BusinessRuleError(
        'A agenda depende de uma atualização de banco que ainda não foi '
        'aplicada. Rode as migrations pendentes (supabase db push). '
        'Detalhe: ${e.code} ${e.message}',
      );
    }
    if (e.code == '23P01' || e.code == '23514' || e.code == 'P0001') {
      // As RPCs de agenda levantam check_violation com mensagem pronta para o
      // usuário ("já possui atendimento neste período", "precisa de ao menos
      // um profissional", "atendimento encerrado"). Fixar um texto só aqui
      // fazia toda regra virar "técnico ocupado", que quase sempre mentia.
      final message = e.message.trim();
      return BusinessRuleError(
        message.isEmpty
            ? 'Não foi possível concluir a operação na agenda.'
            : message,
      );
    }
    return UnexpectedError(
      'Operacao de agenda falhou. Tente novamente.',
      '${e.code}: ${e.message}',
    );
  }
}
