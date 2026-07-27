/// Linha mensal do DRE simples (F4-P2, ADR-026).
///
/// Regime de caixa: `revenueCents` é o que foi efetivamente recebido
/// (`payment_records`) e `expenseCents` é o que foi efetivamente pago a
/// fornecedores (`payable_payments`) naquele mês — não é competência, não
/// tem CMV por venda nem plano de contas.
class DreMonth {
  const DreMonth({
    required this.monthStart,
    required this.revenueCents,
    required this.expenseCents,
    required this.resultCents,
  });

  final DateTime monthStart;
  final int revenueCents;
  final int expenseCents;
  final int resultCents;
}

DreMonth dreMonthFromRow(Map<String, dynamic> row) => DreMonth(
      monthStart: DateTime.parse(row['month_start'] as String),
      revenueCents: (row['revenue_cents'] as num).toInt(),
      expenseCents: (row['expense_cents'] as num).toInt(),
      resultCents: (row['result_cents'] as num).toInt(),
    );
