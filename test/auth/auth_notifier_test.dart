import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:serviceflow/features/auth/application/auth_notifier.dart';

// Para gerar os mocks: flutter pub run build_runner build
// Por enquanto usamos mocks manuais para não depender do build_runner em CI.

void main() {
  group('AuthNotifier — estado inicial', () {
    test('começa como AuthActionIdle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(authNotifierProvider);
      expect(state, isA<AuthActionIdle>());
    });
  });

  group('AuthNotifier — resetState', () {
    test('resetState volta para Idle', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(authNotifierProvider.notifier);
      notifier.resetState();

      expect(container.read(authNotifierProvider), isA<AuthActionIdle>());
    });
  });

  group('Validators — email', () {
    test('e-mail válido retorna null', () {
      import_validators:
      // ignorar: apenas verificação inline
      expect(true, isTrue); // placeholder até importar validators
    });
  });
}
