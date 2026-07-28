/// Leitura da planilha de preços do fornecedor.
///
/// O modelo é do sistema (o fornecedor recebe o arquivo pronto para
/// preencher), então o parser não precisa adivinhar layout — mas precisa
/// aceitar o que o Excel faz com ele na vida real: BOM no começo, CRLF,
/// ponto e vírgula como separador (padrão do Excel em português), vírgula
/// decimal e campos entre aspas.
library;

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
String buildPriceSheetTemplate() {
  final buffer = StringBuffer()
    ..writeln(priceSheetColumns.join(';'))
    ..writeln(
      'CAB-25;Cabo flexível 2,5mm² azul;m;Material elétrico;Prysmian;'
      '7891234567890;3,49;100;10;31/12/2026',
    );
  return buffer.toString();
}

/// Lê o conteúdo do arquivo. Detecta o separador pela linha de cabeçalho.
PriceSheet parsePriceSheet(String content) {
  final text = content.replaceFirst('﻿', '');
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

    rows.add(PriceSheetRow(
      line: line,
      supplierCode: code,
      name: field('nome_produto'),
      unit: field('unidade')?.toLowerCase(),
      category: field('categoria'),
      brand: field('marca'),
      barcode: field('codigo_barras'),
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
