import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/routing/field_route.dart';

void main() {
  test('suggestFieldRoute prioriza criticidade, horario e distancia', () {
    final now = DateTime.now();
    final items = [
      RouteDestination(
        label: 'Baixa prioridade distante',
        address: 'Rua B',
        latitude: -23.60,
        longitude: -46.70,
        priorityLevel: 1,
        scheduledAt: now.add(const Duration(hours: 6)),
      ),
      RouteDestination(
        label: 'Critico agora',
        address: 'Rua A',
        latitude: -23.55,
        longitude: -46.63,
        priorityLevel: 5,
        scheduledAt: now.add(const Duration(minutes: 20)),
      ),
      RouteDestination(
        label: 'Medio perto',
        address: 'Rua C',
        latitude: -23.551,
        longitude: -46.631,
        priorityLevel: 3,
        scheduledAt: now.add(const Duration(hours: 2)),
      ),
    ];

    final route = suggestFieldRoute(items, (item) => item);

    expect(route.first.destination.label, 'Critico agora');
    expect(route[1].destination.label, 'Medio perto');
    expect(route[1].distanceFromPreviousKm, isNotNull);
  });
}
