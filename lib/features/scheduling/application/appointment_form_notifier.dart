import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../domain/appointment.dart';
import 'appointment_list_notifier.dart';

sealed class AppointmentFormState {
  const AppointmentFormState();
}

final class AppointmentFormIdle extends AppointmentFormState {
  const AppointmentFormIdle();
}

final class AppointmentFormLoading extends AppointmentFormState {
  const AppointmentFormLoading();
}

final class AppointmentFormSuccess extends AppointmentFormState {
  const AppointmentFormSuccess({required this.appointment});

  final Appointment appointment;
}

final class AppointmentFormError extends AppointmentFormState {
  const AppointmentFormError({required this.error});

  final AppError error;
}

class AppointmentFormNotifier extends Notifier<AppointmentFormState> {
  @override
  AppointmentFormState build() => const AppointmentFormIdle();

  Future<void> scheduleAppointment({
    required AppointmentKind kind,
    required String referenceId,
    required String customerId,
    required String professionalId,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    String? technicianUserId,
    String? addressId,
    String? notes,
  }) async {
    state = const AppointmentFormLoading();

    try {
      final appointment = Appointment(
        id: '',
        tenantId: '',
        kind: kind,
        referenceId: referenceId,
        customerId: customerId,
        addressId: _emptyToNull(addressId),
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        status: AppointmentStatus.scheduled,
        notes: _emptyToNull(notes),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final created = await ref.read(appointmentRepositoryProvider).schedule(
            appointment: appointment,
            professionalId: professionalId,
            technicianUserId: technicianUserId,
          );
      ref.read(appointmentListProvider.notifier).addOrReplace(created);
      state = AppointmentFormSuccess(appointment: created);
    } on AppError catch (e) {
      state = AppointmentFormError(error: e);
    } on ArgumentError catch (e) {
      state = AppointmentFormError(
        error: ValidationError(e.message?.toString() ?? 'Periodo invalido.'),
      );
    } catch (e) {
      state = AppointmentFormError(
        error: UnexpectedError('Erro ao agendar atendimento.', e.toString()),
      );
    }
  }

  Future<void> scheduleVisit({
    required String serviceRequestId,
    required String customerId,
    required String professionalId,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    String? technicianUserId,
    String? addressId,
    String? notes,
  }) =>
      scheduleAppointment(
        kind: AppointmentKind.visit,
        referenceId: serviceRequestId,
        customerId: customerId,
        professionalId: professionalId,
        technicianUserId: technicianUserId,
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        addressId: addressId,
        notes: notes,
      );

  void reset() => state = const AppointmentFormIdle();
}

String? _emptyToNull(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

final appointmentFormProvider =
    NotifierProvider<AppointmentFormNotifier, AppointmentFormState>(
  AppointmentFormNotifier.new,
);
