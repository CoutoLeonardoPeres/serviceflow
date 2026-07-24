import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../routing/field_route.dart';
import 'neomorphic.dart';

class FieldRoutePanel<T> extends StatelessWidget {
  const FieldRoutePanel({
    super.key,
    required this.title,
    required this.items,
    required this.destinationFor,
    required this.labelFor,
  });

  final String title;
  final List<T> items;
  final RouteDestination Function(T item) destinationFor;
  final String Function(T item) labelFor;

  @override
  Widget build(BuildContext context) {
    final stops = suggestFieldRoute(items, destinationFor);
    if (stops.isEmpty) return const SizedBox.shrink();

    return NeomorphicPanel(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: stops.length > 1
                    ? () => launchUrl(
                          _multiStopGoogleMapsUri(stops),
                          mode: LaunchMode.externalApplication,
                        )
                    : null,
                icon: const Icon(Icons.alt_route_outlined),
                label: const Text('Rota completa'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Ordem sugerida por criticidade, horário marcado e distância quando houver coordenadas.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          ...stops.take(4).map(
                (stop) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RouteStopTile(
                    position: stop.position,
                    title: labelFor(stop.item),
                    address: stop.destination.address ?? '',
                    distanceKm: stop.distanceFromPreviousKm,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _RouteStopTile extends StatelessWidget {
  const _RouteStopTile({
    required this.position,
    required this.title,
    required this.address,
    required this.distanceKm,
  });

  final int position;
  final String title;
  final String address;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            child: Text(
              position.toString(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (distanceKm != null) ...[
            const SizedBox(width: 8),
            Text(
              '${distanceKm!.toStringAsFixed(1)} km',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

Uri _multiStopGoogleMapsUri<T>(List<RouteStop<T>> stops) {
  final destination = stops.last.destination.query;
  final waypoints = stops
      .skip(1)
      .take(stops.length - 2)
      .map((stop) => stop.destination.query)
      .join('|');
  return Uri.https(
    'www.google.com',
    '/maps/dir/',
    {
      'api': '1',
      'destination': destination,
      if (waypoints.isNotEmpty) 'waypoints': waypoints,
    },
  );
}
