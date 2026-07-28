import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/purchases/domain/price_sheet.dart';

/// Guarda a leitura da planilha de preços.
///
/// Cada caso aqui é uma coisa que o Excel realmente faz com um CSV em
/// português — separador ponto e vírgula, vírgula decimal, BOM, CRLF,
/// Latin-1, campo entre aspas com vírgula dentro. Errar qualquer um deles
/// significa importar preço errado, que só aparece na proposta do cliente.
void main() {
  group('cabeçalho', () {
    test('arquivo vazio é recusado com motivo', () {
      final sheet = parsePriceSheet('');
      expect(sheet.headerProblems, isNotEmpty);
      expect(sheet.isUsable, isFalse);
    });

    test('falta de coluna obrigatória impede a leitura das linhas', () {
      final sheet = parsePriceSheet('nome_produto;preco\nCabo;3,49');
      expect(sheet.headerProblems.single, contains('codigo_fornecedor'));
      expect(sheet.rows, isEmpty);
    });

    test('aceita cabeçalho com acento, maiúscula e espaço', () {
      final sheet = parsePriceSheet(
        'Código Fornecedor;Nome Produto;Preço\nCAB-25;Cabo;3,49',
      );
      expect(sheet.headerProblems, isEmpty);
      expect(sheet.validRows.single.supplierCode, 'CAB-25');
      expect(sheet.validRows.single.priceCents, 349);
    });
  });

  group('separador e codificação', () {
    test('detecta ponto e vírgula, que é o padrão do Excel em português', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;nome_produto;preco\nA1;Cabo;10,00',
      );
      expect(sheet.validRows.single.priceCents, 1000);
    });

    test('detecta vírgula quando o arquivo vem no padrão internacional', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor,nome_produto,preco\nA1,Cabo,10.00',
      );
      expect(sheet.validRows.single.priceCents, 1000);
    });

    test('ignora o BOM que o Excel escreve no começo do arquivo', () {
      final sheet = parsePriceSheet(
        '﻿codigo_fornecedor;preco\nA1;5,00',
      );
      expect(sheet.headerProblems, isEmpty);
      expect(sheet.validRows.single.supplierCode, 'A1');
    });

    test('aceita quebra de linha do Windows', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;preco\r\nA1;5,00\r\nA2;6,00\r\n',
      );
      expect(sheet.validRows.length, 2);
    });
  });

  group('campos entre aspas', () {
    test('vírgula dentro de aspas não quebra a coluna', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor,nome_produto,preco\n'
        'A1,"Cabo flexível 2,5mm azul",10.00',
      );
      expect(sheet.validRows.single.name, 'Cabo flexível 2,5mm azul');
      expect(sheet.validRows.single.priceCents, 1000);
    });

    test('aspas duplas escapadas viram uma aspa', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;nome_produto;preco\n'
        'A1;"Tubo 3"" polegadas";10,00',
      );
      expect(sheet.validRows.single.name, 'Tubo 3" polegadas');
    });

    test('quebra de linha dentro de aspas não vira registro novo', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;nome_produto;preco\n'
        'A1;"Cabo\ncom descrição longa";10,00',
      );
      expect(sheet.validRows.length, 1);
      expect(sheet.validRows.single.name, contains('descrição'));
    });
  });

  group('preço', () {
    test('vírgula decimal', () {
      final sheet = parsePriceSheet('codigo_fornecedor;preco\nA1;3,49');
      expect(sheet.validRows.single.priceCents, 349);
    });

    test('ponto como separador de milhar junto com vírgula decimal', () {
      final sheet = parsePriceSheet('codigo_fornecedor;preco\nA1;1.234,56');
      expect(sheet.validRows.single.priceCents, 123456);
    });

    test('símbolo de moeda é ignorado', () {
      final sheet = parsePriceSheet('codigo_fornecedor;preco\nA1;R\$ 3,49');
      expect(sheet.validRows.single.priceCents, 349);
    });

    test('preço em branco vira linha recusada, não zero', () {
      // Importar como zero seria pior que recusar: viraria orçamento de graça.
      final sheet = parsePriceSheet('codigo_fornecedor;preco\nA1;');
      expect(sheet.validRows, isEmpty);
      expect(sheet.invalidRows.single.error, contains('Preço'));
      expect(sheet.invalidRows.single.line, 2);
    });

    test('preço não numérico é recusado', () {
      final sheet = parsePriceSheet('codigo_fornecedor;preco\nA1;sob consulta');
      expect(sheet.invalidRows.single.error, contains('Preço'));
    });
  });

  group('validade', () {
    test('aceita data no formato brasileiro', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;preco;validade\nA1;1,00;31/12/2026',
      );
      expect(sheet.validRows.single.validUntil, DateTime(2026, 12, 31));
    });

    test('aceita ISO, que é o que o Excel às vezes exporta', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;preco;validade\nA1;1,00;2026-12-31',
      );
      expect(sheet.validRows.single.validUntil, DateTime(2026, 12, 31));
    });

    test('data inválida não derruba a linha — fica sem validade', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;preco;validade\nA1;1,00;dezembro',
      );
      expect(sheet.validRows.single.validUntil, isNull);
      expect(sheet.validRows.single.isValid, isTrue);
    });
  });

  group('linhas', () {
    test('número da linha bate com o do Excel, contando o cabeçalho', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;preco\nA1;1,00\n;2,00\nA3;3,00',
      );
      final invalid = sheet.invalidRows.single;
      expect(invalid.line, 3);
    });

    test('linhas em branco no fim não viram registro', () {
      final sheet = parsePriceSheet(
        'codigo_fornecedor;preco\nA1;1,00\n\n\n',
      );
      expect(sheet.rows.length, 1);
    });

    test('embalagem e mínimo têm padrão quando ausentes', () {
      final sheet = parsePriceSheet('codigo_fornecedor;preco\nA1;1,00');
      expect(sheet.validRows.single.packQuantity, 1);
      expect(sheet.validRows.single.minQuantity, 0);
    });
  });

  group('modelo gerado', () {
    test('o próprio modelo é lido sem erro pelo parser', () {
      // Se o modelo que entregamos não passar pelo nosso parser, o primeiro
      // arquivo que o fornecedor devolve já falha.
      final sheet = parsePriceSheet(buildPriceSheetTemplate());
      expect(sheet.headerProblems, isEmpty);
      expect(sheet.validRows.length, 1);
      expect(sheet.validRows.single.supplierCode, 'CAB-25');
      expect(sheet.validRows.single.priceCents, 349);
      expect(sheet.validRows.single.unit, 'm');
      expect(sheet.validRows.single.validUntil, DateTime(2026, 12, 31));
    });

    test('o modelo tem todas as colunas documentadas', () {
      final header = buildPriceSheetTemplate().split('\n').first.split(';');
      expect(header, priceSheetColumns);
    });
  });
}
