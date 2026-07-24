import 'package:flutter/material.dart';

import '../../domain/work_order.dart';

class WorkOrderStatusChip extends StatelessWidget {
  const WorkOrderStatusChip({super.key, required this.status});

  final WorkOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      WorkOrderStatus.done => Colors.green,
      WorkOrderStatus.cancelled => Colors.red,
      WorkOrderStatus.inProgress => Colors.indigo,
      WorkOrderStatus.scheduled => Colors.teal,
      WorkOrderStatus.awaitingCustomer => Colors.orange,
      WorkOrderStatus.paused => Colors.blueGrey,
      WorkOrderStatus.opened => Colors.purple,
      WorkOrderStatus.draft => Colors.grey,
    };

    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(status.label),
    );
  }
}
