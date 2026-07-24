import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../routing/field_route.dart';
import 'neomorphic.dart';

class RouteActions extends StatelessWidget {
  const RouteActions({
    super.key,
    required this.destination,
    this.compact = false,
  });

  final RouteDestination destination;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = destination.hasAddress;
    return OutlinedButton.icon(
      onPressed: enabled ? () => _showRouteSheet(context) : null,
      icon: const Icon(Icons.navigation_outlined),
      label: Text(compact ? 'Rota' : 'Abrir rota'),
    );
  }

  Future<void> _showRouteSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              destination.label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            NeomorphicInset(
              borderRadius: 18,
              child: Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(destination.address ?? 'Endereço indisponível'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MapButton(
                  icon: Icons.map_outlined,
                  label: 'Google Maps',
                  uri: _googleMapsUri(destination),
                ),
                _MapButton(
                  icon: Icons.assistant_direction_outlined,
                  label: 'Waze',
                  uri: _wazeUri(destination),
                ),
                _MapButton(
                  icon: Icons.explore_outlined,
                  label: 'Apple Maps',
                  uri: _appleMapsUri(destination),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: destination.address ?? ''),
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copiar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.label,
    required this.uri,
  });

  final IconData icon;
  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

Uri _googleMapsUri(RouteDestination destination) => Uri.https(
      'www.google.com',
      '/maps/dir/',
      {'api': '1', 'destination': destination.query},
    );

Uri _wazeUri(RouteDestination destination) => Uri.https(
      'waze.com',
      '/ul',
      {'q': destination.query, 'navigate': 'yes'},
    );

Uri _appleMapsUri(RouteDestination destination) => Uri.https(
      'maps.apple.com',
      '/',
      {'daddr': destination.query},
    );
