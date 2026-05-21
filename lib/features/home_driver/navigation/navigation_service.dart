import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class NavigationService {
  /// Précision maximale acceptée en mètres.
  /// Les positions avec accuracy > 50m (réseau/WiFi) sont ignorées.
  static const maxAccuracyMeters = 50.0;

  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 5, // mise à jour toutes les 5 m
  );

  /// Demande la permission et retourne la première position précise (≤ 50 m).
  /// Attend jusqu'à 8s pour un fix GPS propre, sinon fallback sur ce qui est disponible.
  /// Retourne null si l'accès est refusé.
  static Future<Position?> requestAndGetPosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      return await Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      )
          .where((p) => p.accuracy <= maxAccuracyMeters)
          .first
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Timeout ou pas de GPS (intérieur) : prendre la meilleure position disponible
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
    }
  }

  /// Stream de positions GPS en temps réel.
  static Stream<Position> get positionStream =>
      Geolocator.getPositionStream(locationSettings: _settings);

  /// Distance en mètres entre une position GPS et une cible.
  static double distanceTo(Position from, LatLng to) =>
      Geolocator.distanceBetween(
        from.latitude, from.longitude, to.latitude, to.longitude);

  /// Azimut (cap) entre une position GPS et une cible (0–360°).
  static double bearingTo(Position from, LatLng to) =>
      Geolocator.bearingBetween(
        from.latitude, from.longitude, to.latitude, to.longitude);

  /// Formate une distance en m/km pour l'affichage.
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  /// Formate une durée en secondes pour l'affichage.
  static String formatDuration(int seconds) {
    if (seconds < 60) return 'moins d\'1 min';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}min';
  }
}
