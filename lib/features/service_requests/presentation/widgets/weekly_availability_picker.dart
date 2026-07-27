import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../settings/domain/schedule_models.dart';

/// Períodos do dia usados na disponibilidade — mesma granularidade do
/// horário de funcionamento configurado em Configurações.
const kAvailabilityPeriods = ['morning', 'afternoon', 'night'];
const kAvailabilityPeriodLabels = {
  'morning': 'Manhã',
  'afternoon': 'Tarde',
  'night': 'Noite',
};
const _periodIcons = {
  'morning': Icons.wb_sunny_outlined,
  'afternoon': Icons.wb_cloudy_outlined,
  'night': Icons.nights_stay_outlined,
};

/// Resumo em texto da seleção, na ordem dos dias/períodos — é isso que vai
/// pro campo de disponibilidade (texto livre) salvo no chamado.
String buildAvailabilitySummary(Map<String, Set<String>> selection) {
  final parts = <String>[];
  for (final weekday in kWeekdayOrder) {
    final periods = selection[weekday];
    if (periods == null || periods.isEmpty) continue;
    final labels = kAvailabilityPeriods
        .where(periods.contains)
        .map((p) => kAvailabilityPeriodLabels[p]!.toLowerCase())
        .join(', ');
    parts.add('${kWeekdayLabels[weekday]}: $labels');
  }
  return parts.join('; ');
}

SchedulePeriod _periodOf(DaySchedule day, String period) {
  switch (period) {
    case 'morning':
      return day.morning;
    case 'afternoon':
      return day.afternoon;
    default:
      return day.night;
  }
}

/// Calendário semanal de disponibilidade: um card por período (manhã/tarde/
/// noite) em cada dia da semana. Só fica clicável dentro do horário de
/// funcionamento da empresa (Configurações) — fora do expediente o card
/// aparece apagado e desabilitado.
class WeeklyAvailabilityPicker extends StatelessWidget {
  const WeeklyAvailabilityPicker({
    super.key,
    required this.businessHours,
    required this.selected,
    required this.onChanged,
  });

  final Map<String, DaySchedule> businessHours;
  final Map<String, Set<String>> selected;
  final ValueChanged<Map<String, Set<String>>> onChanged;

  bool _isPeriodOpen(DaySchedule day, String period) {
    if (!day.enabled) return false;
    return _periodOf(day, period).enabled;
  }

  void _toggle(String weekday, String period) {
    final next = {
      for (final entry in selected.entries) entry.key: {...entry.value},
    };
    final daySet = next.putIfAbsent(weekday, () => <String>{});
    if (!daySet.add(period)) daySet.remove(period);
    if (daySet.isEmpty) next.remove(weekday);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final weekday in kWeekdayOrder) ...[
          _DayRow(
            weekday: weekday,
            day: businessHours[weekday] ?? defaultDaySchedule(),
            selected: selected[weekday] ?? const {},
            isPeriodOpen: _isPeriodOpen,
            onToggle: (period) => _toggle(weekday, period),
          ),
          if (weekday != kWeekdayOrder.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.weekday,
    required this.day,
    required this.selected,
    required this.isPeriodOpen,
    required this.onToggle,
  });

  final String weekday;
  final DaySchedule day;
  final Set<String> selected;
  final bool Function(DaySchedule, String) isPeriodOpen;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final anyOpen = kAvailabilityPeriods.any((p) => isPeriodOpen(day, p));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            kWeekdayLabels[weekday]!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: anyOpen ? null : AppColors.inkMuted,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in kAvailabilityPeriods)
                _PeriodCard(
                  label: kAvailabilityPeriodLabels[period]!,
                  icon: _periodIcons[period]!,
                  open: isPeriodOpen(day, period),
                  timeRange: isPeriodOpen(day, period)
                      ? '${_periodOf(day, period).start ?? ''}–${_periodOf(day, period).end ?? ''}'
                      : null,
                  selected: selected.contains(period),
                  onTap: isPeriodOpen(day, period)
                      ? () => onToggle(period)
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.label,
    required this.icon,
    required this.open,
    required this.timeRange,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool open;
  final String? timeRange;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? colorScheme.primary : AppColors.surfacePressed,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? colorScheme.primary : AppColors.borderSoft,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colorScheme.onPrimary : AppColors.inkMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? colorScheme.onPrimary : AppColors.ink,
                ),
              ),
            ],
          ),
          if (timeRange != null) ...[
            const SizedBox(height: 2),
            Text(
              timeRange!,
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? colorScheme.onPrimary.withValues(alpha: 0.85)
                    : AppColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );

    if (!open) return Opacity(opacity: 0.35, child: card);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: card,
    );
  }
}
