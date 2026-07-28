import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:serviceflow/core/location/cep_lookup.dart';

/// Guarda a consulta de CEP, usada pelo cadastro de cliente e pelo de
/// fornecedor. O caso que mais morde é o ViaCEP responder **200** com
/// `{"erro": true}` para CEP inexistente — olhar só o status daria o endereço
/// como encontrado.
void main() {
  group('lookupCep', () {
    test('aceita CEP com máscara', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('01310100'));
        return http.Response(
          jsonEncode({
            'logradouro': 'Avenida Paulista',
            'bairro': 'Bela Vista',
            'localidade': 'São Paulo',
            'uf': 'SP',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final address = await lookupCep('01310-100', client: client);
      expect(address.street, 'Avenida Paulista');
      expect(address.district, 'Bela Vista');
      expect(address.city, 'São Paulo');
      expect(address.state, 'SP');
    });

    test('CEP com menos de 8 dígitos nem chega a consultar', () async {
      var chamou = false;
      final client = MockClient((_) async {
        chamou = true;
        return http.Response('{}', 200);
      });

      expect(
        () => lookupCep('0131', client: client),
        throwsA(isA<CepLookupException>()),
      );
      expect(chamou, isFalse);
    });

    test('200 com {"erro": true} é CEP inexistente, não sucesso', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'erro': true}), 200),
      );

      await expectLater(
        lookupCep('99999999', client: client),
        throwsA(
          isA<CepLookupException>().having(
            (e) => e.message,
            'mensagem',
            contains('não encontrado'),
          ),
        ),
      );
    });

    test('CEP geral, sem rua e sem bairro, não é erro', () async {
      // Cidade pequena tem CEP único: vem só localidade e UF.
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'logradouro': '',
            'bairro': '',
            'localidade': 'Bonito',
            'uf': 'MS',
          }),
          200,
        ),
      );

      final address = await lookupCep('79290000', client: client);
      expect(address.street, isEmpty);
      expect(address.city, 'Bonito');
      expect(address.state, 'MS');
    });

    test('falha de rede vira mensagem de usuário, não exceção crua', () async {
      final client = MockClient((_) async => throw const SocketExceptionFake());

      await expectLater(
        lookupCep('01310100', client: client),
        throwsA(isA<CepLookupException>()),
      );
    });

    test('resposta com erro HTTP não é lida como endereço', () async {
      final client = MockClient((_) async => http.Response('', 500));

      await expectLater(
        lookupCep('01310100', client: client),
        throwsA(isA<CepLookupException>()),
      );
    });
  });
}

class SocketExceptionFake implements Exception {
  const SocketExceptionFake();
}
