import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../error/app_exception.dart';

/// Service partagé pour la recherche d'adresses Google Places (Autocomplete +
/// Place Details), utilisé par tous les écrans de saisie d'adresse de l'app.
///
/// Centralise ce qui était dupliqué dans chaque écran : jeton de session
/// (facturation Google groupée par recherche au lieu de facturer chaque appel
/// séparément), et l'association type de lieu → icône.
class PlacesAutocompleteService {
  const PlacesAutocompleteService(this._dio);
  final Dio _dio;

  /// Un jeton par "session" de recherche (de la première frappe jusqu'à la
  /// sélection d'un résultat ou l'abandon) — recommandé par Google pour que
  /// Autocomplete + Place Details soient facturés comme une seule requête.
  static String newSessionToken() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  Future<List<Map<String, dynamic>>> autocomplete({
    required String query,
    required String sessionToken,
    double originLat = 14.6937,
    double originLng = -17.4441,
    double radiusMeters = 60000,
  }) async {
    List<Map<String, dynamic>> predictions;
    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': query,
          'location': '$originLat,$originLng',
          'radius': radiusMeters.toInt(),
          'components': 'country:sn',
          'language': 'fr',
          'sessiontoken': sessionToken,
          'key': AppConfig.mapsApiKey,
        },
      );
      final status = res.data['status'] as String?;
      if (status == 'OK') {
        predictions = List<Map<String, dynamic>>.from(res.data['predictions']);
      } else if (status == 'ZERO_RESULTS') {
        predictions = [];
      } else {
        throw AppException('Recherche d\'adresse indisponible.');
      }
    } on AppException {
      rethrow;
    } catch (_) {
      throw AppException('Recherche d\'adresse indisponible.');
    }

    // Complément : de nombreux quartiers de Dakar (Ouakam, Grand Yoff,
    // Yeumbeul, Parcelles Assainies...) sont mal classés ou absents de
    // l'index Autocomplete faute de données Google suffisantes au Sénégal.
    // L'API Geocoding résout ces noms de quartier/localité bien plus
    // fiablement (c'est ce qu'utilise Google Maps en interne) — on l'appelle
    // en complément, best-effort, sans jamais faire échouer la recherche.
    if (query.trim().length >= 3) {
      try {
        final geocodeHit = await _geocodeFallback(query: query, originLat: originLat, originLng: originLng);
        if (geocodeHit != null && !_containsPlace(predictions, geocodeHit)) {
          predictions = [geocodeHit, ...predictions];
        }
      } catch (_) {
        // Le geocoding est un complément, pas une dépendance : une erreur ici
        // ne doit jamais empêcher l'affichage des résultats Autocomplete.
      }
    }

    return predictions;
  }

  bool _containsPlace(List<Map<String, dynamic>> predictions, Map<String, dynamic> candidate) {
    final candidateId = candidate['place_id'] as String?;
    final candidateDesc = (candidate['description'] as String?)?.toLowerCase();
    return predictions.any((p) {
      if (candidateId != null && p['place_id'] == candidateId) return true;
      final desc = (p['description'] as String?)?.toLowerCase();
      return desc != null && candidateDesc != null && desc == candidateDesc;
    });
  }

  /// Résout [query] via l'API Geocoding (bornée au Sénégal) et renvoie un
  /// objet au même format qu'une prédiction Autocomplete, pour s'insérer sans
  /// traitement particulier dans la liste de suggestions existante.
  Future<Map<String, dynamic>?> _geocodeFallback({
    required String query,
    required double originLat,
    required double originLng,
  }) async {
    final res = await _dio.get(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: {
        'address': query,
        'components': 'country:SN',
        'language': 'fr',
        'key': AppConfig.mapsApiKey,
      },
    );
    if (res.data['status'] != 'OK') return null;
    final results = res.data['results'] as List?;
    if (results == null || results.isEmpty) return null;
    final result = results.first as Map<String, dynamic>;
    final address = result['formatted_address'] as String? ?? query;
    final parts = address.split(',');
    final mainText = parts.first.trim();
    final secondaryText = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
    return {
      'place_id': result['place_id'],
      'description': address,
      'types': result['types'],
      'structured_formatting': {
        'main_text': mainText,
        'secondary_text': secondaryText,
        'main_text_matched_substrings': [
          {'offset': 0, 'length': mainText.length < query.length ? mainText.length : query.length}
        ],
      },
    };
  }

  /// Reverse-géocode une position GPS vers une adresse courte lisible
  /// ("rue, quartier") via l'API Google Geocoding — le géocodeur natif
  /// iOS/Android (utilisé en secours par les écrans appelants) couvre mal le
  /// Sénégal et retombe souvent sans résultat exploitable, d'où l'usage de
  /// la même API que [autocomplete] ici. Renvoie null si aucune adresse
  /// lisible n'a pu être trouvée — l'appelant décide alors du texte affiché
  /// (jamais les coordonnées brutes, illisibles pour un client).
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '$lat,$lng',
          'language': 'fr',
          'key': AppConfig.mapsApiKey,
        },
      );
      if (res.data['status'] != 'OK') return null;
      final results = res.data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      for (final r in results) {
        final short = _shortAddress(r as Map<String, dynamic>);
        if (short != null && short.isNotEmpty) return short;
      }
      return results.first['formatted_address'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Reconstruit une adresse courte ("rue, quartier") à partir des
  /// composants Google — plus lisible que le `formatted_address` complet qui
  /// inclut ville/pays/code postal, et cohérent avec le format déjà utilisé
  /// pour les suggestions Autocomplete.
  String? _shortAddress(Map<String, dynamic> result) {
    final components = (result['address_components'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    String? find(String type) {
      for (final c in components) {
        final types = (c['types'] as List).cast<String>();
        if (types.contains(type)) return c['long_name'] as String?;
      }
      return null;
    }

    final street = find('route');
    final local = find('sublocality') ?? find('sublocality_level_1') ?? find('locality');
    if (street != null && street.isNotEmpty) {
      return local != null && local.isNotEmpty ? '$street, $local' : street;
    }
    return local;
  }

  Future<Map<String, dynamic>?> details({
    required String placeId,
    required String sessionToken,
  }) async {
    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'fields': 'geometry,name,formatted_address,types',
          'language': 'fr',
          'sessiontoken': sessionToken,
          'key': AppConfig.mapsApiKey,
        },
      );
      if (res.data['status'] == 'OK') {
        return res.data['result'] as Map<String, dynamic>;
      }
      throw AppException('Impossible de charger l\'adresse.');
    } on AppException {
      rethrow;
    } catch (_) {
      throw AppException('Impossible de charger l\'adresse.');
    }
  }

  /// Icône représentative du type de lieu (restaurant, aéroport, gare...),
  /// pour remplacer une icône générique identique sur toutes les suggestions.
  static IconData iconForTypes(List<dynamic>? types) {
    if (types == null) return Icons.place_outlined;
    bool has(String needle) => types.any((t) => t.toString().contains(needle));

    if (has('airport')) return Icons.flight_outlined;
    if (has('transit') || has('bus') || has('station')) return Icons.directions_bus_outlined;
    if (has('hospital') || has('health') || has('pharmacy')) return Icons.local_hospital_outlined;
    if (has('school') || has('university')) return Icons.school_outlined;
    if (has('park') || has('natural')) return Icons.park_outlined;
    if (has('restaurant') || has('food') || has('cafe')) return Icons.restaurant_outlined;
    if (has('lodging') || has('hotel')) return Icons.hotel_outlined;
    if (has('store') || has('shopping') || has('supermarket')) return Icons.storefront_outlined;
    if (has('bank') || has('atm') || has('finance')) return Icons.account_balance_outlined;
    if (has('sublocality') || has('neighborhood') || has('locality')) return Icons.location_city_outlined;
    return Icons.place_outlined;
  }
}
