import 'package:flutter/material.dart';

class AddressLocationBox extends StatelessWidget {
  const AddressLocationBox({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.isLoading,
    required this.onLocate,
  });

  final double? latitude;
  final double? longitude;
  final bool isLoading;
  final VoidCallback? onLocate;

  bool get _hasCoordinates => latitude != null && longitude != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(12, 14),
          ),
          BoxShadow(
            color: Color(0xCCFFFFFF),
            blurRadius: 18,
            offset: Offset(-10, -10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 16,
                  offset: Offset(7, 8),
                ),
                BoxShadow(
                  color: Color(0xE6FFFFFF),
                  blurRadius: 12,
                  offset: Offset(-7, -7),
                ),
              ],
            ),
            child: Icon(
              _hasCoordinates
                  ? Icons.location_on_outlined
                  : Icons.add_location_alt_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasCoordinates
                      ? 'Coordenadas salvas'
                      : 'Localização para rotas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _hasCoordinates
                      ? '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
                      : 'Use depois de preencher o endereço completo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onLocate,
            icon: isLoading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_outlined),
            label: Text(_hasCoordinates ? 'Atualizar' : 'Localizar'),
          ),
        ],
      ),
    );
  }
}
