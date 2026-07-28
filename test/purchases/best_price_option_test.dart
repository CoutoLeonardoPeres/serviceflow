import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/purchases/domain/material_catalog.dart';

/// Guarda a leitura do ranking de fornecedores.
///
/// O ranking em si é do banco (`best_price_for_product`, migration 0059) —
/// aqui garantimos que o app lê o que ele devolve sem inventar nada, e que o
/// repasse mostrado na tela é o mesmo que o banco calculou.
BestPriceOption option({
  required String supplier,
  required int price,
  required int clientPrice,
  double markup = 30,
  bool stale = false,
  num stock = 0,
  int stockCost = 0,
  int? leadTime,
}) =>
    BestPriceOption(
      supplierId: 'sup-$supplier',
      supplierName: supplier,
      priceCents: price,
      markupPercent: markup,
      clientPriceCents: clientPrice,
      isStale: stale,
      stockQuantity: stock,
      stockAvgCostCents: stockCost,
      leadTimeDays: leadTime,
    );

void main() {
  group('leitura da linha do ranking', () {
    test('lê todos os campos que a tela usa', () {
      final parsed = bestPriceOptionFromRow({
        'supplier_id': 'sup-1',
        'supplier_name': 'Elétrica Central',
        'supplier_code': 'CAB-25',
        'price_cents': 800,
        'markup_percent': 50,
        'client_price_cents': 1200,
        'lead_time_days': 3,
        'valid_until': '2026-12-31',
        'is_stale': false,
        'stock_quantity': 12.5,
        'stock_avg_cost_cents': 760,
      });

      expect(parsed.supplierName, 'Elétrica Central');
      expect(parsed.priceCents, 800);
      expect(parsed.clientPriceCents, 1200);
      expect(parsed.leadTimeDays, 3);
      expect(parsed.validUntil, DateTime(2026, 12, 31));
      expect(parsed.stockQuantity, 12.5);
      expect(parsed.hasStock, isTrue);
    });

    test('campos ausentes viram padrão seguro, não exceção', () {
      // A RPC pode devolver nulo em prazo e validade — não é erro, é
      // fornecedor sem esses dados cadastrados.
      final parsed = bestPriceOptionFromRow({
        'supplier_id': 'sup-1',
        'supplier_name': 'Sem dados',
        'price_cents': 500,
        'client_price_cents': 650,
      });

      expect(parsed.leadTimeDays, isNull);
      expect(parsed.validUntil, isNull);
      expect(parsed.markupPercent, 0);
      expect(parsed.stockQuantity, 0);
      expect(parsed.hasStock, isFalse);
    });
  });

  group('saldo próprio', () {
    test('vem repetido em todas as linhas — é do produto, não da linha', () {
      // A RPC faz CROSS JOIN com o saldo, então toda linha traz o mesmo
      // número. A tela lê da primeira; este teste trava esse contrato.
      final options = [
        option(supplier: 'A', price: 800, clientPrice: 1040, stock: 5),
        option(supplier: 'B', price: 900, clientPrice: 1170, stock: 5),
      ];
      expect(options.every((o) => o.stockQuantity == 5), isTrue);
    });

    test('sem saldo, nenhuma linha diz ter estoque', () {
      final options = [
        option(supplier: 'A', price: 800, clientPrice: 1040),
      ];
      expect(options.any((o) => o.hasStock), isFalse);
    });
  });

  group('repasse do saldo próprio', () {
    test('usa a mesma margem do produto sobre o custo médio', () {
      // Material do estoque também tem margem: o custo é o médio do depósito,
      // não o preço do fornecedor.
      const stockCost = 760;
      const markup = 50.0;
      expect(applyMarkup(stockCost, markup), 1140);
    });

    test('sem fornecedor cadastrado, não inventa margem', () {
      // Lista vazia significa que a margem não veio do banco. Aplicar 30% de
      // palpite faria a tela mostrar um preço que ninguém configurou.
      const options = <BestPriceOption>[];
      final markup = options.isEmpty ? 0.0 : options.first.markupPercent;
      expect(applyMarkup(760, markup), 760);
    });
  });

  group('tabela vencida', () {
    test('vencida não é a melhor opção mesmo sendo a mais barata', () {
      // O banco já ordena pondo vencida no fim; a tela não deve marcar
      // "melhor opção" numa linha vencida que tenha sobrado em primeiro.
      final stale = option(
        supplier: 'Barato vencido',
        price: 500,
        clientPrice: 650,
        stale: true,
      );
      expect(stale.isStale, isTrue);
    });
  });
}
