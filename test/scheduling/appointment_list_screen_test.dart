import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:serviceflow/features/scheduling/application/appointment_list_notifier.dart';
import 'package:serviceflow/features/scheduling/data/appointment_repository.dart';
import 'package:serviceflow/features/scheduling/domain/appointment.dart';
import 'package:serviceflow/features/scheduling/domain/technician.dart';
import 'package:serviceflow/features/scheduling/presentation/appointment_list_screen.dart';

class _FakeAppointmentRepository extends AppointmentRepository {
  _FakeAppointmentRepository() : super(null);

  @override
  Future<List<Appointment>> list({
    AppointmentFilter filter = const AppointmentFilter(),
  }) async =>
      <Appointment>[];

  @override
  Future<List<Technician>> listTechnicians() async => const [
        Technician(
          professionalId: 'prof-1',
          userId: 'tech-1',
          name: 'João',
          category: 'Eletricista',
          kind: 'internal',
        ),
        Technician(
          professionalId: 'prof-2',
          name: 'Carlos',
          category: 'Bombeiro hidráulico',
          kind: 'partner',
        ),
      ];
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('AppointmentListScreen mostra calendario mensal e muda meses',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentRepositoryProvider.overrideWithValue(
            _FakeAppointmentRepository(),
          ),
        ],
        child: const MaterialApp(
          home: AppointmentListScreen(),
        ),
      ),
    );
    // O calendario abre como popup no primeiro frame — sem assentar a
    // animacao do dialog, nada dele existe ainda na arvore.
    await tester.pumpAndSettle();

    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Livre'), findsOneWidget);
    expect(find.text('Ocupado'), findsOneWidget);
    expect(find.byTooltip('Próximo mês'), findsOneWidget);

    final currentMonth = find.byKey(const ValueKey('calendar-month-title'));
    final before = tester.widget<Text>(currentMonth).data;
    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    final after = tester.widget<Text>(currentMonth).data;

    expect(after, isNot(before));
  });

  testWidgets('AppointmentListScreen abre popup ao tocar em um dia',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentRepositoryProvider.overrideWithValue(
            _FakeAppointmentRepository(),
          ),
        ],
        child: const MaterialApp(
          home: AppointmentListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-day-15')));
    await tester.pumpAndSettle();

    expect(find.text('Horários do dia'), findsOneWidget);
    expect(find.text('Profissionais'), findsWidgets);
    expect(find.text('Visão geral'), findsWidgets);
    // Aparece na sidebar do calendario e na do dia.
    expect(find.text('Carlos'), findsWidgets);
  });
}
