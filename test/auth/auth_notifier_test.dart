import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:serviceflow/features/auth/application/auth_notifier.dart';

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
}
