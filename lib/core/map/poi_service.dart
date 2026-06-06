import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'poi_data.dart';

class PoiService {
  static const _cacheKey     = 'dem_poi_cache_v2';
  static const _cacheTimeKey = 'dem_poi_cache_time_v2';
  static const _cacheTtlMs   = 24 * 60 * 60 * 1000; // 24h

  static const _center = LatLng(14.6937, -17.4441);
  static const _radius = 15000; // mètres

  // Catégories avec un type Google Places direct
  static const _googleTypes = <PoiCategory, String>{
    PoiCategory.hopital:        'hospital',
    PoiCategory.ecole:          'university',
    PoiCategory.stationBus:     'transit_station',
    PoiCategory.stationEssence: 'gas_station',
  };

  /// Retourne les POIs depuis le cache SharedPreferences (24h) ou l'API Google
  /// Places. Fallback sur les données statiques si tout échoue.
  static Future<List<PoiPoint>> loadPois() async {
    // 1. Cache valide ?
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts    = prefs.getInt(_cacheTimeKey) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts < _cacheTtlMs) {
        final raw = prefs.getString(_cacheKey);
        if (raw != null) {
          final pois = _deserialize(raw);
          if (pois.isNotEmpty) return pois;
        }
      }
    } catch (_) {}

    // 2. Appel API
    try {
      final fetched = await _fetchFromApi();
      if (fetched.isNotEmpty) {
        _saveCache(fetched);   // fire-and-forget
        return fetched;
      }
    } catch (_) {}

    // 3. Fallback statique
    return dakarPois;
  }

  // ── Appels Places API ────────────────────────────────────────────────────────

  static Future<List<PoiPoint>> _fetchFromApi() async {
    final key = AppConfig.mapsApiKey;
    if (key.isEmpty) return [];

    final dio  = Dio();
    final pois = <PoiPoint>[];

    // Types directs (hospital, university, transit_station, gas_station)
    for (final entry in _googleTypes.entries) {
      try {
        final rows = await _nearbySearch(dio, key, type: entry.value);
        pois.addAll(_toPoiPoints(rows, entry.key));
      } catch (_) {}
    }

    // Marchés : keyword "marché" (pas de type Google dédié)
    try {
      final rows = await _nearbySearch(dio, key, keyword: 'marché');
      pois.addAll(_toPoiPoints(rows, PoiCategory.marche));
    } catch (_) {}

    // Quartiers : toujours statiques — Google Places n'a pas de type
    // "neighborhood" pour les villes sénégalaises.
    pois.addAll(dakarPois.where((p) => p.category == PoiCategory.quartier));

    return pois;
  }

  static Future<List<Map<String, dynamic>>> _nearbySearch(
    Dio dio,
    String key, {
    String? type,
    String? keyword,
  }) async {
    final params = <String, dynamic>{
      'location': '${_center.latitude},${_center.longitude}',
      'radius':   '$_radius',
      'language': 'fr',
      'key':      key,
    };
    if (type    != null) params['type']    = type;
    if (keyword != null) params['keyword'] = keyword;

    final resp = await dio.get(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json',
      queryParameters: params,
      options: Options(receiveTimeout: const Duration(seconds: 10)),
    );

    final data = resp.data as Map<String, dynamic>;
    if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
      return List<Map<String, dynamic>>.from(data['results'] as List? ?? []);
    }
    return [];
  }

  static List<PoiPoint> _toPoiPoints(
    List<Map<String, dynamic>> results,
    PoiCategory category,
  ) =>
      results.take(15).map((r) {
        final geo = r['geometry']['location'] as Map;
        return PoiPoint(
          id:       r['place_id'] as String,
          name:     r['name']     as String,
          category: category,
          position: LatLng(
            (geo['lat'] as num).toDouble(),
            (geo['lng'] as num).toDouble(),
          ),
        );
      }).toList();

  // ── Cache ────────────────────────────────────────────────────────────────────

  static Future<void> _saveCache(List<PoiPoint> pois) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, _serialize(pois));
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static String _serialize(List<PoiPoint> pois) => jsonEncode(
        pois.map((p) => {
              'id':   p.id,
              'name': p.name,
              'cat':  p.category.index,
              'lat':  p.position.latitude,
              'lng':  p.position.longitude,
            }).toList(),
      );

  static List<PoiPoint> _deserialize(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((m) {
      final cat = m['cat'] as int;
      return PoiPoint(
        id:       m['id']   as String,
        name:     m['name'] as String,
        category: PoiCategory.values[cat],
        position: LatLng(
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
        ),
      );
    }).toList();
  }
}
