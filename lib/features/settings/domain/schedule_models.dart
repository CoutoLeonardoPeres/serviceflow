const kWeekdayLabels = <String, String>{
  'monday': 'Segunda',
  'tuesday': 'Terça',
  'wednesday': 'Quarta',
  'thursday': 'Quinta',
  'friday': 'Sexta',
  'saturday': 'Sábado',
  'sunday': 'Domingo',
};

const kWeekdayOrder = <String>[
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

class SchedulePeriod {
  const SchedulePeriod({
    required this.enabled,
    this.start,
    this.end,
  });

  final bool enabled;
  final String? start;
  final String? end;

  SchedulePeriod copyWith({
    bool? enabled,
    String? start,
    String? end,
    bool clearStart = false,
    bool clearEnd = false,
  }) {
    return SchedulePeriod(
      enabled: enabled ?? this.enabled,
      start: clearStart ? null : start ?? this.start,
      end: clearEnd ? null : end ?? this.end,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'start': start,
        'end': end,
      };

  static SchedulePeriod fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SchedulePeriod(enabled: false);
    }
    return SchedulePeriod(
      enabled: json['enabled'] as bool? ?? false,
      start: json['start'] as String?,
      end: json['end'] as String?,
    );
  }
}

class DaySchedule {
  const DaySchedule({
    required this.enabled,
    required this.morning,
    required this.afternoon,
    required this.night,
  });

  final bool enabled;
  final SchedulePeriod morning;
  final SchedulePeriod afternoon;
  final SchedulePeriod night;

  DaySchedule copyWith({
    bool? enabled,
    SchedulePeriod? morning,
    SchedulePeriod? afternoon,
    SchedulePeriod? night,
  }) {
    return DaySchedule(
      enabled: enabled ?? this.enabled,
      morning: morning ?? this.morning,
      afternoon: afternoon ?? this.afternoon,
      night: night ?? this.night,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'morning': morning.toJson(),
        'afternoon': afternoon.toJson(),
        'night': night.toJson(),
      };

  static DaySchedule fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return defaultDaySchedule();
    }
    return DaySchedule(
      enabled: json['enabled'] as bool? ?? false,
      morning:
          SchedulePeriod.fromJson(json['morning'] as Map<String, dynamic>?),
      afternoon:
          SchedulePeriod.fromJson(json['afternoon'] as Map<String, dynamic>?),
      night: SchedulePeriod.fromJson(json['night'] as Map<String, dynamic>?),
    );
  }
}

DaySchedule defaultDaySchedule({bool enabled = false}) {
  return DaySchedule(
    enabled: enabled,
    morning: SchedulePeriod(
      enabled: enabled,
      start: enabled ? '08:00' : null,
      end: enabled ? '12:00' : null,
    ),
    afternoon: SchedulePeriod(
      enabled: enabled,
      start: enabled ? '13:00' : null,
      end: enabled ? '18:00' : null,
    ),
    night: const SchedulePeriod(
      enabled: false,
      start: '18:00',
      end: '22:00',
    ),
  );
}

Map<String, DaySchedule> defaultWeeklySchedule({
  bool weekdaysEnabled = true,
}) {
  return {
    for (final weekday in kWeekdayOrder)
      weekday: defaultDaySchedule(
        enabled:
            weekdaysEnabled && weekday != 'saturday' && weekday != 'sunday',
      ),
  };
}

Map<String, DaySchedule> weeklyScheduleFromJson(dynamic json) {
  final map =
      json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
  return {
    for (final weekday in kWeekdayOrder)
      weekday: DaySchedule.fromJson(map[weekday] as Map<String, dynamic>?),
  };
}

Map<String, dynamic> weeklyScheduleToJson(Map<String, DaySchedule> schedule) {
  return {
    for (final weekday in kWeekdayOrder)
      weekday: (schedule[weekday] ?? defaultDaySchedule()).toJson(),
  };
}

class AgendaClosure {
  const AgendaClosure({
    required this.date,
    required this.reason,
  });

  final DateTime date;
  final String reason;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'reason': reason,
      };

  static AgendaClosure fromJson(Map<String, dynamic> json) {
    return AgendaClosure(
      date: DateTime.parse(json['date'] as String),
      reason: json['reason'] as String? ?? 'Fechamento',
    );
  }
}

List<AgendaClosure> closuresFromJson(dynamic json) {
  final list = json is List ? json : const [];
  return list
      .whereType<Map>()
      .map((item) => AgendaClosure.fromJson(Map<String, dynamic>.from(item)))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}

List<Map<String, dynamic>> closuresToJson(List<AgendaClosure> closures) {
  return closures.map((closure) => closure.toJson()).toList();
}
