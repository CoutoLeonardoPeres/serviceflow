import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/utils/validators.dart';

void main() {
  group('validateEmail', () {
    test('aceita e-mail válido', () {
      expect(validateEmail('usuario@empresa.com.br'), isNull);
      expect(validateEmail('test+tag@sub.domain.io'), isNull);
    });
    test('rejeita e-mail inválido', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail(null), isNotNull);
      expect(validateEmail('nao-tem-arroba'), isNotNull);
      expect(validateEmail('@semlocal.com'), isNotNull);
    });
  });

  group('validatePassword', () {
    test('aceita senha com 8+ caracteres', () {
      expect(validatePassword('senha123'), isNull);
      expect(validatePassword('MinhaSenh@Forte!'), isNull);
    });
    test('rejeita senha curta', () {
      expect(validatePassword('abc'), isNotNull);
      expect(validatePassword(''), isNotNull);
      expect(validatePassword(null), isNotNull);
    });
  });

  group('validateCpf', () {
    test('aceita CPF válido', () {
      expect(validateCpf('529.982.247-25'), isNull); // CPF de teste válido
    });
    test('rejeita CPF inválido', () {
      expect(validateCpf('111.111.111-11'), isNotNull); // todos iguais
      expect(validateCpf('000.000.000-00'), isNotNull);
      expect(validateCpf('123.456.789-00'), isNotNull);
      expect(validateCpf(''), isNotNull);
    });
  });

  group('validateCnpj', () {
    test('aceita CNPJ válido', () {
      expect(
          validateCnpj('11.222.333/0001-81'), isNull); // CNPJ de teste válido
    });
    test('rejeita CNPJ inválido', () {
      expect(validateCnpj('00.000.000/0000-00'), isNotNull);
      expect(validateCnpj('11.111.111/1111-11'), isNotNull);
      expect(validateCnpj(''), isNotNull);
    });
  });

  group('validateSlug', () {
    test('aceita slugs válidos', () {
      expect(validateSlug('empresa-alpha'), isNull);
      expect(validateSlug('abc123'), isNull);
      expect(validateSlug('minha-empresa-ltda'), isNull);
    });
    test('rejeita slugs inválidos', () {
      expect(validateSlug(''), isNotNull);
      expect(validateSlug('a'), isNotNull); // muito curto
      expect(validateSlug('AB'), isNotNull); // maiúsculas
      expect(validateSlug('empresa_alpha'), isNotNull); // underscore
      expect(validateSlug('-começa-com-hífen'), isNotNull);
    });
  });

  group('validateCep', () {
    test('aceita CEP válido', () {
      expect(validateCep('01310-100'), isNull);
      expect(validateCep('01310100'), isNull);
    });
    test('rejeita CEP inválido', () {
      expect(validateCep(''), isNotNull);
      expect(validateCep('1234'), isNotNull);
    });
  });

  group('validatePhone', () {
    test('aceita telefones válidos', () {
      expect(validatePhone('(11) 98765-4321'), isNull);
      expect(validatePhone('1198765432'), isNull); // 10 dígitos (fixo)
      expect(validatePhone(null), isNull); // opcional
      expect(validatePhone(''), isNull); // opcional
    });
    test('rejeita telefone com dígitos insuficientes', () {
      expect(validatePhone('123'), isNotNull);
    });
  });
}
