import 'dart:convert';

import 'package:http/http.dart' as http;

/// Endereço devolvido pela consulta de CEP.
///
/// Campos podem vir vazios: CEP de logradouro único (o "CEP geral" de cidade
/// pequena) não tem rua nem bairro, e isso não é erro — é o correio.
class CepAddress {
  const CepAddress({
    required this.cep,
    this.street = '',
    this.district = '',
    this.city = '',
    this.state = '',
  });

  final String cep;
  final String street;
  final String district;
  final String city;
  final String state;
}

class CepLookupException implements Exception {
  const CepLookupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Consulta o CEP no ViaCEP.
///
/// Vivia embutida na tela de cliente. Foi extraída aqui quando o cadastro de
/// fornecedor passou a precisar do mesmo comportamento — duplicar significaria
/// duas telas divergindo no tratamento de erro e no formato aceito.
Future<CepAddress> lookupCep(String rawCep, {http.Client? client}) async {
  final cep = rawCep.replaceAll(RegExp(r'\D'), '');
  if (cep.length != 8) {
    throw const CepLookupException('CEP precisa ter 8 dígitos.');
  }

  final owned = client == null;
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CepLookupException(
        'Não foi possível consultar o CEP agora.',
      );
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const CepLookupException(
        'Não foi possível consultar o CEP agora.',
      );
    }
    // O ViaCEP responde 200 com {"erro": true} para CEP inexistente — checar
    // só o status HTTP daria o endereço como encontrado.
    if (data['erro'] == true || data['erro'] == 'true') {
      throw const CepLookupException(
        'CEP não encontrado. Preencha o endereço manualmente.',
      );
    }

    return CepAddress(
      cep: cep,
      street: (data['logradouro'] as String?)?.trim() ?? '',
      district: (data['bairro'] as String?)?.trim() ?? '',
      city: (data['localidade'] as String?)?.trim() ?? '',
      state: (data['uf'] as String?)?.trim() ?? '',
    );
  } on CepLookupException {
    rethrow;
  } catch (_) {
    throw const CepLookupException('Não foi possível consultar o CEP agora.');
  } finally {
    if (owned) httpClient.close();
  }
}
