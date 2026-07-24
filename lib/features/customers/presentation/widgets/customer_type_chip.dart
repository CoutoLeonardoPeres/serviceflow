import 'package:flutter/material.dart';
import '../../domain/customer.dart';

/// Chip visual para o tipo de cliente.
class CustomerTypeChip extends StatelessWidget {
  const CustomerTypeChip({super.key, required this.type});

  final CustomerType type;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (color, icon) = switch (type) {
      CustomerType.person => (
          colorScheme.secondaryContainer,
          Icons.person_outline
        ),
      CustomerType.company => (
          colorScheme.tertiaryContainer,
          Icons.business_outlined
        ),
      CustomerType.condominium => (
          colorScheme.primaryContainer,
          Icons.apartment_outlined
        ),
      CustomerType.publicEntity => (
          colorScheme.surfaceContainerHighest,
          Icons.account_balance_outlined
        ),
    };

    return Chip(
      label: Text(type.label),
      labelStyle: TextStyle(fontSize: 11, color: colorScheme.onSurface),
      backgroundColor: color,
      avatar: Icon(icon, size: 14),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      visualDensity: VisualDensity.compact,
    );
  }
}
