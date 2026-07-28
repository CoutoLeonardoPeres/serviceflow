import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/utils/input_masks.dart';

/// Guarda as máscaras de documento, telefone e CEP.
///
/// Elas existem só na digitação: o que vai ao banco é o número limpo. Guardar
/// a pontuação faria "11.222.333/0001-44" e "11222333000144" serem documentos
/// diferentes na busca e no UNIQUE por empresa.
void main() {
  group('documento', () {
    test('formata CPF conforme digita', () {
      expect(maskDocument('123'), '123');
      expect(maskDocument('123456'), '123.456');
      expect(maskDocument('123456789'), '123.456.789');
      expect(maskDocument('12345678901'), '123.456.789-01');
    });

    test('vira CNPJ ao passar de 11 dígitos, sem pedir escolha antes', () {
      expect(maskDocument('112223330001'), '11.222.333/0001');
      expect(maskDocument('11222333000144'), '11.222.333/0001-44');
    });

    test('descarta dígito além do tamanho do documento', () {
      expect(maskDocument('11222333000144999'), '11.222.333/0001-44');
    });

    test('ignora pontuação já digitada em vez de duplicá-la', () {
      expect(maskDocument('123.456.789-01'), '123.456.789-01');
      expect(maskDocument('11.222.333/0001-44'), '11.222.333/0001-44');
    });
  });

  group('telefone', () {
    test('fixo com 10 dígitos', () {
      expect(maskPhone('1133334444'), '(11) 3333-4444');
    });

    test('celular com 11 dígitos — o nono entrou em 2016 e convive', () {
      expect(maskPhone('11988887777'), '(11) 98888-7777');
    });

    test('formata parcialmente durante a digitação', () {
      expect(maskPhone('1'), '(1');
      expect(maskPhone('11'), '(11');
      expect(maskPhone('119'), '(11) 9');
      expect(maskPhone('119888'), '(11) 9888');
    });

    test('corta o excesso em 11 dígitos', () {
      expect(maskPhone('119888877779999'), '(11) 98888-7777');
    });
  });

  group('CEP', () {
    test('formata em 5+3', () {
      expect(maskCep('01310100'), '01310-100');
      expect(maskCep('013'), '013');
      expect(maskCep('01310'), '01310');
    });

    test('corta além de 8 dígitos', () {
      expect(maskCep('013101009999'), '01310-100');
    });
  });

  group('inscrição estadual', () {
    test('não inventa separador — cada estado tem o seu formato', () {
      // Formatar por conta própria daria número errado em metade dos estados.
      expect(maskStateRegistration('123456789'), '123456789');
      expect(maskStateRegistration('12.345.678-9'), '123456789');
    });

    test('limita a 14 dígitos', () {
      expect(maskStateRegistration('123456789012345678'), '12345678901234');
    });
  });

  group('onlyDigits', () {
    test('é o que vai para o banco', () {
      expect(onlyDigits('(11) 98888-7777'), '11988887777');
      expect(onlyDigits('11.222.333/0001-44'), '11222333000144');
      expect(onlyDigits('01310-100'), '01310100');
      expect(onlyDigits(''), '');
    });
  });
}
