import 'dart:convert';

import 'package:http/http.dart' as http;

class AddressCoordinates {
  const AddressCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class AddressGeocoder {
  const AddressGeocoder({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<AddressCoordinates> locate({
    required String street,
    required String number,
    required String district,
    required String city,
    required String state,
    required String cep,
  }) async {
    final parts = [
      street.trim(),
      number.trim(),
      district.trim(),
      city.trim(),
      state.trim(),
      cep.replaceAll(RegExp(r'\D'), ''),
      'Brasil',
    ].where((part) => part.isNotEmpty).join(', ');

    if (parts.trim().isEmpty) {
      throw const AddressGeocoderException(
        'Preencha o endereço antes de localizar no mapa.',
      );
    }

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'limit': '1',
      'countrycodes': 'br',
      'addressdetails': '0',
      'q': parts,
    });

    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        uri,
        headers: const {
          'User-Agent': 'ServiceFlow/0.2.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AddressGeocoderException(
          'Não foi possível localizar este endereço agora.',
        );
      }

      final body = jsonDecode(response.body);
      if (body is! List || body.isEmpty) {
        throw const AddressGeocoderException(
          'Endereço não encontrado no mapa. Confira os campos e tente novamente.',
        );
      }

      final item = body.first as Map<String, dynamic>;
      final latitude = double.tryParse(item['lat'] as String? ?? '');
      final longitude = double.tryParse(item['lon'] as String? ?? '');
      if (latitude == null || longitude == null) {
        throw const AddressGeocoderException(
          'O mapa não retornou coordenadas válidas para este endereço.',
        );
      }

      return AddressCoordinates(latitude: latitude, longitude: longitude);
    } on AddressGeocoderException {
      rethrow;
    } catch (_) {
      throw const AddressGeocoderException(
        'Não foi possível localizar este endereço agora.',
      );
    } finally {
      if (_client == null) client.close();
    }
  }
}

class AddressGeocoderException implements Exception {
  const AddressGeocoderException(this.message);

  final String message;
}
