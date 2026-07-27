import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/stock/domain/stock_count.dart';
import 'package:serviceflow/features/stock/domain/stock_transfer.dart';

void main() {
  group('StockTransfer', () {
    StockTransfer make({String? from, String? to}) => StockTransfer(
          id: 't1',
          number: 7,
          fromWarehouseId: 'w1',
          toWarehouseId: 'w2',
          fromWarehouseName: from,
          toWarehouseName: to,
          totalValueCents: 9999,
          createdAt: DateTime.utc(2026, 7, 26),
        );

    test('displayNumber formata com cerquilha', () {
      expect(make().displayNumber, '#7');
    });

    test('route mostra origem e destino', () {
      expect(make(from: 'Central', to: 'Veículo').route, 'Central → Veículo');
    });

    test('route usa rótulos genéricos sem os nomes', () {
      expect(make().route, 'Origem → Destino');
    });
  });

  group('stockTransferFromRow', () {
    test('desserializa com nomes achatados do join', () {
      final row = {
        'id': 't1',
        'number': 7,
        'from_warehouse_id': 'w1',
        'to_warehouse_id': 'w2',
        'from_warehouse_name': 'Central',
        'to_warehouse_name': 'Veículo 1',
        'reason': 'reposição',
        'total_value_cents': 9999,
        'created_at': '2026-07-26T10:00:00Z',
      };

      final t = stockTransferFromRow(row);
      expect(t.number, 7);
      expect(t.route, 'Central → Veículo 1');
      expect(t.totalValueCents, 9999);
      expect(t.reason, 'reposição');
    });
  });

  group('StockTransferLine.toJson', () {
    test('serializa produto e quantidade', () {
      const line = StockTransferLine(productId: 'p1', quantity: 2.5);
      expect(line.toJson(), {'product_id': 'p1', 'quantity': 2.5});
    });
  });

  group('StockCountStatus', () {
    test('value corresponde ao CHECK de stock_counts.status', () {
      expect(StockCountStatus.open.value, 'open');
      expect(StockCountStatus.applied.value, 'applied');
      expect(StockCountStatus.cancelled.value, 'cancelled');
    });

    test('fromString faz o caminho de volta', () {
      for (final s in StockCountStatus.values) {
        expect(stockCountStatusFromString(s.value), s);
      }
    });

    test('isOpen só para contagem aberta', () {
      expect(StockCountStatus.open.isOpen, isTrue);
      expect(StockCountStatus.applied.isOpen, isFalse);
      expect(StockCountStatus.cancelled.isOpen, isFalse);
    });
  });

  group('StockCountItem', () {
    StockCountItem make({
      double system = 10,
      double? counted,
      double? difference,
    }) =>
        StockCountItem(
          id: 'i1',
          productId: 'p1',
          productName: 'Cabo',
          sku: 'CB-1',
          unit: 'm',
          systemQuantity: system,
          countedQuantity: counted,
          difference: difference,
        );

    test('isCounted distingue item ainda não conferido', () {
      expect(make().isCounted, isFalse);
      expect(make(counted: 10).isCounted, isTrue);
      // Zero contado é uma contagem válida, não ausência de contagem.
      expect(make(counted: 0).isCounted, isTrue);
    });

    test('hasDivergence só quando contado difere do sistema', () {
      expect(make(counted: 10).hasDivergence, isFalse);
      expect(make(counted: 8).hasDivergence, isTrue);
      expect(make(counted: 12).hasDivergence, isTrue);
      expect(make().hasDivergence, isFalse, reason: 'sem contagem não diverge');
    });

    test('item contado como zero com saldo positivo é divergência', () {
      // Caso real: produto sumiu do depósito. Não pode passar batido.
      expect(make(system: 10, counted: 0).hasDivergence, isTrue);
    });

    test('displayName inclui SKU quando existe', () {
      expect(make().displayName, 'CB-1 — Cabo');
    });
  });

  group('stockCountItemFromRow', () {
    test('desserializa item já contado com diferença', () {
      final row = {
        'id': 'i1',
        'product_id': 'p1',
        'product_name': 'Cabo',
        'sku': 'CB-1',
        'unit': 'm',
        'system_quantity': 10,
        'counted_quantity': 8,
        'difference': -2,
      };

      final i = stockCountItemFromRow(row);
      expect(i.systemQuantity, 10);
      expect(i.countedQuantity, 8);
      expect(i.difference, -2);
      expect(i.hasDivergence, isTrue);
    });

    test('desserializa item não contado', () {
      final row = {
        'id': 'i2',
        'product_id': 'p2',
        'product_name': 'Disjuntor',
        'sku': null,
        'unit': 'un',
        'system_quantity': 5,
        'counted_quantity': null,
        'difference': null,
      };

      final i = stockCountItemFromRow(row);
      expect(i.countedQuantity, isNull);
      expect(i.difference, isNull);
      expect(i.isCounted, isFalse);
      expect(i.displayName, 'Disjuntor');
    });
  });

  group('stockCountFromRow', () {
    test('desserializa contagem aplicada', () {
      final row = {
        'id': 'c1',
        'number': 3,
        'warehouse_id': 'w1',
        'warehouse_name': 'Central',
        'status': 'applied',
        'notes': 'inventário de julho',
        'applied_at': '2026-07-26T15:00:00Z',
        'created_at': '2026-07-26T10:00:00Z',
      };

      final c = stockCountFromRow(row);
      expect(c.displayNumber, '#3');
      expect(c.status, StockCountStatus.applied);
      expect(c.status.isOpen, isFalse);
      expect(c.appliedAt, DateTime.utc(2026, 7, 26, 15));
    });
  });
}
