import 'package:flutter/material.dart';

import '../../domain/appointment.dart';

class AppointmentStatusChip extends StatelessWidget {
  const AppointmentStatusChip({
    super.key,
    required this.status,
  });

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AppointmentStatus.scheduled => Colors.indigo,
      AppointmentStatus.confirmed => Colors.teal,
      AppointmentStatus.done => Colors.green,
      AppointmentStatus.cancelled => Colors.red,
      AppointmentStatus.noShow => Colors.orange,
    };

    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.24)),
      backgroundColor: color.withValues(alpha: 0.10),
      label: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
