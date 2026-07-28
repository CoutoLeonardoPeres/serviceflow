/// Leitura da planilha de preços do fornecedor.
///
/// O modelo é do sistema (o fornecedor recebe o arquivo pronto para
/// preencher), então o parser não precisa adivinhar layout — mas precisa
/// aceitar o que o Excel faz com ele na vida real: BOM no começo, CRLF,
/// ponto e vírgula como separador (padrão do Excel em português), vírgula
/// decimal e campos entre aspas.
library;

import 'dart:convert';

/// Uma linha lida da planilha, ainda sem contato com o banco.
class PriceSheetRow {
  const PriceSheetRow({
    required this.line,
    required this.supplierCode,
    this.name,
    this.unit,
    this.category,
    this.brand,
    this.barcode,
    this.priceCents,
    this.packQuantity,
    this.minQuantity,
    this.validUntil,
    this.error,
  });

  /// Número da linha no arquivo, contando o cabeçalho. É o que o operador vê
  /// no Excel — reportar índice de array faria ele caçar a linha errada.
  final int line;
  final String supplierCode;
  final String? name;
  final String? unit;
  final String? category;
  final String? brand;
  final String? barcode;
  final int? priceCents;
  final num? packQuantity;
  final num? minQuantity;
  final DateTime? validUntil;

  /// Problema encontrado na leitura. Linha com erro não vai para o banco.
  final String? error;

  bool get isValid => error == null;

  Map<String, dynamic> toPayload() => {
        'supplier_code': supplierCode,
        'name': name,
        'unit': unit,
        'category': category,
        'brand': brand,
        'barcode': barcode,
        'price': priceCents == null ? null : priceCents! / 100,
        'pack_quantity': packQuantity?.toString(),
        'min_quantity': minQuantity?.toString(),
        'valid_until': validUntil?.toIso8601String().split('T').first,
      };
}

class PriceSheet {
  const PriceSheet({required this.rows, required this.headerProblems});

  final List<PriceSheetRow> rows;

  /// Colunas obrigatórias que faltaram no cabeçalho. Não vazio = arquivo
  /// errado, e nem adianta olhar as linhas.
  final List<String> headerProblems;

  List<PriceSheetRow> get validRows => rows.where((r) => r.isValid).toList();
  List<PriceSheetRow> get invalidRows => rows.where((r) => !r.isValid).toList();
  bool get isUsable => headerProblems.isEmpty && validRows.isNotEmpty;
}

/// Colunas do modelo, na ordem em que saem no arquivo de exemplo.
const priceSheetColumns = <String>[
  'codigo_fornecedor',
  'nome_produto',
  'unidade',
  'categoria',
  'marca',
  'codigo_barras',
  'preco',
  'embalagem',
  'quantidade_minima',
  'validade',
];

const _requiredColumns = <String>['codigo_fornecedor', 'preco'];

/// Modelo em branco, com uma linha de exemplo. O exemplo existe porque
/// planilha vazia com só cabeçalho gera dúvida sobre formato de data e
/// decimal — e a dúvida volta como arquivo mal preenchido.
///
/// O código de barras sai como `="789..."`. Sem isso o Excel trata 13 dígitos
/// como número e mostra `7,89123E+12`; ao salvar, o arquivo volta com a
/// notação científica no lugar do código, e o produto seria cadastrado com
/// código de barras errado. A fórmula força texto e é entendida por Excel,
/// LibreOffice e Google Sheets.
String buildPriceSheetTemplate() {
  final buffer = StringBuffer()
    ..writeln(priceSheetColumns.join(';'))
    ..writeln(
      'CAB-25;Cabo flexível 2,5mm² azul;m;Material elétrico;Prysmian;'
      '="7891234567890";3,49;100;10;31/12/2026',
    );
  return buffer.toString();
}

/// Lê o conteúdo do arquivo. Detecta o separador pela linha de cabeçalho.
PriceSheet parsePriceSheet(String content) {
  final text = repairMojibake(content.replaceFirst('﻿', ''));
  final lines = _splitRecords(text);
  if (lines.isEmpty) {
    return const PriceSheet(
      rows: [],
      headerProblems: ['O arquivo está vazio.'],
    );
  }

  final separator = _detectSeparator(lines.first);
  final header = _splitFields(lines.first, separator)
      .map(_normalizeHeader)
      .toList();

  final missing = _requiredColumns
      .where((column) => !header.contains(column))
      .map((column) => 'Coluna obrigatória ausente: $column')
      .toList();
  if (missing.isNotEmpty) {
    return PriceSheet(rows: const [], headerProblems: missing);
  }

  int indexOf(String column) => header.indexOf(column);
  final rows = <PriceSheetRow>[];

  for (var i = 1; i < lines.length; i++) {
    final raw = lines[i];
    if (raw.trim().isEmpty) continue;

    final fields = _splitFields(raw, separator);
    String? field(String column) {
      final index = indexOf(column);
      if (index < 0 || index >= fields.length) return null;
      final value = fields[index].trim();
      return value.isEmpty ? null : value;
    }

    // Linha do arquivo: cabeçalho é a 1, então a primeira de dados é a 2.
    final line = i + 1;
    final code = field('codigo_fornecedor');
    if (code == null) {
      rows.add(PriceSheetRow(
        line: line,
        supplierCode: '',
        error: 'Código do fornecedor em branco',
      ));
      continue;
    }

    final priceCents = _parseMoneyCents(field('preco'));
    if (priceCents == null) {
      rows.add(PriceSheetRow(
        line: line,
        supplierCode: code,
        name: field('nome_produto'),
        error: 'Preço inválido ou ausente',
      ));
      continue;
    }

    // Código de barras que voltou como 7,89123E+12 não é código: é o que
    // sobrou depois de o Excel tratar 13 dígitos como número. Gravar isso
    // cadastraria o produto com um código que não existe, e ninguém
    // perceberia até tentar bipar.
    final barcode = _cleanBarcode(field('codigo_barras'));
    if (barcode == _scientificNotation) {
      rows.add(PriceSheetRow(
        line: line,
        supplierCode: code,
        name: field('nome_produto'),
        error: 'Código de barras veio em notação científica '
            '(o Excel converteu). Formate a coluna como Texto e reenvie.',
      ));
      continue;
    }

    rows.add(PriceSheetRow(
      line: line,
      supplierCode: code,
      name: field('nome_produto'),
      unit: field('unidade')?.toLowerCase(),
      category: field('categoria'),
      brand: field('marca'),
      barcode: barcode,
      priceCents: priceCents,
      packQuantity: _parseNumber(field('embalagem')) ?? 1,
      minQuantity: _parseNumber(field('quantidade_minima')) ?? 0,
      validUntil: _parseDate(field('validade')),
    ));
  }

  return PriceSheet(rows: rows, headerProblems: const []);
}

/// Quebra em registros respeitando quebra de linha dentro de aspas — descrição
/// de material com quebra de linha existe e destruiria o alinhamento.
List<String> _splitRecords(String text) {
  final records = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '"') {
      inQuotes = !inQuotes;
      buffer.write(char);
      continue;
    }
    if (!inQuotes && (char == '\n' || char == '\r')) {
      if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      records.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) records.add(buffer.toString());
  return records.where((r) => r.trim().isNotEmpty).toList();
}

/// Excel em português salva CSV com ponto e vírgula. Contar qual aparece mais
/// no cabeçalho acerta os dois casos sem perguntar nada ao usuário.
String _detectSeparator(String headerLine) {
  final semicolons = headerLine.split(';').length;
  final commas = headerLine.split(',').length;
  final tabs = headerLine.split('\t').length;
  if (tabs > semicolons && tabs > commas) return '\t';
  return semicolons >= commas ? ';' : ',';
}

List<String> _splitFields(String line, String separator) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      // Aspas duplas dentro de campo entre aspas representam uma aspa.
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
        continue;
      }
      inQuotes = !inQuotes;
      continue;
    }
    if (!inQuotes && char == separator) {
      fields.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  fields.add(buffer.toString());
  return fields;
}

String _normalizeHeader(String raw) {
  var value = raw.trim().toLowerCase();
  const accents = {
    'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a',
    'é': 'e', 'ê': 'e',
    'í': 'i',
    'ó': 'o', 'ô': 'o', 'õ': 'o',
    'ú': 'u',
    'ç': 'c',
  };
  accents.forEach((from, to) => value = value.replaceAll(from, to));
  return value.replaceAll(RegExp(r'[\s\-]+'), '_');
}

/// Aceita "3,49", "3.49", "R$ 3,49" e "1.234,56". A regra do milhar: se tem
/// vírgula, o ponto é separador de milhar e some.
int? _parseMoneyCents(String? raw) {
  if (raw == null) return null;
  var value = raw.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (value.isEmpty) return null;

  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  }
  final parsed = double.tryParse(value);
  if (parsed == null || parsed < 0) return null;
  return (parsed * 100).round();
}

num? _parseNumber(String? raw) {
  if (raw == null) return null;
  var value = raw.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (value.isEmpty) return null;
  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(value);
}

/// Aceita dd/MM/yyyy (o que o Brasil escreve) e yyyy-MM-dd (o que o Excel
/// às vezes exporta).
DateTime? _parseDate(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();

  final br = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(value);
  if (br != null) {
    return DateTime(
      int.parse(br.group(3)!),
      int.parse(br.group(2)!),
      int.parse(br.group(1)!),
    );
  }
  return DateTime.tryParse(value);
}


/// Marcador interno: o valor não é aproveitável, a linha precisa ser recusada.
const _scientificNotation = '\u0000cientifica';

/// Limpa o que as planilhas fazem com código de barras.
///
/// `="789..."` é a fórmula que o próprio modelo usa para forçar texto —
/// chega de volta assim e precisa ser desembrulhada. Notação científica é
/// perda de informação e não tem conserto: o número original não está mais
/// ali.
String? _cleanBarcode(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();

  final formula = RegExp(r'^="?([^"]*)"?$').firstMatch(value);
  if (formula != null) value = formula.group(1)!.trim();
  value = value.replaceAll('"', '').trim();
  if (value.isEmpty) return null;

  if (RegExp(r'^\d+([.,]\d+)?[eE][+-]?\d+$').hasMatch(value)) {
    return _scientificNotation;
  }
  return value;
}

/// Desfaz texto UTF-8 que foi lido como Latin-1 ou MacRoman.
///
/// Acontece quando a planilha passa por um editor que não reconheceu a
/// codificação — "Material elétrico" chega como "Material el√©trico" ou
/// "Material elÃ©trico". Sem isso o produto entra no catálogo com o nome
/// corrompido e nunca mais casa numa busca.
///
/// Só age quando encontra as marcas típicas; texto correto passa intocado.
String repairMojibake(String text) {
  const marcasMac = ['√ß', '√£', '√°', '√©', '√≠', '√™', '√¥', '√µ', '√∫'];
  const marcasLatin = ['Ã§', 'Ã£', 'Ã¡', 'Ã©', 'Ã­', 'Ãª', 'Ã´', 'Ãµ', 'Ãº'];

  if (marcasLatin.any(text.contains)) {
    try {
      return utf8.decode(latin1.encode(text));
    } catch (_) {
      return text;
    }
  }
  if (marcasMac.any(text.contains)) {
    try {
      return utf8.decode(_macRomanEncode(text));
    } catch (_) {
      return text;
    }
  }
  return text;
}

/// Só os caracteres que o MacRoman usa para os bytes altos de UTF-8 em
/// português. Uma tabela completa seria 128 entradas para resolver as 20 que
/// aparecem de fato.
const _macRomanReverse = <String, int>{
  '√': 0xC3, 'ß': 0xA7, '£': 0xA3, '°': 0xA1, '©': 0xA9, '≠': 0xAD,
  '™': 0xAA, '¥': 0xB4, 'µ': 0xB5, '∫': 0xBA, '¢': 0xA2, '§': 0xA4,
  '•': 0xA5, '¶': 0xA6, '®': 0xA8, '¨': 0xAC, '±': 0xB1, '‰': 0xE9,
  '¬': 0xC2, 'Œ': 0xCE, '≤': 0xB2, '≥': 0xB3, 'π': 0xB9, '∂': 0xB6,
};

List<int> _macRomanEncode(String text) {
  final bytes = <int>[];
  for (final rune in text.runes) {
    if (rune < 128) {
      bytes.add(rune);
      continue;
    }
    final mapped = _macRomanReverse[String.fromCharCode(rune)];
    if (mapped == null) throw const FormatException('fora da tabela MacRoman');
    bytes.add(mapped);
  }
  return bytes;
}
