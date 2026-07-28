import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/config/env_config.dart';

void main() {
  // Sem --dart-define e rodando fora do navegador, Uri.base e um caminho de
  // arquivo. O link precisa cair no dominio de publicacao — nunca em
  // localhost nem em file://, que o cliente nao consegue abrir.
  test('link publico nao usa localhost nem file://', () {
    final url = EnvConfig.publicUrl('/orcamento-publico/abc123');

    expect(url.startsWith('https://'), isTrue, reason: url);
    expect(url.contains('localhost'), isFalse, reason: url);
    expect(url.contains('file:'), isFalse, reason: url);
    expect(url.endsWith('/#/orcamento-publico/abc123'), isTrue, reason: url);
  });
}
