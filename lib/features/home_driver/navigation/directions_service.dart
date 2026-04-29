import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteResult {
  final List<LatLng> points;
  final int? durationSeconds;   // durée estimée
  final double? distanceMeters; // distance totale

  const RouteResult({
    required this.points,
    this.durationSeconds,
    this.distanceMeters,
  });

  /// Résultat de secours : ligne droite entre deux points.
  factory RouteResult.fallback(LatLng origin, LatLng destination) =>
      RouteResult(points: [origin, destination]);
}

class DirectionsService {
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Récupère la vraie route routière.
  /// Stratégie : Google Directions → OSRM (libre) → ligne droite.
  static Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    required String apiKey,
  }) async {
    // ── 1. Google Directions API ──────────────────────────────────────────────
    if (apiKey.isNotEmpty) {
      try {
        final response = await _dio.get(
          'https://maps.googleapis.com/maps/api/directions/json',
          queryParameters: {
            'origin':      '${origin.latitude},${origin.longitude}',
            'destination': '${destination.latitude},${destination.longitude}',
            'key':         apiKey,
            'mode':        'driving',
            'alternatives':'false',
          },
        );

        final data = response.data as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final route = (data['routes'] as List).first as Map<String, dynamic>;
          final leg   = (route['legs']   as List).first as Map<String, dynamic>;

          // Step-level polylines : suit les courbes réelles des rues
          final steps  = leg['steps'] as List;
          final points = <LatLng>[];
          for (final step in steps) {
            points.addAll(_decodePolyline(
              (step as Map<String, dynamic>)['polyline']['points'] as String,
            ));
          }

          return RouteResult(
            points:          points,
            durationSeconds: (leg['duration']['value'] as num).toInt(),
            distanceMeters:  (leg['distance']['value']  as num).toDouble(),
          );
        }
      } catch (_) {
        // Google a échoué → on essaie OSRM
      }
    }

    // ── 2. OSRM (routeur libre, sans clé) ────────────────────────────────────
    try {
      final osrm = Dio(BaseOptions(
        headers: {'User-Agent': 'com.dem.app/1.0'},
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final res = await osrm.get(
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );
      if (res.statusCode == 200 &&
          (res.data['routes'] as List?)?.isNotEmpty == true) {
        final r      = res.data['routes'][0] as Map<String, dynamic>;
        final coords = r['geometry']['coordinates'] as List;
        return RouteResult(
          points: coords
              .map((c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ))
              .toList(),
          durationSeconds: (r['duration'] as num?)?.toInt(),
          distanceMeters:  (r['distance']  as num?)?.toDouble(),
        );
      }
    } catch (_) {
      // OSRM a échoué → ligne droite
    }

    // ── 3. Dernier recours : ligne droite ─────────────────────────────────────
    return RouteResult.fallback(origin, destination);
  }

  /// Décodage de la polyline encodée Google (algorithme officiel).
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0, lng = 0;

    while (index < encoded.length) {
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
