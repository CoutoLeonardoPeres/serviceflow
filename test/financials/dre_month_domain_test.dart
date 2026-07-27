import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/financials/domain/dre_month.dart';

void main() {
  group('dreMonthFromRow', () {
    test('desserializa linha de get_dre_monthly', () {
      final row = {
        'month_start': '2026-07-01',
        'revenue_cents': 10000,
        'expense_cents': 3000,
        'result_cents': 7000,
      };

      final m = dreMonthFromRow(row);
      expect(m.monthStart, DateTime.parse('2026-07-01'));
      expect(m.revenueCents, 10000);
      expect(m.expenseCents, 3000);
      expect(m.resultCents, 7000);
    });

    test('resultado negativo (mes no prejuizo) e preservado', () {
      final row = {
        'month_start': '2026-08-01',
        'revenue_cents': 1000,
        'expense_cents': 5000,
        'result_cents': -4000,
      };

      expect(dreMonthFromRow(row).resultCents, -4000);
    });
  });
}
