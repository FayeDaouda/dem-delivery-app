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

  /// Récupère la vraie route routière via l'API Directions de Google.
  /// Si la clé est absente ou invalide, retourne une ligne droite.
  static Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    required String apiKey,
  }) async {
    if (apiKey.isEmpty) return RouteResult.fallback(origin, destination);

    try {
      final response = await _dio.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'key': apiKey,
          'mode': 'driving',
          'alternatives': 'false',
        },
      );

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        return RouteResult.fallback(origin, destination);
      }

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final leg = (route['legs'] as List).first as Map<String, dynamic>;

      final points = _decodePolyline(
        route['overview_polyline']['points'] as String,
      );
      final durationSec = (leg['duration']['value'] as num).toInt();
      final distanceM = (leg['distance']['value'] as num).toDouble();

      return RouteResult(
        points: points,
        durationSeconds: durationSec,
        distanceMeters: distanceM,
      );
    } catch (_) {
      return RouteResult.fallback(origin, destination);
    }
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
