import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/scheduling/domain/appointment.dart';

void main() {
  group('AppointmentStatus', () {
    test('fromValue e value sao simetricos', () {
      for (final status in AppointmentStatus.values) {
        expect(AppointmentStatus.fromValue(status.value), status);
      }
    });

    test('identifica estados finais', () {
      expect(AppointmentStatus.done.isTerminal, isTrue);
      expect(AppointmentStatus.cancelled.isTerminal, isTrue);
      expect(AppointmentStatus.noShow.isTerminal, isTrue);
      expect(AppointmentStatus.scheduled.isTerminal, isFalse);
    });
  });

  group('Appointment', () {
    test('recusa periodo sem duracao positiva', () {
      final start = DateTime.utc(2026, 7, 21, 13);
      final end = DateTime.utc(2026, 7, 21, 12);

      expect(
        () => Appointment(
          id: 'appt-001',
          tenantId: 'tenant-001',
          kind: AppointmentKind.visit,
          referenceId: 'sr-001',
          customerId: 'customer-001',
          scheduledStart: start,
          scheduledEnd: end,
          status: AppointmentStatus.scheduled,
          createdAt: start,
          updatedAt: start,
        ),
        throwsArgumentError,
      );
    });

    test('toScheduleParams omite tenant_id e metadados server-side', () {
      final start = DateTime.utc(2026, 7, 21, 13);
      final end = DateTime.utc(2026, 7, 21, 15);
      final appointment = Appointment(
        id: 'appt-001',
        tenantId: 'tenant-001',
        kind: AppointmentKind.visit,
        referenceId: 'sr-001',
        customerId: 'customer-001',
        addressId: 'addr-001',
        scheduledStart: start,
        scheduledEnd: end,
        status: AppointmentStatus.scheduled,
        notes: 'Cliente disponivel a tarde.',
        createdAt: start,
        updatedAt: start,
        createdBy: 'user-001',
      );

      final params = appointment.toScheduleParams(
        professionalId: 'prof-001',
        technicianUserId: 'tech-001',
      );

      expect(params['p_kind'], 'visit');
      expect(params['p_reference_id'], 'sr-001');
      expect(params['p_customer_id'], 'customer-001');
      expect(params['p_professional_id'], 'prof-001');
      expect(params['p_technician_user_id'], 'tech-001');
      expect(params.containsKey('tenant_id'), isFalse);
      expect(params.containsKey('created_by'), isFalse);
    });
  });
}
