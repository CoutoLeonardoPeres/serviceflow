import 'package:flutter/services.dart';

/// Máscaras de entrada para os documentos e contatos que o Brasil usa.
///
/// Todas trabalham só com dígitos por dentro: o que vai para o banco continua
/// sendo o número limpo, e a máscara existe apenas na digitação. Guardar a
/// pontuação quebraria busca e comparação — "11.222.333/0001-44" e
/// "11222333000144" seriam documentos diferentes.
String onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

/// CPF (11 dígitos) ou CNPJ (14). Alterna sozinho conforme a pessoa digita:
/// exigir a escolha antes seria uma pergunta que o próprio número responde.
String maskDocument(String value) {
  final d = onlyDigits(value);
  if (d.length <= 11) return maskCpf(d);
  return maskCnpj(d);
}

String maskCpf(String value) {
  final d = onlyDigits(value);
  if (d.length <= 3) return d;
  if (d.length <= 6) return '${d.substring(0, 3)}.${d.substring(3)}';
  if (d.length <= 9) {
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6)}';
  }
  final cut = d.length > 11 ? 11 : d.length;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}'
      '-${d.substring(9, cut)}';
}

String maskCnpj(String value) {
  final d = onlyDigits(value);
  if (d.length <= 2) return d;
  if (d.length <= 5) return '${d.substring(0, 2)}.${d.substring(2)}';
  if (d.length <= 8) {
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5)}';
  }
  if (d.length <= 12) {
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}'
        '/${d.substring(8)}';
  }
  final cut = d.length > 14 ? 14 : d.length;
  return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}'
      '/${d.substring(8, 12)}-${d.substring(12, cut)}';
}

/// Telefone fixo (10 dígitos) ou celular (11). O nono dígito entrou em 2016 e
/// os dois formatos convivem — a máscara não pode assumir só um.
String maskPhone(String value) {
  final d = onlyDigits(value);
  if (d.isEmpty) return '';
  if (d.length <= 2) return '($d';
  if (d.length <= 6) return '(${d.substring(0, 2)}) ${d.substring(2)}';
  if (d.length <= 10) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  }
  final cut = d.length > 11 ? 11 : d.length;
  return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7, cut)}';
}

String maskCep(String value) {
  final d = onlyDigits(value);
  if (d.length <= 5) return d;
  final cut = d.length > 8 ? 8 : d.length;
  return '${d.substring(0, 5)}-${d.substring(5, cut)}';
}

/// Inscrição estadual não tem formato nacional: cada estado tem o seu, com
/// 8 a 14 dígitos e pontuação diferente. Formatar por conta própria daria
/// número errado em metade dos estados — então aqui só limitamos aos dígitos
/// e ao tamanho máximo, sem inventar separador.
String maskStateRegistration(String value) {
  final d = onlyDigits(value);
  return d.length > 14 ? d.substring(0, 14) : d;
}

/// Aplica uma função de máscara enquanto a pessoa digita, mantendo o cursor
/// no fim. Cursor no meio de campo mascarado é problema conhecido e sem
/// solução boa; por isso os campos com máscara são curtos e de digitação
/// contínua.
class MaskTextInputFormatter extends TextInputFormatter {
  const MaskTextInputFormatter(this.mask);

  final String Function(String) mask;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = mask(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

const documentFormatter = MaskTextInputFormatter(maskDocument);
const phoneFormatter = MaskTextInputFormatter(maskPhone);
const cepFormatter = MaskTextInputFormatter(maskCep);
const stateRegistrationFormatter =
    MaskTextInputFormatter(maskStateRegistration);
