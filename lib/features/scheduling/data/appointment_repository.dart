import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/appointment.dart';
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
            '*, customers(name), service_requests(title), appointment_assignments!inner(technician_user_id, profiles(full_name, phone))',
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

      final rows = await query.order('scheduled_start');
      return (rows as List<dynamic>)
          .map((row) => appointmentFromRow(row as Map<String, dynamic>))
          .toList();
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
            '*, customers(name), service_requests(title), appointment_assignments(technician_user_id, profiles(full_name, phone))',
          )
          .eq('id', id)
          .single();
      return appointmentFromRow(row);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        throw const NotFoundError('Agendamento nao encontrado.');
      }
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao carregar agendamento.', e.toString());
    }
  }

  Future<Appointment> schedule({
    required Appointment appointment,
    required String technicianUserId,
  }) async {
    try {
      final appointmentId = await _db.rpc(
        'schedule_appointment',
        params: appointment.toScheduleParams(technicianUserId),
      );
      return get(appointmentId as String);
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError('Erro ao agendar atendimento.', e.toString());
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
    if (e.code == '23P01' || e.code == '23514' || e.code == 'P0001') {
      return const BusinessRuleError(
        'Este tecnico ja possui atendimento neste periodo.',
      );
    }
    return UnexpectedError(
      'Operacao de agenda falhou. Tente novamente.',
      '${e.code}: ${e.message}',
    );
  }
}
