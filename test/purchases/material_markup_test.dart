import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/purchases/domain/material_catalog.dart';

/// Guarda o cálculo de repasse ao cliente.
///
/// Espelha `best_price_for_product` (migration 0059). Se divergir, a tela
/// mostra um preço e o banco grava outro — que é o tipo de erro que só
/// aparece na fatura do cliente.
void main() {
  group('applyMarkup', () {
    test('aplica o percentual sobre o custo', () {
      expect(applyMarkup(800, 50), 1200);
      expect(applyMarkup(800, 10), 880);
      expect(applyMarkup(1000, 0), 1000);
    });

    test('arredonda para o centavo mais próximo, sem truncar', () {
      // 333 + 10% = 366,3 → 366
      expect(applyMarkup(333, 10), 366);
      // 335 + 10% = 368,5 → 369 (truncar daria 368 e perderia margem em
      // todo item barato vendido em quantidade)
      expect(applyMarkup(335, 10), 369);
    });

    test('margem alta não estoura nem perde precisão', () {
      expect(applyMarkup(199, 300), 796);
    });
  });

  group('effectiveMarkup', () {
    test('produto vence categoria, que vence o padrão da empresa', () {
      expect(
        effectiveMarkup(
          productMarkup: 10,
          categoryMarkup: 50,
          tenantDefault: 30,
        ),
        10,
      );
    });

    test('sem margem no produto, usa a da categoria', () {
      expect(
        effectiveMarkup(categoryMarkup: 50, tenantDefault: 30),
        50,
      );
    });

    test('sem produto e sem categoria, usa o padrão da empresa', () {
      expect(effectiveMarkup(tenantDefault: 30), 30);
    });

    test('zero é margem válida, não "sem margem"', () {
      // A diferença importa: null herda, zero vende a preço de custo.
      expect(
        effectiveMarkup(productMarkup: 0, categoryMarkup: 50),
        0,
      );
    });

    test('sem nenhum nível definido, não inventa margem', () {
      expect(effectiveMarkup(), 0);
    });
  });

  group('SupplierPrice.isStale', () {
    test('tabela sem validade nunca vence', () {
      const price = SupplierPrice(
        id: 'p1',
        supplierId: 's1',
        productId: 'prod1',
        priceCents: 1000,
        packQuantity: 1,
        minQuantity: 0,
        isActive: true,
      );
      expect(price.isStale, isFalse);
    });

    test('validade no passado marca como vencida', () {
      final price = SupplierPrice(
        id: 'p1',
        supplierId: 's1',
        productId: 'prod1',
        priceCents: 1000,
        packQuantity: 1,
        minQuantity: 0,
        isActive: true,
        validUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(price.isStale, isTrue);
    });

    test('validade no futuro segue valendo', () {
      final price = SupplierPrice(
        id: 'p1',
        supplierId: 's1',
        productId: 'prod1',
        priceCents: 1000,
        packQuantity: 1,
        minQuantity: 0,
        isActive: true,
        validUntil: DateTime.now().add(const Duration(days: 30)),
      );
      expect(price.isStale, isFalse);
    });
  });
}
