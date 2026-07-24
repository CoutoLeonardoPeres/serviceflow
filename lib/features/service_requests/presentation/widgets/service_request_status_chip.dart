import 'package:flutter/material.dart';

import '../../domain/service_request.dart';

class ServiceRequestStatusChip extends StatelessWidget {
  const ServiceRequestStatusChip({
    super.key,
    required this.status,
  });

  final ServiceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ServiceRequestStatus.draft => Colors.blueGrey,
      ServiceRequestStatus.opened => Colors.indigo,
      ServiceRequestStatus.triage => Colors.deepPurple,
      ServiceRequestStatus.awaitingCustomer => Colors.orange,
      ServiceRequestStatus.scheduled => Colors.teal,
      ServiceRequestStatus.convertedToQuote => Colors.blue,
      ServiceRequestStatus.convertedToWorkOrder => Colors.green,
      ServiceRequestStatus.cancelled => Colors.red,
      ServiceRequestStatus.closed => Colors.grey,
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
