import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/financials/domain/payable.dart';
import 'package:serviceflow/features/financials/domain/receivable.dart';

void main() {
  group('payableFromRow', () {
    test('desserializa linha de list_payables', () {
      final row = {
        'id': 'pay-1',
        'supplier_id': 'sup-1',
        'supplier_name': 'Fornecedor Teste',
        'purchase_order_id': 'po-1',
        'purchase_order_number': 12,
        'description': 'Pedido de compra #00012',
        'due_date': '2026-08-26',
        'amount_cents': 50000,
        'balance_cents': 30000,
        'status': 'partially_paid',
        'created_at': '2026-07-27T12:00:00Z',
      };

      final p = payableFromRow(row);
      expect(p.supplierName, 'Fornecedor Teste');
      expect(p.purchaseOrderNumber, 12);
      expect(p.amountCents, 50000);
      expect(p.balanceCents, 30000);
      expect(p.status, ReceivableStatus.partiallyPaid);
    });
  });

  group('Payable.isOverdue', () {
    Payable make({required DateTime dueDate, int balanceCents = 1000}) =>
        Payable(
          id: 'p1',
          supplierId: 's1',
          supplierName: 'Fornecedor',
          purchaseOrderId: 'po1',
          purchaseOrderNumber: 1,
          description: 'Pedido #00001',
          dueDate: dueDate,
          amountCents: 1000,
          balanceCents: balanceCents,
          status: ReceivableStatus.open,
          createdAt: DateTime.utc(2026),
        );

    test('vencida quando data passou e ha saldo', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(make(dueDate: yesterday).isOverdue, isTrue);
    });

    test('nao vencida quando saldo zerado, mesmo com data passada', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(
        make(dueDate: yesterday, balanceCents: 0).isOverdue,
        isFalse,
      );
    });

    test('nao vencida quando a data ainda nao chegou', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(make(dueDate: tomorrow).isOverdue, isFalse);
    });
  });
}
