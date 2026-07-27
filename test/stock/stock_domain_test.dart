import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/stock/domain/product.dart';
import 'package:serviceflow/features/stock/domain/stock_balance.dart';
import 'package:serviceflow/features/stock/domain/stock_movement.dart';
import 'package:serviceflow/features/stock/domain/warehouse.dart';

void main() {
  group('ProductUnit', () {
    test('fromString mapeia todas as unidades do CHECK da migration 0042', () {
      // Se o banco ganhar uma unidade nova, este teste é o lembrete de
      // atualizar o enum.
      const dbUnits = [
        'un', 'm', 'm2', 'm3', 'kg', 'g', 'l', 'ml', 'cx', 'pc', 'h',
      ];
      for (final u in dbUnits) {
        expect(
          productUnitFromString(u).value,
          u,
          reason: 'Unidade "$u" do banco não tem correspondente no enum',
        );
      }
    });

    test('valor desconhecido cai em un em vez de estourar', () {
      expect(productUnitFromString('parsec'), ProductUnit.un);
    });

    test('label e short são não vazios para todas as unidades', () {
      for (final u in ProductUnit.values) {
        expect(u.label, isNotEmpty);
        expect(u.short, isNotEmpty);
      }
    });
  });

  group('ProductTrackingType', () {
    test('fromString mapeia todos os valores do CHECK da migration 0047', () {
      expect(productTrackingTypeFromString('lot'), ProductTrackingType.lot);
      expect(
        productTrackingTypeFromString('serial'),
        ProductTrackingType.serial,
      );
      expect(productTrackingTypeFromString('none'), ProductTrackingType.none);
    });

    test('valor nulo ou desconhecido cai em none', () {
      expect(productTrackingTypeFromString(null), ProductTrackingType.none);
      expect(
        productTrackingTypeFromString('qualquer-coisa'),
        ProductTrackingType.none,
      );
    });
  });

  group('Product', () {
    Product make({String? sku}) => Product(
          id: 'p1',
          tenantId: 't1',
          name: 'Cabo flexível',
          sku: sku,
          unit: ProductUnit.m,
          trackStock: true,
          minQuantity: 10,
          isActive: true,
          createdAt: DateTime.utc(2026),
        );

    test('displayName inclui SKU quando existe', () {
      expect(make(sku: 'CB-25').displayName, 'CB-25 — Cabo flexível');
    });

    test('displayName usa só o nome quando SKU é null ou vazio', () {
      expect(make().displayName, 'Cabo flexível');
      expect(make(sku: '').displayName, 'Cabo flexível');
    });
  });

  group('productFromRow', () {
    test('desserializa row completo', () {
      final row = {
        'id': 'p1',
        'tenant_id': 't1',
        'name': 'Disjuntor 20A',
        'sku': 'DJ-20',
        'description': 'Bipolar',
        'unit': 'un',
        'track_stock': true,
        'min_quantity': 5,
        'is_active': true,
        'tracking_type': 'lot',
        'created_at': '2026-07-26T10:00:00Z',
      };

      final p = productFromRow(row);
      expect(p.name, 'Disjuntor 20A');
      expect(p.sku, 'DJ-20');
      expect(p.unit, ProductUnit.un);
      expect(p.trackStock, isTrue);
      expect(p.minQuantity, 5);
      expect(p.trackingType, ProductTrackingType.lot);
    });

    test('aplica defaults seguros para campos nulos', () {
      final row = {
        'id': 'p2',
        'tenant_id': 't1',
        'name': 'Item',
        'sku': null,
        'description': null,
        'unit': null,
        'track_stock': null,
        'min_quantity': null,
        'is_active': null,
        'created_at': '2026-07-26T10:00:00Z',
      };

      final p = productFromRow(row);
      expect(p.unit, ProductUnit.un);
      expect(p.trackStock, isTrue);
      expect(p.minQuantity, 0);
      expect(p.isActive, isTrue);
      expect(p.trackingType, ProductTrackingType.none);
    });
  });

  group('warehouseFromRow', () {
    test('desserializa depósito padrão', () {
      final w = warehouseFromRow({
        'id': 'w1',
        'tenant_id': 't1',
        'name': 'Central',
        'is_default': true,
        'is_active': true,
        'created_at': '2026-07-26T10:00:00Z',
      });
      expect(w.name, 'Central');
      expect(w.isDefault, isTrue);
    });
  });

  group('StockMovementKind', () {
    test('value corresponde ao CHECK de stock_movements.kind', () {
      expect(StockMovementKind.entry.value, 'in');
      expect(StockMovementKind.exit.value, 'out');
      expect(StockMovementKind.adjustment.value, 'adjustment');
    });

    test('fromString faz o caminho de volta', () {
      expect(stockMovementKindFromString('in'), StockMovementKind.entry);
      expect(stockMovementKindFromString('out'), StockMovementKind.exit);
      expect(
        stockMovementKindFromString('adjustment'),
        StockMovementKind.adjustment,
      );
    });
  });

  group('StockMovement.averageCostAfterCents', () {
    StockMovement make({
      required double quantityAfter,
      required int valueAfterCents,
    }) =>
        StockMovement(
          id: 'm1',
          kind: StockMovementKind.entry,
          quantity: 1,
          unitCostCents: 100,
          totalCostCents: 100,
          quantityAfter: quantityAfter,
          valueAfterCents: valueAfterCents,
          createdAt: DateTime.utc(2026),
        );

    test('deriva o custo médio do saldo resultante', () {
      final m = make(quantityAfter: 200, valueAfterCents: 60000);
      expect(m.averageCostAfterCents, 300);
    });

    test('arredonda para o centavo mais próximo', () {
      // 9999 / 3 = 3333
      expect(make(quantityAfter: 3, valueAfterCents: 9999)
          .averageCostAfterCents, 3333);
      // 10000 / 3 = 3333,33... -> 3333
      expect(make(quantityAfter: 3, valueAfterCents: 10000)
          .averageCostAfterCents, 3333);
      // 10001 / 3 = 3333,67 -> 3334
      expect(make(quantityAfter: 3, valueAfterCents: 10001)
          .averageCostAfterCents, 3334);
    });

    test('saldo zerado devolve zero em vez de dividir por zero', () {
      expect(make(quantityAfter: 0, valueAfterCents: 0).averageCostAfterCents, 0);
    });
  });

  group('stockMovementFromRow', () {
    test('achata nomes de produto e depósito vindos do join', () {
      final row = {
        'id': 'm1',
        'kind': 'out',
        'quantity': 5,
        'unit_cost_cents': 300,
        'total_cost_cents': 1500,
        'quantity_after': 145,
        'value_after_cents': 43500,
        'reason': 'consumo em campo',
        'related_entity': 'work_orders',
        'related_entity_id': 'wo-1',
        'product_name': 'Cabo',
        'warehouse_name': 'Central',
        'lot_id': 'lot-1',
        'lot_code': 'L-2026-07',
        'created_at': '2026-07-26T12:00:00Z',
      };

      final m = stockMovementFromRow(row);
      expect(m.kind, StockMovementKind.exit);
      expect(m.quantity, 5);
      expect(m.quantityAfter, 145);
      expect(m.productName, 'Cabo');
      expect(m.warehouseName, 'Central');
      expect(m.relatedEntity, 'work_orders');
      expect(m.lotId, 'lot-1');
      expect(m.lotCode, 'L-2026-07');
    });

    test('sem lote, lotId e lotCode ficam null', () {
      final row = {
        'id': 'm2',
        'kind': 'in',
        'quantity': 10,
        'unit_cost_cents': 200,
        'total_cost_cents': 2000,
        'quantity_after': 10,
        'value_after_cents': 2000,
        'created_at': '2026-07-26T12:00:00Z',
      };
      final m = stockMovementFromRow(row);
      expect(m.lotId, isNull);
      expect(m.lotCode, isNull);
    });
  });

  group('StockBalance', () {
    StockBalance make({
      double quantity = 10,
      double minQuantity = 0,
      bool belowMinimum = false,
      ProductUnit unit = ProductUnit.un,
      String? sku,
    }) =>
        StockBalance(
          productId: 'p1',
          productName: 'Cabo',
          sku: sku,
          unit: unit,
          warehouseId: 'w1',
          warehouseName: 'Central',
          quantity: quantity,
          minQuantity: minQuantity,
          totalValueCents: 3000,
          averageUnitCostCents: 300,
          belowMinimum: belowMinimum,
          updatedAt: DateTime.utc(2026),
        );

    test('quantityLabel omite decimais quando o valor é inteiro', () {
      expect(make(quantity: 10).quantityLabel, '10 un');
    });

    test('quantityLabel preserva decimais significativos', () {
      expect(make(quantity: 10.5, unit: ProductUnit.m).quantityLabel, '10.5 m');
      expect(
        make(quantity: 0.25, unit: ProductUnit.kg).quantityLabel,
        '0.25 kg',
      );
    });

    test('quantityLabel corta zeros à direita de numeric(12,3)', () {
      // O banco devolve 2.500 para 2,5 — não deve virar "2.500 un".
      expect(make(quantity: 2.5).quantityLabel, '2.5 un');
    });

    test('isEmpty reflete saldo zerado', () {
      expect(make(quantity: 0).isEmpty, isTrue);
      expect(make(quantity: 0.001).isEmpty, isFalse);
    });

    test('displayName inclui SKU quando existe', () {
      expect(make(sku: 'CB-25').displayName, 'CB-25 — Cabo');
      expect(make().displayName, 'Cabo');
    });
  });

  group('stockBalanceFromRow', () {
    test('desserializa linha de list_stock_balances', () {
      final row = {
        'product_id': 'p1',
        'product_name': 'Cabo flexível',
        'sku': 'CB-25',
        'unit': 'm',
        'warehouse_id': 'w1',
        'warehouse_name': 'Central',
        'quantity': 150,
        'min_quantity': 10,
        'total_value_cents': 45000,
        'average_unit_cost_cents': 300,
        'below_minimum': false,
        'updated_at': '2026-07-26T12:00:00Z',
      };

      final b = stockBalanceFromRow(row);
      expect(b.productName, 'Cabo flexível');
      expect(b.unit, ProductUnit.m);
      expect(b.quantity, 150);
      expect(b.averageUnitCostCents, 300);
      expect(b.belowMinimum, isFalse);
    });

    test('below_minimum vem do servidor, não é recalculado no cliente', () {
      // Mesmo com quantity < min_quantity, o cliente respeita o que o servidor
      // mandou — a regra de alerta mora no banco (list_stock_balances).
      final row = {
        'product_id': 'p1',
        'product_name': 'Cabo',
        'sku': null,
        'unit': 'un',
        'warehouse_id': 'w1',
        'warehouse_name': 'Central',
        'quantity': 2,
        'min_quantity': 10,
        'total_value_cents': 600,
        'average_unit_cost_cents': 300,
        'below_minimum': true,
        'updated_at': '2026-07-26T12:00:00Z',
      };

      expect(stockBalanceFromRow(row).belowMinimum, isTrue);
    });
  });
}
