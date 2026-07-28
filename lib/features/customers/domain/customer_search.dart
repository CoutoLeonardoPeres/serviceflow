import 'customer.dart';

/// Busca de cliente por nome, documento ou telefone — usada no formulário de
/// chamado e no de orçamento. Ficava duplicada como funções privadas de tela.

String normalizeSearchText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[áàâãä]'), 'a')
    .replaceAll(RegExp(r'[éèêë]'), 'e')
    .replaceAll(RegExp(r'[íìîï]'), 'i')
    .replaceAll(RegExp(r'[óòôõö]'), 'o')
    .replaceAll(RegExp(r'[úùûü]'), 'u')
    .replaceAll('ç', 'c')
    .trim();

String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

String formatCpf(String value) {
  final digits = digitsOnly(value);
  if (digits.length != 11) return value;
  return '${digits.substring(0, 3)}.${digits.substring(3, 6)}'
      '.${digits.substring(6, 9)}-${digits.substring(9)}';
}

String formatCnpj(String value) {
  final digits = digitsOnly(value);
  if (digits.length != 14) return value;
  return '${digits.substring(0, 2)}.${digits.substring(2, 5)}'
      '.${digits.substring(5, 8)}/${digits.substring(8, 12)}'
      '-${digits.substring(12)}';
}

String formatPhone(String value) {
  final digits = digitsOnly(value);
  if (digits.length == 10) {
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}'
        '-${digits.substring(6)}';
  }
  if (digits.length == 11) {
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}'
        '-${digits.substring(7)}';
  }
  return value;
}

/// Linha de apoio do resultado: documento e telefone formatados.
String customerSearchSubtitle(Customer customer) {
  final parts = [
    if (customer.document != null)
      customer.type.usesCpf
          ? formatCpf(customer.document!)
          : formatCnpj(customer.document!),
    if (customer.phone != null) formatPhone(customer.phone!),
  ];
  return parts.isEmpty ? customer.type.label : parts.join(' | ');
}

/// Casa por nome/nome fantasia/e-mail (texto) ou por documento/telefone
/// (dígitos) — digitar "119" acha o telefone sem precisar da máscara.
bool customerMatchesQuery(Customer customer, String rawQuery) {
  final query = normalizeSearchText(rawQuery);
  final digits = digitsOnly(rawQuery);
  if (query.isEmpty && digits.isEmpty) return true;

  final haystack = normalizeSearchText(
    [customer.name, customer.tradeName, customer.email]
        .whereType<String>()
        .join(' '),
  );
  final numericHaystack = digitsOnly(
    [customer.document, customer.phone].whereType<String>().join(' '),
  );

  return haystack.contains(query) ||
      (digits.isNotEmpty && numericHaystack.contains(digits));
}
