import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/work_orders/domain/work_order_material.dart';

void main() {
  group('WorkOrderMaterial.originLabel', () {
    WorkOrderMaterial make({
      String? productId,
      bool fromStock = false,
    }) =>
        WorkOrderMaterial(
          id: 'm1',
          description: 'Cabo',
          quantity: 10,
          unitCostCents: 500,
          unitPriceCents: 1200,
          totalCostCents: 5000,
          totalPriceCents: 12000,
          fromStock: fromStock,
          productId: productId,
          createdAt: DateTime.utc(2026, 7, 26),
        );

    test('lançamento que baixou estoque', () {
      final m = make(productId: 'p1', fromStock: true);
      expect(m.originLabel, 'Baixado do estoque');
      expect(m.isCatalogWithoutStock, isFalse);
    });

    test('produto do catálogo sem controle de saldo', () {
      // track_stock = false: vincula para rastreabilidade, não movimenta.
      final m = make(productId: 'p1', fromStock: false);
      expect(m.originLabel, 'Catálogo, sem controle de saldo');
      expect(m.isCatalogWithoutStock, isTrue);
    });

    test('texto livre, fora do catálogo', () {
      final m = make();
      expect(m.originLabel, 'Fora do catálogo');
      expect(m.isCatalogWithoutStock, isFalse);
    });
  });

  group('workOrderMaterialFromRow', () {
    test('desserializa lançamento com baixa de estoque', () {
      final row = {
        'id': 'm1',
        'description': 'Cabo para OS',
        'quantity': 10,
        'unit_cost_cents': 500,
        'unit_price_cents': 1200,
        'total_cost_cents': 5000,
        'total_price_cents': 12000,
        'product_id': 'p1',
        'product_name': 'Cabo para OS',
        'from_stock': true,
        'created_at': '2026-07-26T12:00:00Z',
      };

      final m = workOrderMaterialFromRow(row);
      expect(m.description, 'Cabo para OS');
      expect(m.quantity, 10);
      expect(m.unitCostCents, 500);
      expect(m.productId, 'p1');
      expect(m.productName, 'Cabo para OS');
      expect(m.fromStock, isTrue);
    });

    test('desserializa lançamento em texto livre', () {
      final row = {
        'id': 'm2',
        'description': 'Fita isolante avulsa',
        'quantity': 2,
        'unit_cost_cents': 800,
        'unit_price_cents': 1500,
        'total_cost_cents': 1600,
        'total_price_cents': 3000,
        'product_id': null,
        'product_name': null,
        'from_stock': false,
        'created_at': '2026-07-26T12:00:00Z',
      };

      final m = workOrderMaterialFromRow(row);
      expect(m.productId, isNull);
      expect(m.productName, isNull);
      expect(m.fromStock, isFalse);
      expect(m.originLabel, 'Fora do catálogo');
    });

    test('from_stock nulo assume false — nunca presume baixa', () {
      final row = {
        'id': 'm3',
        'description': 'Item',
        'quantity': 1,
        'unit_cost_cents': null,
        'unit_price_cents': null,
        'total_cost_cents': null,
        'total_price_cents': null,
        'product_id': null,
        'product_name': null,
        'from_stock': null,
        'created_at': '2026-07-26T12:00:00Z',
      };

      final m = workOrderMaterialFromRow(row);
      expect(m.fromStock, isFalse);
      expect(m.unitCostCents, 0);
    });
  });

  group('workOrderMaterialResultFromMap', () {
    test('captura o custo médio aplicado pelo servidor', () {
      // O formulário mandou custo 0; o servidor sobrescreveu com o médio 500.
      final map = {
        'id': 'm1',
        'total_price_cents': 12000,
        'unit_cost_cents': 500,
        'stock_movement_id': 'mv1',
        'from_stock': true,
      };

      final r = workOrderMaterialResultFromMap(map);
      expect(r.unitCostCents, 500);
      expect(r.fromStock, isTrue);
      expect(r.stockMovementId, 'mv1');
    });

    test('lançamento sem baixa não traz movimento', () {
      final map = {
        'id': 'm2',
        'total_price_cents': 3000,
        'unit_cost_cents': 800,
        'stock_movement_id': null,
        'from_stock': false,
      };

      final r = workOrderMaterialResultFromMap(map);
      expect(r.fromStock, isFalse);
      expect(r.stockMovementId, isNull);
      expect(r.unitCostCents, 800);
    });
  });
}
