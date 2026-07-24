import '../../../core/utils/validators.dart';
import 'customer.dart';
import 'customer_address.dart';

class CustomerImportRow {
  const CustomerImportRow({
    required this.rowNumber,
    required this.type,
    required this.name,
    this.tradeName,
    this.document,
    this.email,
    this.phone,
    this.contactName,
    this.contactPhone,
    this.cep,
    this.street,
    this.number,
    this.complement,
    this.district,
    this.city,
    this.state,
    this.notes,
  });

  final int rowNumber;
  final CustomerType type;
  final String name;
  final String? tradeName;
  final String? document;
  final String? email;
  final String? phone;
  final String? contactName;
  final String? contactPhone;
  final String? cep;
  final String? street;
  final String? number;
  final String? complement;
  final String? district;
  final String? city;
  final String? state;
  final String? notes;

  bool get hasAddress =>
      [street, number, district, city, state].any((value) => value != null);
}

class CustomerImportIssue {
  const CustomerImportIssue({
    required this.rowNumber,
    required this.message,
  });

  final int rowNumber;
  final String message;
}

class CustomerImportPreview {
  const CustomerImportPreview({
    required this.rows,
    required this.issues,
    required this.delimiterLabel,
  });

  final List<CustomerImportRow> rows;
  final List<CustomerImportIssue> issues;
  final String delimiterLabel;
}

class CustomerImportResult {
  const CustomerImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.issues,
  });

  final int importedCount;
  final int skippedCount;
  final int failedCount;
  final List<CustomerImportIssue> issues;
}

CustomerImportPreview parseCustomerImportCsv(String rawText) {
  final sanitized = rawText.replaceFirst('\uFEFF', '').trim();
  if (sanitized.isEmpty) {
    return const CustomerImportPreview(
      rows: [],
      issues: [CustomerImportIssue(rowNumber: 0, message: 'Arquivo vazio.')],
      delimiterLabel: ';',
    );
  }

  final lines = sanitized
      .split(RegExp(r'\r\n|\n|\r'))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return const CustomerImportPreview(
      rows: [],
      issues: [CustomerImportIssue(rowNumber: 0, message: 'Arquivo vazio.')],
      delimiterLabel: ';',
    );
  }

  final headerLine = lines.first;
  final semicolons = ';'.allMatches(headerLine).length;
  final commas = ','.allMatches(headerLine).length;
  final delimiter = semicolons >= commas ? ';' : ',';
  final headers = _parseCsvLine(headerLine, delimiter)
      .map(_normalizeHeader)
      .toList(growable: false);

  final rows = <CustomerImportRow>[];
  final issues = <CustomerImportIssue>[];

  for (var index = 1; index < lines.length; index++) {
    final rowNumber = index + 1;
    final values = _parseCsvLine(lines[index], delimiter);
    if (values.every((value) => value.trim().isEmpty)) {
      continue;
    }

    final map = <String, String>{};
    for (var column = 0; column < headers.length; column++) {
      final key = headers[column];
      final value = column < values.length ? values[column].trim() : '';
      if (key.isNotEmpty) {
        map[key] = value;
      }
    }

    final parsed = _mapImportRow(rowNumber, map);
    if (parsed is CustomerImportRow) {
      rows.add(parsed);
    } else if (parsed is CustomerImportIssue) {
      issues.add(parsed);
    }
  }

  return CustomerImportPreview(
    rows: rows,
    issues: issues,
    delimiterLabel: delimiter,
  );
}

Object _mapImportRow(int rowNumber, Map<String, String> map) {
  final name = _pickValue(map, const [
    'nome',
    'nomecompleto',
    'razaosocial',
  ]);
  if (name == null || name.trim().isEmpty) {
    return CustomerImportIssue(
      rowNumber: rowNumber,
      message: 'Linha sem nome do cliente.',
    );
  }

  final document = _digitsOnly(
    _pickValue(map, const ['cpfcnpj', 'documento', 'cpf', 'cnpj']),
  );
  final phone = _digitsOnly(
    _pickValue(map, const ['telefone', 'celular', 'fone', 'whatsapp']),
  );
  final contactPhone = _digitsOnly(
    _pickValue(map, const ['contatotelefone', 'telefonedocontato']),
  );

  final explicitType = _parseType(_pickValue(map, const ['tipo']));
  final resolvedType = explicitType ?? _typeFromDocument(document);

  if (document != null) {
    final docError =
        resolvedType.usesCpf ? validateCpf(document) : validateCnpj(document);
    if (docError != null) {
      return CustomerImportIssue(
        rowNumber: rowNumber,
        message: 'CPF/CNPJ inválido.',
      );
    }
  }

  if (phone != null && validatePhone(phone) != null) {
    return CustomerImportIssue(
      rowNumber: rowNumber,
      message: 'Telefone inválido.',
    );
  }

  if (contactPhone != null && validatePhone(contactPhone) != null) {
    return CustomerImportIssue(
      rowNumber: rowNumber,
      message: 'Telefone do contato inválido.',
    );
  }

  final state = _normalizeState(_pickValue(map, const ['uf', 'estado']));
  if (state != null && !kBrazilianStates.contains(state)) {
    return CustomerImportIssue(
      rowNumber: rowNumber,
      message: 'UF inválida.',
    );
  }

  final cep = _digitsOnly(_pickValue(map, const ['cep']));
  if (cep != null && validateCep(cep) != null) {
    return CustomerImportIssue(
      rowNumber: rowNumber,
      message: 'CEP inválido.',
    );
  }

  return CustomerImportRow(
    rowNumber: rowNumber,
    type: resolvedType,
    name: name.trim(),
    tradeName: _clean(_pickValue(map, const ['nomefantasia', 'fantasia'])),
    document: document,
    email: _clean(_pickValue(map, const ['email', 'emailprincipal'])),
    phone: phone,
    contactName: _clean(
          _pickValue(map, const ['contato', 'contatonome', 'responsavel']),
        ) ??
        name.trim(),
    contactPhone: contactPhone ?? phone,
    cep: cep,
    street: _clean(_pickValue(map, const ['logradouro', 'rua', 'endereco'])),
    number: _clean(_pickValue(map, const ['numero', 'n'])),
    complement: _clean(_pickValue(map, const ['complemento', 'compl'])),
    district: _clean(_pickValue(map, const ['bairro'])),
    city: _clean(_pickValue(map, const ['cidade', 'municipio'])),
    state: state,
    notes: _clean(_pickValue(map, const ['observacoes', 'obs', 'notas'])),
  );
}

List<String> _parseCsvLine(String line, String delimiter) {
  final values = <String>[];
  final buffer = StringBuffer();
  var insideQuotes = false;

  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (char == '"') {
      final nextIsQuote = index + 1 < line.length && line[index + 1] == '"';
      if (insideQuotes && nextIsQuote) {
        buffer.write('"');
        index++;
      } else {
        insideQuotes = !insideQuotes;
      }
      continue;
    }

    if (char == delimiter && !insideQuotes) {
      values.add(buffer.toString());
      buffer.clear();
      continue;
    }

    buffer.write(char);
  }

  values.add(buffer.toString());
  return values;
}

String _normalizeHeader(String raw) {
  final lower = _removeAccents(raw).toLowerCase().trim();
  return lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _removeAccents(String value) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  return value.split('').map((char) => accents[char] ?? char).join();
}

String? _pickValue(Map<String, String> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

String? _clean(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

String? _digitsOnly(String? value) {
  if (value == null) return null;
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : digits;
}

CustomerType? _parseType(String? raw) {
  if (raw == null) return null;
  final value = _normalizeHeader(raw);
  if (value.contains('fisica') || value == 'pf' || value == 'person') {
    return CustomerType.person;
  }
  if (value.contains('empresa') || value == 'pj' || value.contains('company')) {
    return CustomerType.company;
  }
  if (value.contains('condominio')) {
    return CustomerType.condominium;
  }
  if (value.contains('entidadepublica') || value.contains('publica')) {
    return CustomerType.publicEntity;
  }
  return null;
}

CustomerType _typeFromDocument(String? document) {
  if (document != null && document.length == 11) {
    return CustomerType.person;
  }
  return CustomerType.company;
}

String? _normalizeState(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return _removeAccents(value).trim().toUpperCase();
}
