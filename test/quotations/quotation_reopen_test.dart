import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/quotations/domain/quotation.dart';
import 'package:serviceflow/features/quotations/domain/quotation_version.dart';
import 'package:serviceflow/features/quotations/presentation/quotation_detail_screen.dart';

/// Guarda a janela de reabertura de 30 dias (migration 0058).
///
/// Se falhar, `quotation_reopen_deadline` no banco e `_reopenDeadline` no app
/// divergiram — o botão passaria a aparecer quando o banco vai recusar, ou o
/// contrário.
Quotation makeQuote({
  required QuotationStatus status,
  required DateTime updatedAt,
}) =>
    Quotation(
      id: 'q-1',
      tenantId: 't-1',
      number: 1,
      customerId: 'c-1',
      status: status,
      subtotalCents: 1000,
      discountCents: 0,
      taxCents: 0,
      totalCents: 1000,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updatedAt,
    );

void main() {
  group('janela de reabertura', () {
    test('conta 30 dias a partir da recusa, não da criação', () {
      final rejectedAt = DateTime(2026, 6, 10);
      final quote = makeQuote(
        status: QuotationStatus.rejected,
        // updatedAt propositalmente diferente: o histórico deve vencer.
        updatedAt: DateTime(2026, 1, 5),
      );
      final events = [
        QuotationStatusEvent(
          id: 'e-1',
          status: 'sent',
          changedAt: DateTime(2026, 1, 2),
        ),
        QuotationStatusEvent(
          id: 'e-2',
          status: 'rejected',
          changedAt: rejectedAt,
        ),
      ];

      expect(
        quotationReopenDeadline(quote, events),
        rejectedAt.add(const Duration(days: 30)),
      );
    });

    test('usa a recusa mais recente quando houve mais de uma', () {
      final quote = makeQuote(
        status: QuotationStatus.rejected,
        updatedAt: DateTime(2026, 1, 5),
      );
      final events = [
        QuotationStatusEvent(
          id: 'e-1',
          status: 'rejected',
          changedAt: DateTime(2026, 3, 1),
        ),
        QuotationStatusEvent(
          id: 'e-2',
          status: 'rejected',
          changedAt: DateTime(2026, 6, 1),
        ),
      ];

      expect(
        quotationReopenDeadline(quote, events),
        DateTime(2026, 6, 1).add(const Duration(days: 30)),
      );
    });

    test('sem histórico, cai em updatedAt', () {
      final updatedAt = DateTime(2026, 5, 20);
      final quote = makeQuote(
        status: QuotationStatus.expired,
        updatedAt: updatedAt,
      );

      expect(
        quotationReopenDeadline(quote, const []),
        updatedAt.add(const Duration(days: 30)),
      );
    });
  });
}
