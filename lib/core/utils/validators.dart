/// Validadores brasileiros para formulários.
/// Todos retornam null se válido, ou mensagem de erro se inválido.
library validators;

// ── CPF ─────────────────────────────────────────────────────────────────────
String? validateCpf(String? value) {
  if (value == null || value.isEmpty) return 'Informe o CPF.';
  final digits = value.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length != 11) return 'CPF deve ter 11 dígitos.';
  if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return 'CPF inválido.';

  int sum = 0;
  for (int i = 0; i < 9; i++) {
    sum += int.parse(digits[i]) * (10 - i);
  }
  int remainder = (sum * 10) % 11;
  if (remainder == 10 || remainder == 11) remainder = 0;
  if (remainder != int.parse(digits[9])) return 'CPF inválido.';

  sum = 0;
  for (int i = 0; i < 10; i++) {
    sum += int.parse(digits[i]) * (11 - i);
  }
  remainder = (sum * 10) % 11;
  if (remainder == 10 || remainder == 11) remainder = 0;
  if (remainder != int.parse(digits[10])) return 'CPF inválido.';

  return null;
}

// ── CNPJ ────────────────────────────────────────────────────────────────────
String? validateCnpj(String? value) {
  if (value == null || value.isEmpty) return 'Informe o CNPJ.';
  final digits = value.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length != 14) return 'CNPJ deve ter 14 dígitos.';
  if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return 'CNPJ inválido.';

  const weights1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  const weights2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

  int _calc(List<int> weights) {
    int sum = 0;
    for (int i = 0; i < weights.length; i++) {
      sum += int.parse(digits[i]) * weights[i];
    }
    final r = sum % 11;
    return r < 2 ? 0 : 11 - r;
  }

  if (_calc(weights1) != int.parse(digits[12])) return 'CNPJ inválido.';
  if (_calc(weights2) != int.parse(digits[13])) return 'CNPJ inválido.';

  return null;
}

// ── E-mail ───────────────────────────────────────────────────────────────────
String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Informe o e-mail.';
  final re = RegExp(r'^[\w\.\+\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
  if (!re.hasMatch(value.trim())) return 'E-mail inválido.';
  return null;
}

// ── Telefone (BR) ────────────────────────────────────────────────────────────
String? validatePhone(String? value) {
  if (value == null || value.isEmpty) return null; // opcional por padrão
  final digits = value.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length < 10 || digits.length > 11) {
    return 'Telefone inválido. Ex: (11) 98765-4321';
  }
  return null;
}

// ── CEP ──────────────────────────────────────────────────────────────────────
String? validateCep(String? value) {
  if (value == null || value.isEmpty) return 'Informe o CEP.';
  final digits = value.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length != 8) return 'CEP deve ter 8 dígitos.';
  return null;
}

// ── Campo obrigatório genérico ────────────────────────────────────────────────
String? validateRequired(String? value, [String label = 'Este campo']) {
  if (value == null || value.trim().isEmpty) return '$label é obrigatório.';
  return null;
}

// ── Senha ────────────────────────────────────────────────────────────────────
String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Informe a senha.';
  if (value.length < 8) return 'A senha deve ter pelo menos 8 caracteres.';
  return null;
}

// ── Slug de tenant ───────────────────────────────────────────────────────────
String? validateSlug(String? value) {
  if (value == null || value.trim().isEmpty) return 'Informe o identificador.';
  final re = RegExp(r'^[a-z0-9][a-z0-9\-]{1,62}[a-z0-9]$');
  if (!re.hasMatch(value.trim())) {
    return 'Use apenas letras minúsculas, números e hífens (mín. 3 caracteres).';
  }
  return null;
}
