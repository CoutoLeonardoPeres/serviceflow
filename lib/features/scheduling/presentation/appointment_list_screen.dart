import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../customers/application/customer_list_notifier.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/domain/customer.dart';
import '../../professionals/domain/professional_categories.dart';
import '../../service_requests/application/service_request_list_notifier.dart';
import '../../service_requests/data/service_request_repository.dart';
import '../../service_requests/domain/service_request.dart';
import '../../service_requests/presentation/service_request_form_screen.dart';
import '../../settings/domain/schedule_models.dart';
import '../../settings/presentation/settings_screen.dart'
    show companySettingsProvider;
import '../../work_orders/application/work_order_list_notifier.dart';
import '../../work_orders/domain/work_order.dart';
import '../../work_orders/presentation/work_order_form_screen.dart';
import '../application/appointment_form_notifier.dart';
import '../application/appointment_list_notifier.dart';
import '../data/appointment_repository.dart';
import '../domain/appointment.dart';
import '../domain/technician.dart';

final _calendarSchedulableRequestsProvider =
    FutureProvider.autoDispose<List<ServiceRequest>>((ref) async {
  final result = await ref.read(serviceRequestRepositoryProvider).listPaged(
        filter: const ServiceRequestFilter(),
      );
  return result.items.where((request) => !request.status.isTerminal).toList();
});

final _calendarSchedulableCustomersProvider =
    FutureProvider.autoDispose<List<Customer>>((ref) async {
  final result = await ref.read(customerRepositoryProvider).listPaged(
        filter: const CustomerFilter(isActive: true),
      );
  return result.items;
});

final _calendarSchedulableWorkOrdersProvider =
    FutureProvider.autoDispose<List<WorkOrder>>((ref) async {
  final result = await ref.read(workOrderRepositoryProvider).listPaged();
  return result.items
      .where(
        (workOrder) =>
            workOrder.status != WorkOrderStatus.done &&
            workOrder.status != WorkOrderStatus.cancelled,
      )
      .toList();
});

/// Um chamado ou OS esperando agendamento. Vira card arrastável na fila do
/// profissional cuja categoria bate com a do item.
class _QueueItem {
  const _QueueItem({
    required this.kind,
    required this.referenceId,
    required this.label,
    required this.customerId,
    required this.customerName,
    this.addressId,
    this.categoryName,
    this.customerPhone,
    this.district,
    this.city,
  });

  final AppointmentKind kind;
  final String referenceId;
  final String label;
  final String customerId;
  final String customerName;
  final String? addressId;
  final String? categoryName;
  final String? customerPhone;
  final String? district;
  final String? city;

  String get key => '${kind.value}:$referenceId';

  String get placeLabel {
    final parts = [district, city].where(
      (part) => part != null && part.trim().isNotEmpty,
    );
    return parts.isEmpty ? 'Endereço não informado' : parts.join(' · ');
  }
}

final _scheduledReferenceKeysProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  return ref.read(appointmentRepositoryProvider).listScheduledReferenceKeys();
});

/// Fila de trabalho: chamados e OS ativos que ainda não têm agendamento.
/// Agendar para um profissional remove o item da fila de todos os outros,
/// porque a chave sai desta lista assim que o appointment é criado.
final _workQueueProvider =
    FutureProvider.autoDispose<List<_QueueItem>>((ref) async {
  final scheduled = await ref.watch(_scheduledReferenceKeysProvider.future);
  final requests =
      await ref.watch(_calendarSchedulableRequestsProvider.future);
  final workOrders =
      await ref.watch(_calendarSchedulableWorkOrdersProvider.future);

  final items = <_QueueItem>[
    for (final request in requests)
      _QueueItem(
        kind: AppointmentKind.visit,
        referenceId: request.id,
        label: '${request.displayNumber} · ${request.title}',
        customerId: request.customerId,
        customerName: request.customerName ?? 'Cliente não informado',
        addressId: request.addressId,
        categoryName: request.categoryName,
        customerPhone: request.customerPhone,
        district: request.routeDistrict,
        city: request.routeCity,
      ),
    for (final workOrder in workOrders)
      _QueueItem(
        kind: AppointmentKind.workOrder,
        referenceId: workOrder.id,
        label: '${workOrder.displayNumber} · ${workOrder.title}',
        customerId: workOrder.customerId,
        customerName: workOrder.customerName ?? 'Cliente não informado',
        addressId: workOrder.addressId,
        categoryName: workOrder.categoryName,
        customerPhone: workOrder.customerPhone,
        district: workOrder.routeDistrict,
        city: workOrder.routeCity,
      ),
  ];

  return items.where((item) => !scheduled.contains(item.key)).toList();
});

class AppointmentListScreen extends ConsumerStatefulWidget {
  const AppointmentListScreen({super.key});

  @override
  ConsumerState<AppointmentListScreen> createState() =>
      _AppointmentListScreenState();
}

class _AppointmentListScreenState extends ConsumerState<AppointmentListScreen> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMonth());
  }

  void _loadMonth() {
    final start = DateTime(_visibleMonth.year, _visibleMonth.month);
    final end = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    ref.read(appointmentListProvider.notifier).load(
          filter: AppointmentFilter(from: start, to: end),
        );
  }

  void _moveMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
    _loadMonth();
  }

  Future<void> _openScheduleDialog(
    DateTime day,
    List<Appointment> appointments,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DayScheduleDialog(
        initialDate: day,
        appointments: appointments,
      ),
    );
    if (mounted) {
      ref.read(appointmentListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appointmentListProvider);
    final appointmentsByDay = _groupByDay(state.items);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(appointmentListProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(appointmentListProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _CalendarHeader(
              month: _visibleMonth,
              onPrevious: () => _moveMonth(-1),
              onNext: () => _moveMonth(1),
            ),
            const SizedBox(height: 14),
            const _LegendRow(),
            const SizedBox(height: 14),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ErrorView(
                  message: state.error!.userMessage,
                  onRetry: () =>
                      ref.read(appointmentListProvider.notifier).refresh(),
                ),
              ),
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            _CalendarGrid(
              month: _visibleMonth,
              appointmentsByDay: appointmentsByDay,
              onDayTap: (day) => _openScheduleDialog(
                  day, appointmentsByDay[day.day] ?? const []),
              weeklySchedule: ref.watch(companySettingsProvider).maybeWhen(
                    data: (settings) => settings.weeklySchedule,
                    orElse: defaultWeeklySchedule,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SlotAction { serviceRequest, quote, workOrder }

class _SlotActionDialog extends StatelessWidget {
  const _SlotActionDialog({required this.slot});

  final DateTime slot;

  @override
  Widget build(BuildContext context) {
    final label =
        DateFormat("EEEE, d 'de' MMMM 'às' HH:mm", 'pt_BR').format(slot);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: NeomorphicPanel(
          borderRadius: 30,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'O que deseja criar?',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${label[0].toUpperCase()}${label.substring(1)}',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _DayActionCard(
                    icon: Icons.support_agent_outlined,
                    title: 'Chamado',
                    subtitle: 'Abrir um novo chamado para este cliente.',
                    onTap: () =>
                        Navigator.of(context).pop(_SlotAction.serviceRequest),
                  ),
                  _DayActionCard(
                    icon: Icons.request_quote_outlined,
                    title: 'Orçamento',
                    subtitle: 'Agendar orçamento neste horário.',
                    onTap: () => Navigator.of(context).pop(_SlotAction.quote),
                  ),
                  _DayActionCard(
                    icon: Icons.engineering_outlined,
                    title: 'OS',
                    subtitle: 'Agendar execução neste horário.',
                    onTap: () =>
                        Navigator.of(context).pop(_SlotAction.workOrder),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayActionCard extends StatelessWidget {
  const _DayActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 175,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: Colors.white.withValues(alpha: 0.6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: 0.08),
                  offset: const Offset(8, 10),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('MMMM de yyyy', 'pt_BR').format(month);
    return NeomorphicPanel(
      borderRadius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mês anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              label[0].toUpperCase() + label.substring(1),
              key: const ValueKey('calendar-month-title'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Próximo mês',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 18,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _LegendItem(color: Color(0xFFA9DADB), label: 'Livre'),
        _LegendItem(color: Color(0xFFB77A9B), label: 'Ocupado'),
        _LegendItem(color: Color(0xFFAEB8C4), label: 'Fechado'),
        _LegendItem(color: _kQuoteColor, label: 'Orçamento'),
        _LegendItem(color: _kWorkOrderColor, label: 'Ordem de serviço'),
        Text('Manhã (esq.) | Tarde (dir.) | Noite (abaixo)'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.appointmentsByDay,
    required this.onDayTap,
    required this.weeklySchedule,
  });

  final DateTime month;
  final Map<int, List<Appointment>> appointmentsByDay;
  final ValueChanged<DateTime> onDayTap;
  final Map<String, DaySchedule> weeklySchedule;

  @override
  Widget build(BuildContext context) {
    final days = _calendarDays(month);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 760 ? 2 : 7;
        return Column(
          children: [
            if (columns == 7)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    _Weekday('Seg'),
                    _Weekday('Ter'),
                    _Weekday('Qua'),
                    _Weekday('Qui'),
                    _Weekday('Sex'),
                    _Weekday('Sáb'),
                    _Weekday('Dom'),
                  ],
                ),
              ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: days.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: columns == 7 ? 1.75 : 2.45,
              ),
              itemBuilder: (context, index) {
                final day = days[index];
                if (day == null) return const SizedBox.shrink();
                final items = appointmentsByDay[day.day] ?? const [];
                final isClosed = day.weekday == DateTime.sunday;
                return _CalendarDayCard(
                  day: day,
                  appointments: items,
                  isClosed: isClosed,
                  onTap: isClosed ? null : () => onDayTap(day),
                  daySchedule:
                      weeklySchedule[kWeekdayOrder[day.weekday - 1]] ??
                          defaultDaySchedule(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _Weekday extends StatelessWidget {
  const _Weekday(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _CalendarDayCard extends StatelessWidget {
  const _CalendarDayCard({
    required this.day,
    required this.appointments,
    required this.isClosed,
    required this.onTap,
    required this.daySchedule,
  });

  final DateTime day;
  final List<Appointment> appointments;
  final bool isClosed;
  final VoidCallback? onTap;
  final DaySchedule daySchedule;

  @override
  Widget build(BuildContext context) {
    final hasAppointments = appointments.isNotEmpty;
    final baseColor = isClosed
        ? const Color(0xFFAEB8C4)
        : hasAppointments
            ? const Color(0xFFB77A9B)
            : const Color(0xFFA9DADB);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('calendar-day-${day.day}'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isToday(day)
                  ? const Color(0xFFB2537F)
                  : Colors.white.withValues(alpha: 0.2),
              width: _isToday(day) ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withValues(
                      alpha: isClosed ? 0.06 : 0.1,
                    ),
                offset: const Offset(7, 10),
                blurRadius: 18,
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF40505D),
                      ),
                ),
              ),
              // Marcadores de ocupação: manhã à esquerda, tarde à direita,
              // noite embaixo. Só aparecem onde há agendamento.
              if (!isClosed) ..._occupancyMarkers(),
              if (isClosed)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF52606D),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'Fechado',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _occupancyMarkers() {
    final morning = <Appointment>[];
    final afternoon = <Appointment>[];
    final night = <Appointment>[];
    for (final appointment in appointments) {
      switch (_periodOf(appointment.scheduledStart, daySchedule)) {
        case _DayPeriod.morning:
          morning.add(appointment);
        case _DayPeriod.afternoon:
          afternoon.add(appointment);
        case _DayPeriod.night:
          night.add(appointment);
      }
    }
    return [
      if (morning.isNotEmpty)
        Positioned(
          left: 6,
          top: 6,
          bottom: 6,
          child: _MarkerStack(appointments: morning, horizontal: false),
        ),
      if (afternoon.isNotEmpty)
        Positioned(
          right: 6,
          top: 6,
          bottom: 6,
          child: _MarkerStack(appointments: afternoon, horizontal: false),
        ),
      if (night.isNotEmpty)
        Positioned(
          left: 0,
          right: 0,
          bottom: 5,
          child: Center(
            child: _MarkerStack(appointments: night, horizontal: true),
          ),
        ),
    ];
  }
}

enum _DayPeriod { morning, afternoon, night }

/// Classifica pelo horário de funcionamento do dia; se o período estiver
/// desligado ou sem horário definido, cai no corte padrão 12h/18h.
_DayPeriod _periodOf(DateTime start, DaySchedule schedule) {
  final minutes = start.hour * 60 + start.minute;
  bool inside(SchedulePeriod period) {
    if (!period.enabled) return false;
    final from = _minutesOf(period.start);
    final to = _minutesOf(period.end);
    if (from == null || to == null) return false;
    return minutes >= from && minutes < to;
  }

  if (inside(schedule.morning)) return _DayPeriod.morning;
  if (inside(schedule.afternoon)) return _DayPeriod.afternoon;
  if (inside(schedule.night)) return _DayPeriod.night;
  if (minutes < 12 * 60) return _DayPeriod.morning;
  if (minutes < 18 * 60) return _DayPeriod.afternoon;
  return _DayPeriod.night;
}

int? _minutesOf(String? value) {
  final parts = value?.split(':');
  if (parts == null || parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Azul = visita técnica (orçamento), vermelho = ordem de serviço.
const _kQuoteColor = Color(0xFF5B8FD4);
const _kWorkOrderColor = Color(0xFFE23B2E);

class _MarkerStack extends StatelessWidget {
  const _MarkerStack({required this.appointments, required this.horizontal});

  final List<Appointment> appointments;
  final bool horizontal;

  static const _maxMarkers = 4;

  @override
  Widget build(BuildContext context) {
    final visible = appointments.take(_maxMarkers).toList();
    final extra = appointments.length - visible.length;
    final markers = <Widget>[
      for (final appointment in visible)
        Container(
          width: 20,
          height: 12,
          margin: horizontal
              ? const EdgeInsets.symmetric(horizontal: 3)
              : const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: appointment.kind == AppointmentKind.workOrder
                ? _kWorkOrderColor
                : _kQuoteColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      if (extra > 0)
        Padding(
          padding: horizontal
              ? const EdgeInsets.symmetric(horizontal: 3)
              : const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            '+$extra',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF40505D),
                ),
          ),
        ),
    ];

    return horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: markers)
        : Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: markers,
          );
  }
}

class _DayScheduleDialog extends ConsumerStatefulWidget {
  const _DayScheduleDialog({
    required this.initialDate,
    required this.appointments,
  });

  final DateTime initialDate;
  final List<Appointment> appointments;

  @override
  ConsumerState<_DayScheduleDialog> createState() => _DayScheduleDialogState();
}

class _DayScheduleDialogState extends ConsumerState<_DayScheduleDialog> {
  String _selectedCategory = 'Todos';
  String? _selectedProfessionalId;
  final _createdHere = <Appointment>[];

  List<Appointment> get _allAppointments => [
        ...widget.appointments,
        ..._createdHere,
      ];

  @override
  Widget build(BuildContext context) {
    final techniciansAsync = ref.watch(techniciansProvider);
    final textTheme = Theme.of(context).textTheme;
    final dateLabel =
        DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(widget.initialDate);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1480, maxHeight: 980),
        child: NeomorphicPanel(
          borderRadius: 34,
          padding: EdgeInsets.zero,
          child: techniciansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) =>
                const Center(child: Text('Profissionais indisponíveis.')),
            data: (technicians) {
              final categories = [
                'Todos',
                ...{
                  for (final technician in technicians) technician.category,
                }.toList()
                  ..sort(compareCategoryNames),
              ];
              final visibleTechnicians = technicians
                  .where(
                    (technician) =>
                        _selectedCategory == 'Todos' ||
                        technician.category == _selectedCategory,
                  )
                  .toList();
              final effectiveProfessionalId = _selectedProfessionalId ??
                  (visibleTechnicians.isNotEmpty
                      ? visibleTechnicians.first.professionalId
                      : null);
              Technician? selectedTechnician;
              for (final technician in visibleTechnicians) {
                if (technician.professionalId == effectiveProfessionalId) {
                  selectedTechnician = technician;
                  break;
                }
              }
              final slots = _buildDaySlots(widget.initialDate);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Horários do dia',
                                style: textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${dateLabel[0].toUpperCase()}${dateLabel.substring(1)}',
                                style: textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 280,
                            child: _ProfessionSidebar(
                              selectedProfessionalId: effectiveProfessionalId,
                              technicians: visibleTechnicians,
                              onSelectGeneral: () => setState(
                                () => _selectedProfessionalId = null,
                              ),
                              onSelectTechnician: (technician) => setState(
                                () => _selectedProfessionalId =
                                    technician.professionalId,
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: categories
                                      .map(
                                        (category) => FilterChip(
                                          selected:
                                              _selectedCategory == category,
                                          label: Text(category),
                                          onSelected: (_) => setState(() {
                                            _selectedCategory = category;
                                            final stillVisible =
                                                visibleTechnicians.any(
                                              (technician) =>
                                                  technician.professionalId ==
                                                  _selectedProfessionalId,
                                            );
                                            if (!stillVisible) {
                                              _selectedProfessionalId = null;
                                            }
                                          }),
                                        ),
                                      )
                                      .toList(),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  selectedTechnician == null
                                      ? visibleTechnicians.isEmpty
                                          ? 'Nenhum profissional disponível'
                                          : 'Visão geral'
                                      : selectedTechnician.name,
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: visibleTechnicians.isEmpty
                                      ? Center(
                                          child: Text(
                                            'Cadastre ao menos um profissional ativo para abrir a agenda do dia.',
                                            textAlign: TextAlign.center,
                                            style: textTheme.bodyMedium,
                                          ),
                                        )
                                      : ListView(
                                          children: _buildPeriods(
                                            context: context,
                                            slots: slots,
                                            selectedTechnician:
                                                selectedTechnician,
                                            visibleTechnicians:
                                                visibleTechnicians,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPeriods({
    required BuildContext context,
    required List<DateTime> slots,
    required Technician? selectedTechnician,
    required List<Technician> visibleTechnicians,
  }) {
    final groups = <String, List<DateTime>>{
      'Manhã': slots.where((slot) => slot.hour < 12).toList(),
      'Tarde':
          slots.where((slot) => slot.hour >= 12 && slot.hour < 18).toList(),
      'Noite': slots.where((slot) => slot.hour >= 18).toList(),
    };

    return groups.entries
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = constraints.maxWidth;
                    final columns = maxWidth >= 1200
                        ? 6
                        : maxWidth >= 980
                            ? 5
                            : maxWidth >= 760
                                ? 4
                                : 3;
                    const spacing = 10.0;
                    final cardWidth =
                        (maxWidth - (spacing * (columns - 1))) / columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: entry.value
                          .map(
                            (slot) => DragTarget<
                                ({_QueueItem item, Technician technician})>(
                              onWillAcceptWithDetails: (_) =>
                                  _appointmentForSlot(
                                    slot: slot,
                                    selectedTechnician: selectedTechnician,
                                    visibleTechnicians: visibleTechnicians,
                                    appointments: _allAppointments,
                                  ) ==
                                  null,
                              onAcceptWithDetails: (details) =>
                                  _scheduleDroppedItem(
                                slot: slot,
                                item: details.data.item,
                                technician: details.data.technician,
                              ),
                              builder: (context, candidate, __) =>
                                  _ScheduleSlotCard(
                                width: cardWidth.clamp(138.0, 176.0),
                                slot: slot,
                                highlighted: candidate.isNotEmpty,
                                appointment: _appointmentForSlot(
                                  slot: slot,
                                  selectedTechnician: selectedTechnician,
                                  visibleTechnicians: visibleTechnicians,
                                  appointments: _allAppointments,
                                ),
                                onTap: () async {
                                final action = await showDialog<_SlotAction>(
                                  context: context,
                                  barrierDismissible: true,
                                  builder: (_) => _SlotActionDialog(slot: slot),
                                );
                                if (!context.mounted || action == null) return;

                                if (action == _SlotAction.serviceRequest) {
                                  await showAppFormDialog<void>(
                                    context: context,
                                    title: 'Novo chamado',
                                    maxWidth: 1100,
                                    child: const ServiceRequestFormScreen(
                                      embedded: true,
                                    ),
                                  );
                                  return;
                                }

                                await showAppFormDialog<void>(
                                  context: context,
                                  title: action == _SlotAction.quote
                                      ? 'Agendar orçamento'
                                      : 'Agendar OS',
                                  maxWidth: 920,
                                  child: _CreateScheduleDialog(
                                    initialSlot: slot,
                                    preselectedTechnician: selectedTechnician,
                                    visibleTechnicians: visibleTechnicians,
                                    initialMode: action == _SlotAction.quote
                                        ? _ScheduleMode.quote
                                        : _ScheduleMode.workOrder,
                                  ),
                                );
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                },
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  /// Agenda o item solto no horário, para o profissional dono da fila.
  /// O item some da fila de todos porque passa a ter appointment ativo.
  Future<void> _scheduleDroppedItem({
    required DateTime slot,
    required _QueueItem item,
    required Technician technician,
  }) async {
    final technicianUserId = technician.userId;
    if (technicianUserId == null) {
      _showDropMessage(
        '${technician.name} não tem usuário vinculado — agende pelo formulário.',
      );
      return;
    }

    try {
      final created = await ref.read(appointmentRepositoryProvider).schedule(
            technicianUserId: technicianUserId,
            appointment: Appointment(
              id: '',
              tenantId: '',
              kind: item.kind,
              referenceId: item.referenceId,
              customerId: item.customerId,
              addressId: item.addressId,
              scheduledStart: slot,
              scheduledEnd: slot.add(const Duration(minutes: 30)),
              status: AppointmentStatus.scheduled,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      ref.invalidate(_scheduledReferenceKeysProvider);
      ref.read(appointmentListProvider.notifier).refresh();
      if (!mounted) return;
      // O diálogo recebeu a lista de agendamentos por valor, então mantém os
      // criados aqui para o slot já aparecer ocupado sem fechar a tela.
      setState(() => _createdHere.add(created));
      _showDropMessage(
        '${item.customerName} agendado para ${DateFormat('HH:mm').format(slot)} com ${technician.name}.',
      );
    } catch (e) {
      _showDropMessage(
        e is AppError ? e.userMessage : 'Não foi possível agendar.',
      );
    }
  }

  void _showDropMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProfessionSidebar extends ConsumerStatefulWidget {
  const _ProfessionSidebar({
    required this.selectedProfessionalId,
    required this.technicians,
    required this.onSelectGeneral,
    required this.onSelectTechnician,
  });

  final String? selectedProfessionalId;
  final List<Technician> technicians;
  final VoidCallback onSelectGeneral;
  final ValueChanged<Technician> onSelectTechnician;

  @override
  ConsumerState<_ProfessionSidebar> createState() => _ProfessionSidebarState();
}

class _ProfessionSidebarState extends ConsumerState<_ProfessionSidebar> {
  /// Todos começam recolhidos; expandir mostra a fila da categoria.
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(_workQueueProvider);

    return NeomorphicPanel(
      borderRadius: 26,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profissionais',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          _SidebarItem(
            label: 'Visão geral',
            selected: widget.selectedProfessionalId == null,
            icon: Icons.grid_view_rounded,
            onTap: widget.onSelectGeneral,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: widget.technicians.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final technician = widget.technicians[index];
                final isExpanded = _expanded.contains(technician.professionalId);
                // Todos da mesma categoria enxergam a mesma fila.
                final queue = queueAsync.maybeWhen(
                  data: (items) => items
                      .where(
                        (item) =>
                            item.categoryName == null ||
                            item.categoryName == technician.category,
                      )
                      .toList(),
                  orElse: () => const <_QueueItem>[],
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SidebarItem(
                      label: technician.name,
                      selected: technician.professionalId ==
                          widget.selectedProfessionalId,
                      icon: isExpanded
                          ? Icons.expand_more
                          : Icons.chevron_right_rounded,
                      badge: queue.isEmpty ? null : '${queue.length}',
                      onTap: () {
                        setState(() {
                          if (!_expanded.remove(technician.professionalId)) {
                            _expanded.add(technician.professionalId);
                          }
                        });
                        widget.onSelectTechnician(technician);
                      },
                    ),
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 0, 4),
                        child: queue.isEmpty
                            ? Text(
                                'Nada aguardando agendamento.',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : Column(
                                children: queue
                                    .map(
                                      (item) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: _QueueCard(
                                          item: item,
                                          technician: technician,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Card arrastável da fila. Solte-o num horário para agendar.
class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.item, required this.technician});

  final _QueueItem item;
  final Technician technician;

  @override
  Widget build(BuildContext context) {
    final card = _QueueCardBody(item: item);
    final payload = (item: item, technician: technician);
    return Draggable<({_QueueItem item, Technician technician})>(
      data: payload,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 240, child: _QueueCardBody(item: item)),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class _QueueCardBody extends StatelessWidget {
  const _QueueCardBody({required this.item});

  final _QueueItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = item.kind == AppointmentKind.workOrder
        ? _kWorkOrderColor
        : _kQuoteColor;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: accent, width: 4),
          top: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
          right: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall,
          ),
          if (item.customerPhone != null &&
              item.customerPhone!.trim().isNotEmpty)
            Text(
              item.customerPhone!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
          Text(
            item.placeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? const Color(0xFFECDDE6)
              : Colors.white.withValues(alpha: 0.42),
          border: Border.all(
            color: selected
                ? const Color(0xFFB2537F)
                : Colors.white.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ),
            if (badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colorScheme.primary,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleSlotCard extends StatelessWidget {
  const _ScheduleSlotCard({
    required this.width,
    required this.slot,
    required this.appointment,
    required this.onTap,
    this.highlighted = false,
  });

  final double width;
  final DateTime slot;
  final Appointment? appointment;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final isBusy = appointment != null;
    final time = DateFormat('HH:mm', 'pt_BR').format(slot);
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: isBusy ? null : onTap,
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withValues(alpha: 0.65),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: 0.08),
                  offset: const Offset(8, 10),
                  blurRadius: 18,
                ),
              ],
              border: Border.all(
                color: highlighted
                    ? const Color(0xFFB2537F)
                    : isBusy
                        ? const Color(0xFFCAA1B4)
                        : Colors.white.withValues(alpha: 0.72),
                width: highlighted ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        time,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: isBusy
                            ? const Color(0xFFE7CBD8)
                            : const Color(0xFFD1EFEC),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: Text(
                          isBusy ? 'Ocupado' : 'Livre',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  appointment == null
                      ? 'Agendar orçamento ou OS'
                      : appointment?.serviceRequestTitle ??
                          appointment?.customerName ??
                          'Horário ocupado',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ScheduleMode { quote, workOrder }

class _CreateScheduleDialog extends ConsumerStatefulWidget {
  const _CreateScheduleDialog({
    required this.initialSlot,
    required this.visibleTechnicians,
    this.initialMode = _ScheduleMode.quote,
    this.preselectedTechnician,
  });

  final DateTime initialSlot;
  final Technician? preselectedTechnician;
  final List<Technician> visibleTechnicians;
  final _ScheduleMode initialMode;

  @override
  ConsumerState<_CreateScheduleDialog> createState() =>
      _CreateScheduleDialogState();
}

class _CreateScheduleDialogState extends ConsumerState<_CreateScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerSearchController = TextEditingController();
  final _sourceSearchController = TextEditingController();
  final _notesController = TextEditingController();
  _ScheduleMode _mode = _ScheduleMode.quote;
  Customer? _selectedCustomer;
  ServiceRequest? _selectedRequest;
  WorkOrder? _selectedWorkOrder;
  String? _selectedProfessionalId;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialSlot;
    _end = _start.add(const Duration(hours: 2));
    _selectedProfessionalId = widget.preselectedTechnician?.professionalId;
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _customerSearchController.dispose();
    _sourceSearchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(_calendarSchedulableCustomersProvider);
    final requestsAsync = ref.watch(_calendarSchedulableRequestsProvider);
    final workOrdersAsync = ref.watch(_calendarSchedulableWorkOrdersProvider);
    final formState = ref.watch(appointmentFormProvider);
    final isLoading = formState is AppointmentFormLoading;
    final availableTechnicians = widget.visibleTechnicians;
    Technician? selectedTechnician;
    if (_selectedProfessionalId != null) {
      for (final technician in availableTechnicians) {
        if (technician.professionalId == _selectedProfessionalId) {
          selectedTechnician = technician;
          break;
        }
      }
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFormSection(
              title: 'Tipo de agendamento',
              icon: Icons.schedule_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<_ScheduleMode>(
                    segments: const [
                      ButtonSegment(
                        value: _ScheduleMode.quote,
                        label: Text('Orçamento'),
                        icon: Icon(Icons.request_quote_outlined),
                      ),
                      ButtonSegment(
                        value: _ScheduleMode.workOrder,
                        label: Text('OS'),
                        icon: Icon(Icons.engineering_outlined),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: isLoading
                        ? null
                        : (value) => setState(() {
                              _mode = value.first;
                              _selectedRequest = null;
                              _selectedWorkOrder = null;
                              _sourceSearchController.clear();
                            }),
                  ),
                  const SizedBox(height: 16),
                  AppFormGrid(
                    children: [
                      TextFormField(
                        controller: _customerSearchController,
                        enabled: !isLoading,
                        decoration: const InputDecoration(
                          labelText: 'Buscar cliente',
                          hintText: 'Nome, CPF/CNPJ ou telefone',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedProfessionalId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Profissional',
                          helperText: selectedTechnician != null &&
                                  selectedTechnician.userId == null
                              ? 'Este profissional aparece na agenda, mas ainda precisa ser vinculado a um usuário interno para receber agendamentos.'
                              : 'Selecione quem ficará responsável pelo horário.',
                        ),
                        items: availableTechnicians
                            .map(
                              (technician) => DropdownMenuItem(
                                value: technician.professionalId,
                                child: Text(
                                  '${technician.name} · ${technician.category}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isLoading
                            ? null
                            : (value) => setState(
                                  () => _selectedProfessionalId = value,
                                ),
                        validator: (value) =>
                            value == null ? 'Selecione um profissional.' : null,
                      ),
                      OutlinedButton.icon(
                        onPressed: isLoading ? null : () => _pickDate(context),
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                            DateFormat('dd/MM/yyyy', 'pt_BR').format(_start)),
                      ),
                      OutlinedButton.icon(
                        onPressed: isLoading
                            ? null
                            : () => _pickTime(context, start: true),
                        icon: const Icon(Icons.play_arrow_outlined),
                        label:
                            Text(DateFormat('HH:mm', 'pt_BR').format(_start)),
                      ),
                      OutlinedButton.icon(
                        onPressed: isLoading
                            ? null
                            : () => _pickTime(context, start: false),
                        icon: const Icon(Icons.stop_outlined),
                        label: Text(DateFormat('HH:mm', 'pt_BR').format(_end)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            customersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Clientes indisponíveis.'),
              data: (customers) {
                final filteredCustomers = customers
                    .where((customer) {
                      final search =
                          _customerSearchController.text.trim().toLowerCase();
                      if (search.isEmpty) return true;
                      return customer.name.toLowerCase().contains(search) ||
                          (customer.document ?? '')
                              .contains(search.replaceAll(RegExp(r'\D'), '')) ||
                          (customer.phone ?? '')
                              .contains(search.replaceAll(RegExp(r'\D'), ''));
                    })
                    .take(25)
                    .toList();
                return AppFormSection(
                  title: 'Cliente',
                  icon: Icons.people_alt_outlined,
                  child: DropdownButtonFormField<Customer>(
                    initialValue: _selectedCustomer,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Selecionar cliente',
                    ),
                    items: filteredCustomers
                        .map(
                          (customer) => DropdownMenuItem(
                            value: customer,
                            child: Text(
                              '${customer.name}${customer.phone != null ? ' · ${customer.phone}' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: isLoading
                        ? null
                        : (value) => setState(() {
                              _selectedCustomer = value;
                              _selectedRequest = null;
                              _selectedWorkOrder = null;
                            }),
                    validator: (value) =>
                        value == null ? 'Selecione um cliente.' : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sourceSearchController,
              enabled: !isLoading,
              decoration: InputDecoration(
                labelText: _mode == _ScheduleMode.quote
                    ? 'Buscar chamado para orçamento'
                    : 'Buscar OS',
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_mode == _ScheduleMode.quote)
              requestsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Chamados indisponíveis.'),
                data: (requests) {
                  final filteredRequests = requests
                      .where((request) {
                        if (_selectedCustomer != null &&
                            request.customerId != _selectedCustomer!.id) {
                          return false;
                        }
                        final search =
                            _sourceSearchController.text.trim().toLowerCase();
                        if (search.isEmpty) return true;
                        return request.title.toLowerCase().contains(search) ||
                            request.displayNumber
                                .toLowerCase()
                                .contains(search) ||
                            (request.customerName ?? '')
                                .toLowerCase()
                                .contains(search);
                      })
                      .take(25)
                      .toList();
                  return DropdownButtonFormField<ServiceRequest>(
                    initialValue: _selectedRequest,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Chamado para orçamento',
                    ),
                    items: filteredRequests
                        .map(
                          (request) => DropdownMenuItem(
                            value: request,
                            child: Text(
                              '${request.displayNumber} · ${request.title}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: isLoading
                        ? null
                        : (value) => setState(() => _selectedRequest = value),
                    validator: (value) =>
                        value == null ? 'Selecione o chamado.' : null,
                  );
                },
              )
            else
              workOrdersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('OS indisponíveis.'),
                data: (workOrders) {
                  final filteredOrders = workOrders
                      .where((workOrder) {
                        if (_selectedCustomer != null &&
                            workOrder.customerId != _selectedCustomer!.id) {
                          return false;
                        }
                        final search =
                            _sourceSearchController.text.trim().toLowerCase();
                        if (search.isEmpty) return true;
                        return workOrder.title.toLowerCase().contains(search) ||
                            workOrder.displayNumber
                                .toLowerCase()
                                .contains(search) ||
                            (workOrder.customerName ?? '')
                                .toLowerCase()
                                .contains(search);
                      })
                      .take(25)
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<WorkOrder>(
                        initialValue: _selectedWorkOrder,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'OS para execução',
                        ),
                        items: filteredOrders
                            .map(
                              (workOrder) => DropdownMenuItem(
                                value: workOrder,
                                child: Text(
                                  '${workOrder.displayNumber} · ${workOrder.title}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isLoading
                            ? null
                            : (value) =>
                                setState(() => _selectedWorkOrder = value),
                        validator: (value) =>
                            value == null ? 'Selecione a OS.' : null,
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: isLoading
                            ? null
                            : () async {
                                final created = await showAppFormDialog<bool>(
                                  context: context,
                                  title: 'Nova OS',
                                  child:
                                      const WorkOrderFormScreen(embedded: true),
                                );
                                if (created == true && mounted) {
                                  ref.invalidate(
                                      _calendarSchedulableWorkOrdersProvider);
                                }
                              },
                        icon: const Icon(Icons.add_task_outlined),
                        label: const Text('Criar OS antes de agendar'),
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 16),
            if (_mode == _ScheduleMode.quote)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: isLoading
                      ? null
                      : () async {
                          await showAppFormDialog<void>(
                            context: context,
                            title: 'Novo chamado',
                            maxWidth: 1100,
                            child: const ServiceRequestFormScreen(
                              embedded: true,
                            ),
                          );
                          if (mounted) {
                            ref.invalidate(
                              _calendarSchedulableRequestsProvider,
                            );
                          }
                        },
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Cadastrar chamado antes de agendar'),
                ),
              ),
            if (_mode == _ScheduleMode.quote) const SizedBox(height: 12),
            if (formState is AppointmentFormError)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ErrorView(message: formState.error.userMessage),
              ),
            TextFormField(
              controller: _notesController,
              enabled: !isLoading,
              maxLines: 3,
              maxLength: 1000,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: const InputDecoration(
                labelText: 'Observações',
                hintText: 'Ex.: levar escada, confirmar portaria, cobrar sinal',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: isLoading ? null : _submit,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Salvar agendamento'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      locale: const Locale('pt', 'BR'),
    );
    if (date == null) return;
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        _start.hour,
        _start.minute,
      );
      _end = DateTime(
        date.year,
        date.month,
        date.day,
        _end.hour,
        _end.minute,
      );
      if (!_end.isAfter(_start)) {
        _end = _start.add(const Duration(hours: 2));
      }
    });
  }

  Future<void> _pickTime(BuildContext context, {required bool start}) async {
    final current = start ? _start : _end;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    setState(() {
      final next = DateTime(
        current.year,
        current.month,
        current.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = next;
        if (!_end.isAfter(_start)) {
          _end = _start.add(const Duration(hours: 2));
        }
      } else {
        _end = next;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final selectedTechnician =
        widget.visibleTechnicians.cast<Technician?>().firstWhere(
              (technician) =>
                  technician?.professionalId == _selectedProfessionalId,
              orElse: () => null,
            );
    final technicianUserId = selectedTechnician?.userId;
    if (technicianUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este profissional ainda não está vinculado a um usuário interno. Faça o vínculo no cadastro do profissional para liberar o agendamento.',
          ),
        ),
      );
      return;
    }
    if (_mode == _ScheduleMode.quote) {
      final request = _selectedRequest;
      if (request == null) return;
      await ref.read(appointmentFormProvider.notifier).scheduleAppointment(
            kind: AppointmentKind.visit,
            referenceId: request.id,
            customerId: request.customerId,
            addressId: request.addressId,
            technicianUserId: technicianUserId,
            scheduledStart: _start,
            scheduledEnd: _end,
            notes: _notesController.text,
          );
    } else {
      final workOrder = _selectedWorkOrder;
      if (workOrder == null) return;
      await ref.read(appointmentFormProvider.notifier).scheduleAppointment(
            kind: AppointmentKind.workOrder,
            referenceId: workOrder.id,
            customerId: workOrder.customerId,
            addressId: workOrder.addressId,
            technicianUserId: technicianUserId,
            scheduledStart: _start,
            scheduledEnd: _end,
            notes: _notesController.text,
          );
    }

    final state = ref.read(appointmentFormProvider);
    if (!mounted) return;
    if (state is AppointmentFormSuccess) {
      Navigator.of(context).pop();
    }
  }
}

List<DateTime> _buildDaySlots(DateTime day) {
  final slots = <DateTime>[];
  var current = DateTime(day.year, day.month, day.day, 8, 0);
  final end = DateTime(day.year, day.month, day.day, 19, 30);
  while (!current.isAfter(end)) {
    slots.add(current);
    current = current.add(const Duration(minutes: 30));
  }
  return slots;
}

Appointment? _appointmentForSlot({
  required DateTime slot,
  required Technician? selectedTechnician,
  required List<Technician> visibleTechnicians,
  required List<Appointment> appointments,
}) {
  final relevantTechnicianIds = selectedTechnician != null
      ? {
          if (selectedTechnician.userId != null) selectedTechnician.userId!,
        }
      : visibleTechnicians
          .where((technician) => technician.userId != null)
          .map((technician) => technician.userId!)
          .toSet();
  for (final appointment in appointments) {
    final technicianId = appointment.technicianUserId;
    if (technicianId == null || !relevantTechnicianIds.contains(technicianId)) {
      continue;
    }
    final appointmentStart = appointment.scheduledStart.toLocal();
    final appointmentEnd = appointment.scheduledEnd.toLocal();
    if (!slot.isBefore(appointmentStart) && slot.isBefore(appointmentEnd)) {
      return appointment;
    }
  }
  return null;
}

Map<int, List<Appointment>> _groupByDay(List<Appointment> appointments) {
  final grouped = <int, List<Appointment>>{};
  for (final appointment in appointments) {
    grouped
        .putIfAbsent(appointment.scheduledStart.day, () => [])
        .add(appointment);
  }
  return grouped;
}

List<DateTime?> _calendarDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final total = DateTime(month.year, month.month + 1, 0).day;
  final leading = first.weekday - 1;
  return [
    ...List<DateTime?>.filled(leading, null),
    for (var day = 1; day <= total; day++)
      DateTime(month.year, month.month, day),
  ];
}

bool _isToday(DateTime day) {
  final now = DateTime.now();
  return now.year == day.year && now.month == day.month && now.day == day.day;
}
