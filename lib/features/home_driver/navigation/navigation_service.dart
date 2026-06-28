import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NavigationService {
  static const _kCachedLat = 'dem_gps_lat';
  static const _kCachedLng = 'dem_gps_lng';
  static const _kCachedTs  = 'dem_gps_ts';

  // ── Paramètres GPS continu ─────────────────────────────────────────────────

  static LocationSettings get _settings {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        forceLocationManager: false,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationChannelName: 'Course en cours',
          notificationTitle: 'DEM · Course en cours',
          notificationText: 'Votre position est partagée en temps réel.',
          enableWakeLock: true,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  // ── Cache app (toujours positions GPS, jamais réseau/cellulaire) ────────────

  /// Dernière bonne position GPS sauvegardée par l'app (< 30 min).
  /// Utilisée pour centrer la carte instantanément au démarrage.
  static Future<Position?> getCachedPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final lat  = prefs.getDouble(_kCachedLat);
    final lng  = prefs.getDouble(_kCachedLng);
    final tsMs = prefs.getInt(_kCachedTs);
    if (lat == null || lng == null || tsMs == null) return null;
    final ageMs = DateTime.now().millisecondsSinceEpoch - tsMs;
    if (ageMs > 30 * 60 * 1000) return null; // > 30 minutes = trop vieux
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
      accuracy: 30,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  /// Sauvegarde une position GPS précise pour le prochain démarrage.
  /// Ignore les positions imprécises (réseau, cellulaire).
  static Future<void> savePosition(Position p) async {
    if (p.accuracy > 80) return; // position réseau — pas fiable
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kCachedLat, p.latitude);
    await prefs.setDouble(_kCachedLng, p.longitude);
    await prefs.setInt(_kCachedTs, DateTime.now().millisecondsSinceEpoch);
  }

  // ── Position initiale ──────────────────────────────────────────────────────

  /// Retourne la position GPS fraîche sans jamais lire le cache OS.
  ///
  /// Sur iOS : getCurrentPosition() → requestLocation() → JAMAIS de cache.
  /// Sur Android : FusedLocationProviderClient déclenche une nouvelle requête.
  ///
  /// Demande la permission si elle n'a pas encore été accordée.
  /// À appeler UNE FOIS au démarrage. Pour les mises à jour continues, utiliser positionStream.
  static Future<Position?> requestAndGetPosition() async {
    var permission = await Geolocator.checkPermission();

    // Permission pas encore demandée → la demander maintenant.
    // Le disclosure screen a déjà expliqué le contexte à l'utilisateur.
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).timeout(const Duration(seconds: 20));
    } catch (_) {}

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}

    return null;
  }

  static Future<bool> isLocationEnabled() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }
    return Geolocator.isLocationServiceEnabled();
  }

  static Future<bool> requestLocationWithPrompt() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }
    return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
  }

  // ── Stream continu ─────────────────────────────────────────────────────────

  /// Stream de positions GPS en temps réel.
  /// Le filtre timestamp exclut la première émission du cache iOS.
  static Stream<Position> get positionStream async* {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
      yield* Geolocator.getPositionStream(locationSettings: _settings)
          .where((p) => DateTime.now().difference(p.timestamp).inSeconds < 60);
    }
  }

  // ── Calculs géographiques ──────────────────────────────────────────────────

  static double distanceTo(Position from, LatLng to) =>
      Geolocator.distanceBetween(
          from.latitude, from.longitude, to.latitude, to.longitude);

  static double bearingTo(Position from, LatLng to) =>
      Geolocator.bearingBetween(
          from.latitude, from.longitude, to.latitude, to.longitude);

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String formatDuration(int seconds) {
    if (seconds < 60) return 'moins d\'1 min';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}min';
  }
}
