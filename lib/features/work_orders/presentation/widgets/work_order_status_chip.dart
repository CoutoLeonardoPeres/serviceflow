import 'package:flutter/material.dart';

import '../../domain/work_order.dart';

/// Selo de status da OS.
///
/// As cores saem do `ColorScheme`, não de `Colors.*` fixos: a cor de destaque
/// é variável por empresa (white-label), e um "Aberta" roxo cravado no código
/// colidia com a marca de qualquer tenant que não fosse roxo.
class WorkOrderStatusChip extends StatelessWidget {
  const WorkOrderStatusChip({super.key, required this.status});

  final WorkOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      WorkOrderStatus.done => scheme.primary,
      WorkOrderStatus.cancelled => scheme.error,
      WorkOrderStatus.inProgress => scheme.tertiary,
      WorkOrderStatus.scheduled => scheme.secondary,
      WorkOrderStatus.awaitingCustomer => scheme.secondary,
      WorkOrderStatus.paused => scheme.outline,
      WorkOrderStatus.opened => scheme.onSurfaceVariant,
      WorkOrderStatus.draft => scheme.outlineVariant,
    };

    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text(status.label),
    );
  }
}
