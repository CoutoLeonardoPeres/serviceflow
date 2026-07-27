import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/quotations/domain/quotation_version.dart';

void main() {
  group('QuotationVersion', () {
    QuotationVersion makeVersion({
      int versionNumber = 1,
      bool isCurrent = false,
      int totalCents = 150000,
    }) =>
        QuotationVersion(
          id: 'ver-$versionNumber',
          versionNumber: versionNumber,
          totalCents: totalCents,
          subtotalCents: 140000,
          discountCents: 0,
          taxCents: 10000,
          isCurrent: isCurrent,
          createdAt: DateTime(2026, 7, 25),
        );

    test('label mostra versão com sufixo (atual) quando isCurrent', () {
      final v = makeVersion(versionNumber: 3, isCurrent: true);
      expect(v.label, 'Versão 3 (atual)');
    });

    test('label mostra versão sem sufixo quando não é atual', () {
      final v = makeVersion(versionNumber: 2, isCurrent: false);
      expect(v.label, 'Versão 2');
    });
  });

  group('quotationVersionFromRow', () {
    test('desserializa row com is_current=true', () {
      final row = {
        'id': 'ver-1',
        'version_number': 1,
        'total_cents': 200000,
        'subtotal_cents': 180000,
        'discount_cents': 5000,
        'tax_cents': 25000,
        'is_current': true,
        'created_at': '2026-07-25T08:00:00Z',
      };

      final v = quotationVersionFromRow(row);
      expect(v.id, 'ver-1');
      expect(v.versionNumber, 1);
      expect(v.totalCents, 200000);
      expect(v.subtotalCents, 180000);
      expect(v.discountCents, 5000);
      expect(v.taxCents, 25000);
      expect(v.isCurrent, isTrue);
      expect(v.createdAt, DateTime.utc(2026, 7, 25, 8));
    });

    test('desserializa row com is_current=false', () {
      final row = {
        'id': 'ver-2',
        'version_number': 2,
        'total_cents': 220000,
        'subtotal_cents': 200000,
        'discount_cents': 0,
        'tax_cents': 20000,
        'is_current': false,
        'created_at': '2026-07-25T10:00:00Z',
      };

      final v = quotationVersionFromRow(row);
      expect(v.isCurrent, isFalse);
      expect(v.label, 'Versão 2');
    });
  });

  group('QuotationStatusEvent', () {
    test('desserializa row', () {
      final row = {
        'id': 'hist-1',
        'status': 'cancelled',
        'notes': 'Cliente desistiu.',
        'changed_at': '2026-07-25T15:00:00Z',
      };

      final event = quotationStatusEventFromRow(row);
      expect(event.id, 'hist-1');
      expect(event.status, 'cancelled');
      expect(event.notes, 'Cliente desistiu.');
      expect(event.changedAt, DateTime.utc(2026, 7, 25, 15));
    });

    test('desserializa row sem notes', () {
      final row = {
        'id': 'hist-2',
        'status': 'approved',
        'notes': null,
        'changed_at': '2026-07-25T09:00:00Z',
      };

      final event = quotationStatusEventFromRow(row);
      expect(event.notes, isNull);
      expect(event.status, 'approved');
    });
  });
}
