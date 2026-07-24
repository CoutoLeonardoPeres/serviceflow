import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:serviceflow/core/error/app_error.dart';
import 'package:serviceflow/features/scheduling/application/appointment_form_notifier.dart';
import 'package:serviceflow/features/scheduling/application/appointment_list_notifier.dart';
import 'package:serviceflow/features/scheduling/data/appointment_repository.dart';
import 'package:serviceflow/features/scheduling/domain/appointment.dart';

class _FakeAppointmentRepository extends AppointmentRepository {
  _FakeAppointmentRepository({
    this.created,
    this.error,
  }) : super(null);

  final Appointment? created;
  final Object? error;
  Appointment? lastInput;
  String? lastTechnicianId;

  @override
  Future<Appointment> schedule({
    required Appointment appointment,
    required String technicianUserId,
  }) async {
    lastInput = appointment;
    lastTechnicianId = technicianUserId;
    if (error != null) throw error!;
    return created!;
  }
}

Appointment appointmentFixture() {
  final start = DateTime.utc(2026, 7, 21, 13);
  return Appointment(
    id: 'appt-001',
    tenantId: 'tenant-001',
    kind: AppointmentKind.visit,
    referenceId: 'sr-001',
    customerId: 'customer-001',
    scheduledStart: start,
    scheduledEnd: start.add(const Duration(hours: 2)),
    status: AppointmentStatus.scheduled,
    createdAt: start,
    updatedAt: start,
  );
}

void main() {
  ProviderContainer makeContainer(AppointmentRepository repo) =>
      ProviderContainer(
        overrides: [
          appointmentRepositoryProvider.overrideWithValue(repo),
          appointmentListProvider.overrideWith(AppointmentListNotifier.new),
        ],
      );

  group('AppointmentFormNotifier', () {
    test('comeca em idle', () {
      final container = makeContainer(
        _FakeAppointmentRepository(created: appointmentFixture()),
      );
      addTearDown(container.dispose);

      expect(
          container.read(appointmentFormProvider), isA<AppointmentFormIdle>());
    });

    test('agenda visita com periodo e tecnico selecionado', () async {
      final repo = _FakeAppointmentRepository(created: appointmentFixture());
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      final start = DateTime.utc(2026, 7, 21, 13);

      await container.read(appointmentFormProvider.notifier).scheduleVisit(
            serviceRequestId: 'sr-001',
            customerId: 'customer-001',
            technicianUserId: 'tech-001',
            scheduledStart: start,
            scheduledEnd: start.add(const Duration(hours: 2)),
            notes: '  Cliente disponivel a tarde.  ',
          );

      final state = container.read(appointmentFormProvider);
      expect(state, isA<AppointmentFormSuccess>());
      expect(repo.lastInput?.kind, AppointmentKind.visit);
      expect(repo.lastInput?.referenceId, 'sr-001');
      expect(repo.lastInput?.notes, 'Cliente disponivel a tarde.');
      expect(repo.lastTechnicianId, 'tech-001');
    });

    test('conflito de agenda vira erro de regra de negocio', () async {
      final repo = _FakeAppointmentRepository(
        error: const BusinessRuleError(
          'Este tecnico ja possui atendimento neste periodo.',
        ),
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      final start = DateTime.utc(2026, 7, 21, 13);

      await container.read(appointmentFormProvider.notifier).scheduleVisit(
            serviceRequestId: 'sr-001',
            customerId: 'customer-001',
            technicianUserId: 'tech-001',
            scheduledStart: start,
            scheduledEnd: start.add(const Duration(hours: 2)),
          );

      final state = container.read(appointmentFormProvider);
      expect(state, isA<AppointmentFormError>());
      expect((state as AppointmentFormError).error, isA<BusinessRuleError>());
    });
  });
}
