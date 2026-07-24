import 'package:flutter/material.dart';

import '../../domain/quotation.dart';

class QuotationStatusChip extends StatelessWidget {
  const QuotationStatusChip({super.key, required this.status});

  final QuotationStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      QuotationStatus.draft => Colors.grey,
      QuotationStatus.underReview => Colors.indigo,
      QuotationStatus.sent => Colors.blue,
      QuotationStatus.viewed => Colors.teal,
      QuotationStatus.awaitingApproval => Colors.orange,
      QuotationStatus.approved => Colors.green,
      QuotationStatus.rejected => Colors.red,
      QuotationStatus.changeRequested => Colors.deepPurple,
      QuotationStatus.expired => Colors.brown,
      QuotationStatus.cancelled => Colors.blueGrey,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(status.label),
      labelStyle: TextStyle(
        color: color.shade800,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: color.shade50,
      side: BorderSide(color: color.shade100),
    );
  }
}
