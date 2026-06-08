import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class NavigationService {
  /// Précision maximale acceptée en mètres.
  /// Les positions avec accuracy > 50m (réseau/WiFi) sont ignorées.
  static const maxAccuracyMeters = 50.0;

  /// Paramètres GPS adaptés à chaque OS.
  ///
  /// Android — `AndroidSettings` avec `foregroundNotificationConfig` :
  ///   démarre un vrai foreground service visible dans la barre de statut,
  ///   ce qui empêche Android de tuer le processus quand l'app passe en arrière-plan.
  ///   Nécessite FOREGROUND_SERVICE + FOREGROUND_SERVICE_LOCATION (déjà dans le manifest)
  ///   et `GeolocatorService` avec `foregroundServiceType="location"` (déjà déclaré).
  ///
  /// iOS — `AppleSettings` avec `pauseLocationUpdatesAutomatically: false` :
  ///   désactive la suspension automatique du stream GPS par CoreLocation.
  ///   Nécessite UIBackgroundModes: location + NSLocationAlwaysUsageDescription (déjà en place).
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
        // Indicateur bleu en haut de l'écran — obligatoire sur iOS pour la localisation en fond
        showBackgroundLocationIndicator: true,
      );
    }
    // Fallback desktop / autre
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  /// Retourne la position actuelle sans jamais afficher de dialog de permission.
  /// La permission doit être demandée en amont via LocationDisclosureScreen.
  /// Fallback sur Dakar si GPS indisponible (simulateur, permission refusée).
  static Future<Position> requestAndGetPosition() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return _dakarFallback();
    }

    // Première position du stream sans filtre d'accuracy.
    // On n'utilise PAS getLastKnownPosition() : il retourne un cache potentiellement
    // vieux de plusieurs heures et affiche une position incorrecte au démarrage.
    // Sans le filtre accuracy, le stream fournit une vraie position en 1-3 s.
    try {
      return await Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).first.timeout(const Duration(seconds: 12));
    } catch (_) {}

    // Fallback : position réseau/WiFi (rapide, moins précise)
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}

    return _dakarFallback();
  }

  static Position _dakarFallback() => Position(
    latitude: 14.6937,
    longitude: -17.4441,
    timestamp: DateTime.now(),
    accuracy: 999,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    isMocked: kDebugMode,
  );

  /// Stream de positions GPS en temps réel.
  /// Ne démarre que si la permission est accordée — évite le flood sur simulateur.
  static Stream<Position> get positionStream async* {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
      yield* Geolocator.getPositionStream(locationSettings: _settings);
    }
  }

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
