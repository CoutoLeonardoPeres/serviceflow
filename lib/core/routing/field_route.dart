import 'dart:math';

class RouteDestination {
  const RouteDestination({
    required this.label,
    required this.address,
    this.latitude,
    this.longitude,
    this.priorityLevel,
    this.scheduledAt,
  });

  final String label;
  final String? address;
  final double? latitude;
  final double? longitude;
  final int? priorityLevel;
  final DateTime? scheduledAt;

  bool get hasAddress => address != null && address!.trim().isNotEmpty;
  bool get hasCoordinates => latitude != null && longitude != null;

  String get query {
    if (hasCoordinates) return '$latitude,$longitude';
    return address?.trim() ?? label;
  }
}

class RouteStop<T> {
  const RouteStop({
    required this.item,
    required this.destination,
    required this.position,
    this.distanceFromPreviousKm,
  });

  final T item;
  final RouteDestination destination;
  final int position;
  final double? distanceFromPreviousKm;
}

List<RouteStop<T>> suggestFieldRoute<T>(
  List<T> items,
  RouteDestination Function(T item) destinationFor,
) {
  final pending = items
      .map((item) => (item: item, destination: destinationFor(item)))
      .where((entry) => entry.destination.hasAddress)
      .toList();
  final stops = <RouteStop<T>>[];
  RouteDestination? previous;

  while (pending.isNotEmpty) {
    pending.sort((a, b) {
      final scoreComparison = _routeScore(a.destination, previous).compareTo(
        _routeScore(b.destination, previous),
      );
      if (scoreComparison != 0) return scoreComparison;
      final aDate = a.destination.scheduledAt;
      final bDate = b.destination.scheduledAt;
      if (aDate != null && bDate != null) return aDate.compareTo(bDate);
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return a.destination.label.compareTo(b.destination.label);
    });
    final selected = pending.removeAt(0);
    final distance =
        previous == null ? null : distanceKm(previous, selected.destination);
    stops.add(
      RouteStop(
        item: selected.item,
        destination: selected.destination,
        position: stops.length + 1,
        distanceFromPreviousKm: distance,
      ),
    );
    previous = selected.destination;
  }

  return stops;
}

double _routeScore(RouteDestination destination, RouteDestination? previous) {
  final priorityScore = 6 - (destination.priorityLevel ?? 3).clamp(1, 5);
  final scheduleScore = destination.scheduledAt == null
      ? 8.0
      : destination.scheduledAt!
              .difference(DateTime.now())
              .inMinutes
              .clamp(-240, 1440) /
          240;
  final distanceScore =
      previous == null ? 0.0 : distanceKm(previous, destination) ?? 4.0;
  return priorityScore * 3 + scheduleScore + distanceScore;
}

double? distanceKm(RouteDestination from, RouteDestination to) {
  if (!from.hasCoordinates || !to.hasCoordinates) return null;
  const earthRadiusKm = 6371.0;
  final dLat = _radians(to.latitude! - from.latitude!);
  final dLon = _radians(to.longitude! - from.longitude!);
  final lat1 = _radians(from.latitude!);
  final lat2 = _radians(to.latitude!);
  final a =
      pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
  return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _radians(double degrees) => degrees * pi / 180;
