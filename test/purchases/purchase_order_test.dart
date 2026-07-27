import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/purchases/domain/purchase_order.dart';
import 'package:serviceflow/features/purchases/domain/supplier.dart';

void main() {
  group('PurchaseOrderStatus', () {
    test('value corresponde ao CHECK de purchase_orders.status', () {
      expect(PurchaseOrderStatus.draft.value, 'draft');
      expect(PurchaseOrderStatus.sent.value, 'sent');
      expect(PurchaseOrderStatus.partiallyReceived.value, 'partially_received');
      expect(PurchaseOrderStatus.received.value, 'received');
      expect(PurchaseOrderStatus.cancelled.value, 'cancelled');
    });

    test('fromString faz o caminho de volta para todos', () {
      for (final s in PurchaseOrderStatus.values) {
        expect(purchaseOrderStatusFromString(s.value), s);
      }
    });

    test('canSend só para rascunho', () {
      expect(PurchaseOrderStatus.draft.canSend, isTrue);
      for (final s in PurchaseOrderStatus.values
          .where((e) => e != PurchaseOrderStatus.draft)) {
        expect(s.canSend, isFalse, reason: '${s.name} não deveria enviar');
      }
    });

    test('canReceive só para enviado e parcialmente recebido', () {
      expect(PurchaseOrderStatus.sent.canReceive, isTrue);
      expect(PurchaseOrderStatus.partiallyReceived.canReceive, isTrue);
      expect(PurchaseOrderStatus.draft.canReceive, isFalse);
      expect(PurchaseOrderStatus.received.canReceive, isFalse);
      expect(PurchaseOrderStatus.cancelled.canReceive, isFalse);
    });

    test('canCancel bloqueia depois que mercadoria entrou', () {
      // Regra do servidor (0044): parcialmente recebido não cancela, porque a
      // mercadoria já existe fisicamente no estoque.
      expect(PurchaseOrderStatus.draft.canCancel, isTrue);
      expect(PurchaseOrderStatus.sent.canCancel, isTrue);
      expect(PurchaseOrderStatus.partiallyReceived.canCancel, isFalse);
      expect(PurchaseOrderStatus.received.canCancel, isFalse);
      expect(PurchaseOrderStatus.cancelled.canCancel, isFalse);
    });

    test('isTerminal para recebido e cancelado', () {
      expect(PurchaseOrderStatus.received.isTerminal, isTrue);
      expect(PurchaseOrderStatus.cancelled.isTerminal, isTrue);
      expect(PurchaseOrderStatus.sent.isTerminal, isFalse);
    });
  });

  group('PurchaseOrder', () {
    PurchaseOrder make({
      PurchaseOrderStatus status = PurchaseOrderStatus.sent,
      DateTime? expectedAt,
    }) =>
        PurchaseOrder(
          id: 'po1',
          number: 42,
          supplierId: 's1',
          warehouseId: 'w1',
          status: status,
          totalCents: 90000,
          expectedAt: expectedAt,
          createdAt: DateTime.utc(2026, 7, 26),
        );

    test('displayNumber formata com cerquilha', () {
      expect(make().displayNumber, '#42');
    });

    test('isOpen para enviado e parcialmente recebido', () {
      expect(make(status: PurchaseOrderStatus.sent).isOpen, isTrue);
      expect(
        make(status: PurchaseOrderStatus.partiallyReceived).isOpen,
        isTrue,
      );
      expect(make(status: PurchaseOrderStatus.draft).isOpen, isFalse);
      expect(make(status: PurchaseOrderStatus.received).isOpen, isFalse);
    });

    test('isLate só para pedido aberto com previsão vencida', () {
      final past = DateTime.now().subtract(const Duration(days: 5));
      final future = DateTime.now().add(const Duration(days: 5));

      expect(make(expectedAt: past).isLate, isTrue);
      expect(make(expectedAt: future).isLate, isFalse);
      expect(make().isLate, isFalse, reason: 'sem previsão não atrasa');

      // Pedido fechado não fica "atrasado" mesmo com previsão vencida.
      expect(
        make(status: PurchaseOrderStatus.received, expectedAt: past).isLate,
        isFalse,
      );
      expect(
        make(status: PurchaseOrderStatus.cancelled, expectedAt: past).isLate,
        isFalse,
      );
    });
  });

  group('purchaseOrderFromRow', () {
    test('desserializa com nomes achatados do join', () {
      final row = {
        'id': 'po1',
        'number': 42,
        'supplier_id': 's1',
        'warehouse_id': 'w1',
        'status': 'partially_received',
        'total_cents': 90000,
        'supplier_name': 'Fornecedor X',
        'warehouse_name': 'Central',
        'expected_at': '2026-08-10',
        'notes': 'urgente',
        'received_at': null,
        'cancellation_reason': null,
        'created_at': '2026-07-26T10:00:00Z',
      };

      final o = purchaseOrderFromRow(row);
      expect(o.number, 42);
      expect(o.status, PurchaseOrderStatus.partiallyReceived);
      expect(o.supplierName, 'Fornecedor X');
      expect(o.warehouseName, 'Central');
      expect(o.expectedAt, DateTime.parse('2026-08-10'));
      expect(o.isOpen, isTrue);
    });
  });

  group('PurchaseOrderItem', () {
    PurchaseOrderItem make({
      double ordered = 100,
      double received = 0,
      String? sku = 'SKU-1',
    }) =>
        PurchaseOrderItem(
          id: 'i1',
          productId: 'p1',
          productName: 'Cabo',
          sku: sku,
          unit: 'm',
          quantityOrdered: ordered,
          quantityReceived: received,
          unitCostCents: 400,
          totalCostCents: 40000,
        );

    test('quantityPending é o que falta', () {
      expect(make(received: 30).quantityPending, 70);
      expect(make().quantityPending, 100);
      expect(make(received: 100).quantityPending, 0);
    });

    test('isFullyReceived quando recebido alcança o pedido', () {
      expect(make(received: 100).isFullyReceived, isTrue);
      expect(make(received: 99).isFullyReceived, isFalse);
    });

    test('displayName inclui SKU quando existe', () {
      expect(make().displayName, 'SKU-1 — Cabo');
      expect(make(sku: null).displayName, 'Cabo');
    });
  });

  group('PurchaseReceiptLine.toJson', () {
    test('omite custo quando não informado — mantém o cotado no pedido', () {
      const line = PurchaseReceiptLine(itemId: 'i1', quantity: 10);
      final json = line.toJson();
      expect(json['item_id'], 'i1');
      expect(json['quantity'], 10);
      expect(json.containsKey('unit_cost_cents'), isFalse);
    });

    test('inclui custo da nota quando informado', () {
      const line = PurchaseReceiptLine(
        itemId: 'i1',
        quantity: 10,
        unitCostCents: 6000,
      );
      expect(line.toJson()['unit_cost_cents'], 6000);
    });
  });

  group('Supplier', () {
    test('displayName prefere nome fantasia', () {
      final s = Supplier(
        id: 's1',
        tenantId: 't1',
        name: 'Comercial Silva LTDA',
        tradeName: 'Silva Materiais',
        isActive: true,
        createdAt: DateTime.utc(2026),
      );
      expect(s.displayName, 'Silva Materiais');
    });

    test('displayName cai na razão social sem fantasia', () {
      final s = Supplier(
        id: 's1',
        tenantId: 't1',
        name: 'Comercial Silva LTDA',
        isActive: true,
        createdAt: DateTime.utc(2026),
      );
      expect(s.displayName, 'Comercial Silva LTDA');
    });
  });
}
