import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/map/route_marker_icons.dart';
import '../../../core/services/location_reveal_controller.dart';
import '../../../core/services/places_autocomplete_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/storage/promo_code_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../shared/widgets/address_options_sheet.dart';
import '../../../shared/widgets/contact_picker.dart';
import '../../../shared/widgets/favorite_address_chips.dart';
import '../../../shared/widgets/map_placement_pin.dart';
import '../../client_profile/data/favorite_addresses_repository.dart';
import '../../deliveries/data/orders_repository.dart';
import '../../home_driver/navigation/navigation_service.dart';
import '../map_host.dart';
import 'order_wizard_steps.dart';

/// Logique du parcours Express/Simple — extraite quasi telle quelle de
/// l'ancien order_create_screen.dart. Ne possède plus sa propre carte/GPS/
/// style (voir MapHost, fourni par ClientHomeShellScreen) : uniquement la
/// logique de formulaire (étapes, champs, prix, promo, soumission).
///
/// Instancié une seule fois par ClientHomeShellScreen puis CONSERVÉ tant que
/// la commande n'est pas soumise (décision produit validée : la saisie en
/// cours survit à un aller-retour vers l'accueil).
class OrderWizardController {
  OrderWizardController({
    required this.orderType,
    required this.priority,
    required this.mapHost,
    required this.onChanged,
    required this.onSubmitSuccess,
    required TickerProvider vsync,
  }) : pickupReveal = LocationRevealController(
         vsync: vsync,
         onUpdate: onChanged,
       ) {
    _init();
  }

  final String orderType;
  final String priority; // NORMAL | EXPRESS — voir orders.service.js
  final MapHost mapHost;

  /// Appelé après chaque mutation d'état — le socle y répond par un simple
  /// `setState(() {})`, exactement comme l'ancien `setState` interne à
  /// l'écran d'origine.
  final VoidCallback onChanged;

  /// Signalé une fois la commande créée avec succès (après la navigation
  /// vers /orders/confirmation) — le socle en profite pour repasser en
  /// mode accueil et détruire ce contrôleur (données déjà soumises).
  final VoidCallback onSubmitSuccess;

  final _repo = OrdersRepository();

  // ── Step wizard ──────────────────────────────────────────────────────────
  int step = 0; // 0=Trajet, 1=Contacts, 2=Résumé

  // ── Placement mode ───────────────────────────────────────────────────────
  bool isSelectingPickup = true;
  bool isMapPlacementMode = false;

  // ── Addresses ────────────────────────────────────────────────────────────
  final pickupCtrl = TextEditingController();
  final deliveryCtrl = TextEditingController();
  final pickupFocus = FocusNode();
  final deliveryFocus = FocusNode();
  double? pickupLat, pickupLng;
  double? deliveryLat, deliveryLng;

  // ── Contacts ─────────────────────────────────────────────────────────────
  final senderNameCtrl = TextEditingController();
  final senderPhoneCtrl = TextEditingController();
  final receiverNameCtrl = TextEditingController();
  final receiverPhoneCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();

  // ── Autocomplete ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> suggestions = [];
  bool isSearching = false;
  String? searchError;
  String? _sessionToken;
  Timer? _searchDebounce;

  // ── Pricing ──────────────────────────────────────────────────────────────
  double surgeMultiplier = 1.0;
  double? estimatedPrice;
  double demFee = 0.0;
  double? routeDistanceKm;
  int? routeDurationMin;

  // ── Promotion ─────────────────────────────────────────────────────────────
  double? discountAmount;
  String? promoLabel;
  String? promoError;
  bool checkingPromo = false;
  final promoCodeCtrl = TextEditingController();

  bool loadingGps = false;
  bool priceTimedOut = false;
  bool submitting = false;

  bool pickupManualEntry = false;
  bool deliveryManualEntry = false;
  Timer? _surgeDebounce;
  Timer? _priceTimeoutTimer;
  List<LatLng> routePoints = [];
  Map<String, dynamic>? currentUser;

  late final _publicDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  late final _placesService = PlacesAutocompleteService(_publicDio);

  final _favRepo = FavoriteAddressesRepository();
  List<Map<String, dynamic>> favorites = [];

  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _deliveryIcon;

  // Chute + rebond du marqueur jusqu'à sa position, à l'arrivée sur l'étape
  // Trajet — vsync fourni par le socle (seul TickerProvider de l'arbre).
  final LocationRevealController pickupReveal;

  ScreenCoordinate? pickupScreenPos;
  LatLng? _pickupScreenPosSource;

  /// Recalcule sans condition — nécessaire après un pan/zoom manuel ou une
  /// animation de caméra : le POINT suivi n'a pas changé, mais sa position à
  /// L'ÉCRAN si, et c'est elle que l'anneau de pulsation doit suivre. Utilisé
  /// par le socle sur `onCameraIdle` (voir client_home_shell_screen.dart) —
  /// la variante "maybe" ci-dessous ne suffit pas ici : elle ignore tout
  /// appel où seule la caméra a bougé (raison du bug d'anneau mal positionné
  /// repéré en test).
  Future<void> forceUpdatePickupScreenPos(LatLng target) async {
    final controller = mapHost.mapController;
    if (controller == null) return;
    final coord = await controller.getScreenCoordinate(target);
    pickupScreenPos = coord;
    onChanged();
  }

  /// À appeler à chaque frame par le socle (comme l'ancien build()) — ne
  /// recalcule que si le POINT suivi a changé (pas la caméra), pour éviter
  /// de spammer getScreenCoordinate() à chaque frame de build.
  void maybeUpdatePickupScreenPos(LatLng current) {
    if (_pickupScreenPosSource == current) return;
    _pickupScreenPosSource = current;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => forceUpdatePickupScreenPos(current),
    );
  }

  void _init() {
    _seedInitialPickup();
    _loadUser();
    _loadFavorites();
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    final results = await Future.wait([
      RouteMarkerIcons.pickup(AppColors.success),
      RouteMarkerIcons.delivery(AppColors.error),
    ]);
    _pickupIcon = results[0];
    _deliveryIcon = results[1];
    onChanged();
  }

  Future<void> _loadFavorites() async {
    try {
      final list = await _favRepo.getAll();
      favorites = list;
      onChanged();
    } catch (_) {}
  }

  void applyFavorite(Map<String, dynamic> fav) {
    final lat = (fav['lat'] as num).toDouble();
    final lng = (fav['lng'] as num).toDouble();
    final addr = fav['address'] as String;
    if (isSelectingPickup) {
      pickupCtrl.text = addr;
      pickupLat = lat;
      pickupLng = lng;
    } else {
      deliveryCtrl.text = addr;
      deliveryLat = lat;
      deliveryLng = lng;
    }
    suggestions = [];
    onChanged();
    mapHost.centerOn(LatLng(lat, lng));
    _updateEstimate();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    currentUser = user;
    onChanged();
  }

  Future<void> _checkAutoPromo() async {
    if (estimatedPrice == null) return;
    final savedCode = await PromoCodeStorage.get();
    if (savedCode != null) {
      try {
        final result = await _repo.getPromoPreview(
          price: estimatedPrice!.toInt(),
          demFee: demFee.toInt(),
          code: savedCode,
        );
        if (result != null) {
          promoCodeCtrl.text = savedCode;
          discountAmount = (result['discountAmount'] as num?)?.toDouble();
          promoLabel = result['promoCode'] as String?;
          onChanged();
          return;
        }
      } catch (_) {}
    }
    try {
      final result = await _repo.getPromoPreview(
        price: estimatedPrice!.toInt(),
        demFee: demFee.toInt(),
      );
      if (result == null) return;
      discountAmount = (result['discountAmount'] as num?)?.toDouble();
      promoLabel = result['promoCode'] as String?;
      onChanged();
    } catch (_) {}
  }

  Future<void> applyPromoCode(BuildContext context) async {
    final code = promoCodeCtrl.text.trim();
    if (code.isEmpty || estimatedPrice == null) return;
    checkingPromo = true;
    promoError = null;
    onChanged();
    try {
      final result = await _repo.getPromoPreview(
        price: estimatedPrice!.toInt(),
        demFee: demFee.toInt(),
        code: code,
      );
      discountAmount = (result?['discountAmount'] as num?)?.toDouble();
      promoLabel = result?['promoCode'] as String?;
      checkingPromo = false;
      onChanged();
      if (context.mounted) showDemToast(context, 'Code promo appliqué !');
    } catch (e) {
      checkingPromo = false;
      promoError = friendlyError(e);
      discountAmount = null;
      onChanged();
    }
  }

  void _fillMe(
    TextEditingController nameCtrl,
    TextEditingController phoneCtrl,
  ) {
    if (currentUser != null) {
      nameCtrl.text = currentUser!['name'] ?? currentUser!['firstName'] ?? '';
      phoneCtrl.text = (currentUser!['phone'] ?? '').replaceFirst('+221', '');
    }
  }

  void dispose() {
    pickupReveal.dispose();
    _searchDebounce?.cancel();
    _surgeDebounce?.cancel();
    _priceTimeoutTimer?.cancel();
    pickupCtrl.dispose();
    deliveryCtrl.dispose();
    pickupFocus.dispose();
    deliveryFocus.dispose();
    senderNameCtrl.dispose();
    senderPhoneCtrl.dispose();
    receiverNameCtrl.dispose();
    receiverPhoneCtrl.dispose();
    descriptionCtrl.dispose();
    promoCodeCtrl.dispose();
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  // La position est déjà connue du socle (flux GPS continu actif depuis
  // l'accueil) — on la reprend telle quelle, SANS jamais déplacer la caméra
  // : c'est justement ce qui cassait la continuité "une seule carte" entre
  // l'accueil et l'assistant (la caméra sautait à un autre zoom/tilt dès
  // l'entrée dans Express/Simple, repéré en test). Le point de collecte
  // apparaît là où l'utilisateur le voyait déjà — seule l'animation de
  // "chute" du marqueur (pickupReveal) joue, sur place.
  Future<void> _seedInitialPickup() async {
    final known = mapHost.currentPosition;
    if (known != null) {
      pickupLat = known.latitude;
      pickupLng = known.longitude;
      pickupReveal.reveal();
      onChanged();
      await _reverseGeocode(known, forPickup: true);
      return;
    }
    // Repli — le socle n'a pas encore de position connue (cas rare : GPS
    // pas encore résolu au moment où l'utilisateur ouvre l'assistant).
    // Seul ce chemin déplace la caméra, faute de mieux.
    loadingGps = true;
    onChanged();
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos != null) {
        final ll = LatLng(pos.latitude, pos.longitude);
        mapHost.centerOn(ll);
        pickupLat = ll.latitude;
        pickupLng = ll.longitude;
        pickupReveal.reveal();
        await _reverseGeocode(ll, forPickup: true);
      }
    } catch (_) {
    } finally {
      loadingGps = false;
      onChanged();
    }
  }

  /// Recentrage explicite (bouton "ma position") — celui-ci DOIT déplacer la
  /// caméra, contrairement à la saisie initiale silencieuse ci-dessus.
  Future<void> refreshGps() async {
    loadingGps = true;
    onChanged();
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos != null) {
        final ll = LatLng(pos.latitude, pos.longitude);
        mapHost.centerOn(ll);
        pickupLat = ll.latitude;
        pickupLng = ll.longitude;
        pickupReveal.reveal();
        await _reverseGeocode(ll, forPickup: true);
      }
    } catch (_) {
    } finally {
      loadingGps = false;
      onChanged();
    }
  }

  // ── Reverse geocoding ────────────────────────────────────────────────────
  Future<void> _reverseGeocode(LatLng pos, {required bool forPickup}) async {
    String? addr = await _placesService.reverseGeocode(
      pos.latitude,
      pos.longitude,
    );
    if (addr == null || addr.isEmpty) {
      try {
        final marks = await geo
            .placemarkFromCoordinates(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 5));
        if (marks.isNotEmpty) {
          final p = marks.first;
          final street = p.street ?? p.name ?? '';
          final local = p.subLocality ?? p.locality ?? '';
          final built = street.isNotEmpty ? '$street, $local' : local;
          if (built.isNotEmpty) addr = built;
        }
      } catch (_) {}
    }
    final label = (addr != null && addr.isNotEmpty)
        ? addr
        : 'Position sélectionnée';
    if (forPickup) {
      pickupCtrl.text = label;
    } else {
      deliveryCtrl.text = label;
    }
    onChanged();
  }

  Future<void> useCurrentLocationFor({
    required bool forPickup,
    required BuildContext context,
  }) async {
    if (forPickup) {
      loadingGps = true;
      onChanged();
    }
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos == null) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      if (forPickup) {
        pickupLat = ll.latitude;
        pickupLng = ll.longitude;
        pickupManualEntry = false;
        isSelectingPickup = true;
      } else {
        deliveryLat = ll.latitude;
        deliveryLng = ll.longitude;
        deliveryManualEntry = false;
        isSelectingPickup = false;
      }
      isMapPlacementMode = false;
      onChanged();
      mapHost.centerOn(ll);
      await _reverseGeocode(ll, forPickup: forPickup);
      _updateEstimate();
    } catch (_) {
      if (context.mounted) {
        showDemToast(
          context,
          'Impossible de récupérer la position.',
          isError: true,
        );
      }
    } finally {
      if (forPickup) {
        loadingGps = false;
        onChanged();
      }
    }
  }

  Future<void> showAddressMenu({
    required bool forPickup,
    required BuildContext context,
  }) async {
    final choice = await showAddressOptionsSheet(context, forPickup: forPickup);
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case AddressOptionChoice.currentLocation:
        await useCurrentLocationFor(forPickup: forPickup, context: context);
      case AddressOptionChoice.favorites:
        final fav = await pickFavoriteAddress(
          context,
          favorites: favorites,
          forPickup: forPickup,
        );
        if (fav == null) return;
        isSelectingPickup = forPickup;
        applyFavorite(fav);
      case AddressOptionChoice.map:
        FocusScope.of(context).unfocus();
        isSelectingPickup = forPickup;
        isMapPlacementMode = true;
        onChanged();
      case AddressOptionChoice.manual:
        isSelectingPickup = forPickup;
        isMapPlacementMode = false;
        if (forPickup) {
          pickupManualEntry = true;
        } else {
          deliveryManualEntry = true;
        }
        onChanged();
        (forPickup ? pickupFocus : deliveryFocus).requestFocus();
    }
  }

  Future<void> confirmPlacement() async {
    final pos = mapHost.currentCameraPosition;
    isMapPlacementMode = false;
    if (isSelectingPickup) {
      pickupLat = pos.latitude;
      pickupLng = pos.longitude;
    } else {
      deliveryLat = pos.latitude;
      deliveryLng = pos.longitude;
    }
    onChanged();
    _updateEstimate();
    await _reverseGeocode(pos, forPickup: isSelectingPickup);
  }

  // ── Autocomplete Google Places ────────────────────────────────────────────
  void onAddressChanged(String query, {required bool forPickup}) {
    isSelectingPickup = forPickup;
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (suggestions.isNotEmpty) {
        suggestions = [];
        onChanged();
      } else {
        onChanged();
      }
      return;
    }
    onChanged();
    _sessionToken ??= PlacesAutocompleteService.newSessionToken();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      isSearching = true;
      searchError = null;
      onChanged();
      try {
        final preds = await _placesService.autocomplete(
          query: query,
          sessionToken: _sessionToken!,
        );
        suggestions = preds;
        isSearching = false;
        onChanged();
      } catch (e) {
        isSearching = false;
        searchError = friendlyError(e);
        onChanged();
      }
    });
  }

  void retryAddressSearch() {
    final query = isSelectingPickup ? pickupCtrl.text : deliveryCtrl.text;
    onAddressChanged(query, forPickup: isSelectingPickup);
  }

  Future<void> selectSuggestion(
    Map<String, dynamic> place,
    BuildContext context,
  ) async {
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
    final wasSelectingPickup = isSelectingPickup;
    FocusScope.of(context).unfocus();
    suggestions = [];
    onChanged();
    final token = _sessionToken ?? PlacesAutocompleteService.newSessionToken();
    try {
      final result = await _placesService.details(
        placeId: placeId,
        sessionToken: token,
      );
      if (result != null) {
        final loc = result['geometry']['location'];
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final name =
            (place['structured_formatting']?['main_text'] as String?) ??
            place['description'] as String? ??
            '';
        if (wasSelectingPickup) {
          pickupLat = lat;
          pickupLng = lng;
          pickupCtrl.text = name;
        } else {
          deliveryLat = lat;
          deliveryLng = lng;
          deliveryCtrl.text = name;
        }
        onChanged();
        mapHost.centerOn(LatLng(lat, lng));
        _updateEstimate();

        if (wasSelectingPickup && deliveryCtrl.text.isEmpty) {
          isSelectingPickup = false;
          onChanged();
          Future.delayed(const Duration(milliseconds: 300), () {
            deliveryFocus.requestFocus();
          });
        }
      }
    } catch (_) {
    } finally {
      _sessionToken = null;
    }
  }

  // ── Pricing ──────────────────────────────────────────────────────────────
  void _updateEstimate() {
    if (pickupLat == null || deliveryLat == null) return;
    _surgeDebounce?.cancel();
    _surgeDebounce = Timer(const Duration(milliseconds: 800), _computeEstimate);
  }

  void retryEstimate() {
    priceTimedOut = false;
    onChanged();
    _updateEstimate();
  }

  void swapAddresses() {
    final tmpText = pickupCtrl.text;
    final tmpLat = pickupLat;
    final tmpLng = pickupLng;
    pickupCtrl.text = deliveryCtrl.text;
    pickupLat = deliveryLat;
    pickupLng = deliveryLng;
    deliveryCtrl.text = tmpText;
    deliveryLat = tmpLat;
    deliveryLng = tmpLng;
    final tmpManual = pickupManualEntry;
    pickupManualEntry = deliveryManualEntry;
    deliveryManualEntry = tmpManual;
    isSelectingPickup = true;
    onChanged();
    if (pickupLat != null || deliveryLat != null) _updateEstimate();
  }

  bool validatePhone(
    TextEditingController ctrl,
    String label,
    BuildContext context,
  ) {
    final digits = ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      showDemToast(context, 'Numéro $label requis', isError: true);
      return false;
    }
    if (digits.length < 9) {
      showDemToast(
        context,
        'Numéro $label invalide — 9 chiffres minimum',
        isError: true,
      );
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>?> _fetchRouteAndDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) async {
    final googleResult = await _fetchGoogleDirections(lat1, lng1, lat2, lng2);
    if (googleResult != null) return googleResult;
    return _fetchOsrmRoute(lat1, lng1, lat2, lng2);
  }

  Future<Map<String, dynamic>?> _fetchGoogleDirections(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) async {
    final key = AppConfig.mapsApiKey;
    if (key.isEmpty) return null;
    try {
      final res = await _publicDio.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '$lat1,$lng1',
          'destination': '$lat2,$lng2',
          'key': key,
        },
      );
      if (res.statusCode == 200 && res.data['status'] == 'OK') {
        final route =
            (res.data['routes'] as List).first as Map<String, dynamic>;
        final legs = route['legs'] as List;
        double distM = 0;
        double durS = 0;
        for (final leg in legs) {
          distM += ((leg['distance'] as Map)['value'] as num).toDouble();
          durS += ((leg['duration'] as Map)['value'] as num).toDouble();
        }
        final encoded = route['overview_polyline']['points'] as String;
        return {
          'distance': distM / 1000.0,
          'durationMin': (durS / 60).round(),
          'points': _decodePolyline(encoded),
        };
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _fetchOsrmRoute(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) async {
    try {
      final res = await _publicDio.get(
        'https://router.project-osrm.org/route/v1/driving/$lng1,$lat1;$lng2,$lat2',
        queryParameters: {'overview': 'full', 'geometries': 'geojson'},
      );
      if (res.statusCode == 200) {
        final routes = res.data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0] as Map<String, dynamic>;
          final distance = (route['distance'] as num) / 1000.0;
          final durationMin = ((route['duration'] as num) / 60).round();
          final coords = (route['geometry']['coordinates'] as List);
          final points = coords.map((c) {
            final coord = c as List;
            return LatLng(
              (coord[1] as num).toDouble(),
              (coord[0] as num).toDouble(),
            );
          }).toList();
          return {
            'distance': distance,
            'durationMin': durationMin,
            'points': points,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _computeEstimate() async {
    if (pickupLat == null || deliveryLat == null) return;
    loadingSurge = true;
    priceTimedOut = false;
    onChanged();

    _priceTimeoutTimer?.cancel();
    _priceTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (loadingSurge) {
        loadingSurge = false;
        priceTimedOut = true;
        onChanged();
      }
    });

    try {
      final routeFuture = _fetchRouteAndDistance(
        pickupLat!,
        pickupLng!,
        deliveryLat!,
        deliveryLng!,
      );
      final estimateFuture = _repo.getEstimate(
        pickupLat: pickupLat!,
        pickupLng: pickupLng!,
        deliveryLat: deliveryLat!,
        deliveryLng: deliveryLng!,
        orderType: orderType,
        priority: priority,
      );

      final estimate = await estimateFuture;
      if (estimate != null) {
        surgeMultiplier =
            (estimate['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
        estimatedPrice = (estimate['price'] as num?)?.toDouble();
        demFee = (estimate['demFee'] as num?)?.toDouble() ?? 0.0;
        loadingSurge = false;
        priceTimedOut = false;
        onChanged();
        _checkAutoPromo();
      } else {
        loadingSurge = false;
        priceTimedOut = true;
        onChanged();
      }

      final routeData = await routeFuture;
      if (routeData != null) {
        routePoints = routeData['points'] as List<LatLng>;
        routeDistanceKm = (routeData['distance'] as num?)?.toDouble();
        routeDurationMin = routeData['durationMin'] as int?;
        onChanged();
      } else if (pickupLat != null && deliveryLat != null) {
        routePoints = [
          LatLng(pickupLat!, pickupLng!),
          LatLng(deliveryLat!, deliveryLng!),
        ];
        onChanged();
      }
    } catch (_) {
      loadingSurge = false;
      priceTimedOut = true;
      onChanged();
    } finally {
      _priceTimeoutTimer?.cancel();
    }
  }

  bool loadingSurge = false;

  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, res = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      shift = 0;
      res = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        res |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }

  // ── Step navigation ───────────────────────────────────────────────────────
  bool get routeComplete => pickupLat != null && deliveryLat != null;

  void goStep(int newStep, BuildContext context) {
    FocusScope.of(context).unfocus();
    step = newStep;
    onChanged();
    mapHost.requestSheetRemeasure();
    if (newStep >= 1 && pickupLat != null && deliveryLat != null) {
      mapHost.fitPoints([
        LatLng(pickupLat!, pickupLng!),
        LatLng(deliveryLat!, deliveryLng!),
      ]);
    }
  }

  /// Contenu de l'étape courante — la Key distincte déclenche la transition
  /// d'AnimatedSwitcher côté HomeClientSheetScaffold.
  Widget buildStep(BuildContext context) {
    final Widget child;
    if (isMapPlacementMode) {
      child = MapPlacementConfirmPanel(
        color: isSelectingPickup ? AppColors.success : AppColors.error,
        label: isSelectingPickup
            ? 'Valider ce point de départ'
            : 'Valider cette destination',
        onConfirm: confirmPlacement,
      );
    } else {
      switch (step) {
        case 0:
          child = OrderStep0Panel(
            priority: priority,
            routeComplete: routeComplete,
            estimatedPrice: estimatedPrice,
            demFee: demFee,
            surgeMultiplier: surgeMultiplier,
            loadingSurge: loadingSurge,
            timedOut: priceTimedOut,
            onRetry: retryEstimate,
            onNext: () => goStep(1, context),
            distanceKm: routeDistanceKm,
            durationMin: routeDurationMin,
          );
        case 1:
          child = OrderStep1Panel(
            priority: priority,
            orderType: orderType,
            nameCtrl: senderNameCtrl,
            phoneCtrl: senderPhoneCtrl,
            onPickContact: () => pickContact(
              context,
              nameCtrl: senderNameCtrl,
              phoneCtrl: senderPhoneCtrl,
            ),
            onPickMe: () {
              _fillMe(senderNameCtrl, senderPhoneCtrl);
              if (senderPhoneCtrl.text.length >= 9) goStep(2, context);
            },
            onPhoneComplete: () => goStep(2, context),
            onNext: () {
              if (!validatePhone(senderPhoneCtrl, 'expéditeur', context))
                return;
              goStep(2, context);
            },
          );
        case 2:
          child = OrderStep2Panel(
            priority: priority,
            orderType: orderType,
            nameCtrl: receiverNameCtrl,
            phoneCtrl: receiverPhoneCtrl,
            descriptionCtrl: descriptionCtrl,
            onPickContact: () => pickContact(
              context,
              nameCtrl: receiverNameCtrl,
              phoneCtrl: receiverPhoneCtrl,
            ),
            onPickMe: () {
              _fillMe(receiverNameCtrl, receiverPhoneCtrl);
              if (receiverPhoneCtrl.text.length >= 9) {
                _updateEstimate();
                goStep(3, context);
              }
            },
            onPhoneComplete: () {
              _updateEstimate();
              goStep(3, context);
            },
            onNext: () {
              if (!validatePhone(receiverPhoneCtrl, 'destinataire', context))
                return;
              _updateEstimate();
              goStep(3, context);
            },
          );
        default:
          child = OrderStep3Panel(
            priority: priority,
            pickupLabel: pickupCtrl.text.isNotEmpty
                ? pickupCtrl.text
                : 'Départ',
            deliveryLabel: deliveryCtrl.text.isNotEmpty
                ? deliveryCtrl.text
                : 'Destination',
            estimatedPrice: estimatedPrice,
            demFee: demFee,
            discountAmount: discountAmount,
            promoLabel: promoLabel,
            promoCodeCtrl: promoCodeCtrl,
            promoError: promoError,
            checkingPromo: checkingPromo,
            onApplyPromo: () => applyPromoCode(context),
            surgeMultiplier: surgeMultiplier,
            loadingSurge: loadingSurge,
            timedOut: priceTimedOut,
            submitting: submitting,
            canSubmit: routeComplete && estimatedPrice != null,
            onRetry: retryEstimate,
            onSubmit: () => submit(context),
            distanceKm: routeDistanceKm,
            durationMin: routeDurationMin,
            onEditPickup: () {
              isSelectingPickup = true;
              onChanged();
              goStep(0, context);
              Future.delayed(
                const Duration(milliseconds: 300),
                () => pickupFocus.requestFocus(),
              );
            },
            onEditDelivery: () {
              isSelectingPickup = false;
              onChanged();
              goStep(0, context);
              Future.delayed(
                const Duration(milliseconds: 300),
                () => deliveryFocus.requestFocus(),
              );
            },
          );
      }
    }
    return KeyedSubtree(
      key: ValueKey(isMapPlacementMode ? 'placement' : step),
      child: child,
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> submit(BuildContext context) async {
    if (submitting) return;
    if (pickupCtrl.text.trim().isEmpty) {
      pickupCtrl.text =
          '${pickupLat!.toStringAsFixed(4)}, ${pickupLng!.toStringAsFixed(4)}';
    }
    if (deliveryCtrl.text.trim().isEmpty) {
      deliveryCtrl.text =
          '${deliveryLat!.toStringAsFixed(4)}, ${deliveryLng!.toStringAsFixed(4)}';
    }
    submitting = true;
    onChanged();
    try {
      final order = await _repo.createOrder({
        'orderType': orderType,
        'priority': priority,
        'pickupAddress': pickupCtrl.text.trim(),
        'pickupLatitude': pickupLat,
        'pickupLongitude': pickupLng,
        'deliveryAddress': deliveryCtrl.text.trim(),
        'deliveryLatitude': deliveryLat,
        'deliveryLongitude': deliveryLng,
        if (senderNameCtrl.text.trim().isNotEmpty)
          'senderName': senderNameCtrl.text.trim(),
        if (senderPhoneCtrl.text.trim().isNotEmpty)
          'senderPhone': '+221${senderPhoneCtrl.text.trim()}',
        if (receiverNameCtrl.text.trim().isNotEmpty)
          'receiverName': receiverNameCtrl.text.trim(),
        if (receiverPhoneCtrl.text.trim().isNotEmpty)
          'receiverPhone': '+221${receiverPhoneCtrl.text.trim()}',
        if (orderType == 'DELIVERY')
          'description': descriptionCtrl.text.trim().isEmpty
              ? null
              : descriptionCtrl.text.trim(),
        if (estimatedPrice != null) 'price': estimatedPrice,
        if (demFee > 0) 'demFee': demFee,
        if (promoError == null && promoCodeCtrl.text.trim().isNotEmpty)
          'promoCode': promoCodeCtrl.text.trim(),
      });

      if (estimatedPrice != null) order['price'] = estimatedPrice;
      if (demFee > 0) order['demFee'] = demFee;

      if (!context.mounted) return;
      context.pushReplacement('/orders/confirmation', extra: order);
      onSubmitSuccess();
    } catch (e) {
      if (context.mounted)
        showDemToast(context, friendlyError(e), isError: true);
    } finally {
      submitting = false;
      onChanged();
    }
  }

  // ── Carte : marqueurs/tracé ────────────────────────────────────────────────
  Set<Marker> get markers {
    final result = <Marker>{};
    if (pickupLat != null && (!isSelectingPickup || !isMapPlacementMode)) {
      final pickupLabel = pickupCtrl.text.isNotEmpty
          ? pickupCtrl.text
          : 'Point de départ';
      result.add(
        Marker(
          markerId: const MarkerId('order-pickup'),
          position: pickupReveal.markerPosition(LatLng(pickupLat!, pickupLng!)),
          icon:
              _pickupIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: _pickupIcon != null
              ? const Offset(0.5, 0.5)
              : const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: 'Départ',
            snippet: pickupLabel.length > 60
                ? '${pickupLabel.substring(0, 57)}…'
                : pickupLabel,
          ),
          onTap: () {
            isSelectingPickup = true;
            isMapPlacementMode = true;
            onChanged();
            mapHost.centerOn(LatLng(pickupLat!, pickupLng!));
          },
        ),
      );
    }
    if (deliveryLat != null && (isSelectingPickup || !isMapPlacementMode)) {
      final deliveryLabel = deliveryCtrl.text.isNotEmpty
          ? deliveryCtrl.text
          : 'Destination';
      result.add(
        Marker(
          markerId: const MarkerId('order-delivery'),
          position: LatLng(deliveryLat!, deliveryLng!),
          icon:
              _deliveryIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: _deliveryIcon != null
              ? RouteMarkerIcons.pinAnchor
              : const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: 'Destination',
            snippet: deliveryLabel.length > 60
                ? '${deliveryLabel.substring(0, 57)}…'
                : deliveryLabel,
          ),
          onTap: () {
            isSelectingPickup = false;
            isMapPlacementMode = true;
            onChanged();
            mapHost.centerOn(LatLng(deliveryLat!, deliveryLng!));
          },
        ),
      );
    }
    return result;
  }

  Set<Polyline> get polylines {
    if (pickupLat == null || deliveryLat == null) return {};
    final pts = routePoints.isNotEmpty
        ? routePoints
        : [LatLng(pickupLat!, pickupLng!), LatLng(deliveryLat!, deliveryLng!)];
    return {
      Polyline(
        polylineId: const PolylineId('order-route-glow'),
        points: pts,
        color: AppColors.primary.withValues(alpha: 0.25),
        width: 10,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
      Polyline(
        polylineId: const PolylineId('order-route'),
        points: pts,
        color: AppColors.primary,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }
}
