import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import '../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/map/route_marker_icons.dart';
import '../../core/services/location_reveal_controller.dart';
import '../../core/services/places_autocomplete_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/storage/promo_code_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/theme/map_theme_provider.dart';
import '../../shared/widgets/address_options_sheet.dart';
import '../../shared/widgets/address_row.dart';
import '../../shared/widgets/colored_address_field.dart';
import '../../shared/widgets/contact_mini_field.dart';
import '../../shared/widgets/contact_picker.dart';
import '../../shared/widgets/favorite_address_chips.dart';
import '../../shared/widgets/floating_map_button.dart';
import '../../shared/widgets/gradient_dialog.dart';
import '../../shared/widgets/map_placement_pin.dart';
import '../../shared/widgets/map_theme_toggle_button.dart';
import '../../shared/widgets/place_suggestions_list.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/screen_pulse_ring.dart';
import '../../shared/widgets/wizard_top_bar.dart';
import '../client_profile/data/favorite_addresses_repository.dart';
import '../deliveries/data/orders_repository.dart';
import '../home_driver/navigation/map_theme.dart';
import '../home_driver/navigation/navigation_service.dart';

// ─── Heights par step ────────────────────────────────────────────────────────
// Les hauteurs tablette sont plus généreuses pour exploiter l'écran iPad.
const _kPanelHeightsPhone = [215.0, 290.0, 350.0, 250.0];
const _kPanelHeightsTablet = [255.0, 340.0, 420.0, 300.0];
const _kMinPanelContent =
    66.0; // button (52) + bottom padding (12) + 2px margin

const _placeSuggestionsColors = PlaceSuggestionsColors(
  background: Color(0xFF1A2540),
  border: Colors.white24,
  divider: AppColors.primary,
  iconBg: AppColors.primary,
  icon: Colors.white,
  mainText: Colors.white,
  secondaryText: AppColors.primary,
  accent: AppColors.primary,
);

class OrderCreateScreen extends ConsumerStatefulWidget {
  final String orderType;
  final String priority; // NORMAL | EXPRESS — voir orders.service.js
  const OrderCreateScreen({
    super.key,
    this.orderType = 'DELIVERY',
    this.priority = 'NORMAL',
  });

  @override
  ConsumerState<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends ConsumerState<OrderCreateScreen>
    with TickerProviderStateMixin {
  final _repo = OrdersRepository();

  // ── Constants ────────────────────────────────────────────────────────────
  static const LatLng _dakar = LatLng(14.6937, -17.4441);

  // ── Step wizard ──────────────────────────────────────────────────────────
  int _step = 0; // 0=Trajet, 1=Contacts, 2=Résumé
  double _panelDragOffset = 0.0;
  bool _isDragging = false;
  late final PageController _pageCtrl;

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  bool _isMapMoving = false;
  LatLng _currentCameraPos = _dakar;

  // ── Placement mode ───────────────────────────────────────────────────────
  bool _isSelectingPickup = true;
  bool _isMapPlacementMode = false;

  // ── Addresses ────────────────────────────────────────────────────────────
  final _pickupCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController();
  final _pickupFocus = FocusNode();
  final _deliveryFocus = FocusNode();
  double? _pickupLat, _pickupLng;
  double? _deliveryLat, _deliveryLng;

  // ── Contacts ─────────────────────────────────────────────────────────────
  final _senderNameCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  final _receiverNameCtrl = TextEditingController();
  final _receiverPhoneCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  // ── Autocomplete ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;
  String? _searchError;
  String? _sessionToken;
  Timer? _searchDebounce;

  // ── Pricing ──────────────────────────────────────────────────────────────
  double _surgeMultiplier = 1.0;
  double? _estimatedPrice; // prix course (= ce que le livreur gagne)
  double _demFee = 0.0; // frais DEM prélevés en sus au client
  double? _routeDistanceKm;
  int? _routeDurationMin;

  // ── Promotion (voir promo.service.js côté serveur) ──────────────────────
  // discountAmount/promoLabel peuvent venir soit d'une campagne auto-appliquée
  // (silencieuse, pas de code — promoLabel = nom de la campagne, à afficher
  // uniquement) soit d'un code saisi manuellement (promoLabel = le vrai code,
  // renvoyé à la création — voir _submit). Le calcul final est de toute façon
  // toujours refait côté serveur, jamais fait confiance à ce preview.
  double? _discountAmount;
  String? _promoLabel;
  String? _promoError;
  bool _checkingPromo = false;
  final _promoCodeCtrl = TextEditingController();

  bool _loadingSurge = false;
  bool _priceTimedOut = false;
  bool _loadingGps = false;
  bool _submitting = false;

  // ── Livraison programmée ─────────────────────────────────────────────────
  // Manquait côté client (déjà disponible pour DEM Pro) — écart concurrentiel
  // réel face à Uber Eats/Glovo/Jumia, qui permettent tous de programmer.
  bool _isScheduled = false;
  DateTime? _scheduledAt;

  // Tant que false, la bulle départ/destination affiche son texte mais
  // s'ouvre sur le menu de choix (position actuelle / favoris / carte /
  // écrire) au tap plutôt que le clavier — jusqu'à ce que le client
  // choisisse explicitement "Écrire l'adresse".
  bool _pickupManualEntry = false;
  bool _deliveryManualEntry = false;
  Timer? _surgeDebounce;
  Timer? _priceTimeoutTimer;
  List<LatLng> _routePoints = [];
  Map<String, dynamic>? _currentUser;

  // ── Dio public (Google Places, OSRM) — sans token JWT ────────────────────
  late final _publicDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  late final _placesService = PlacesAutocompleteService(_publicDio);

  // ── Adresses favorites ───────────────────────────────────────────────────
  final _favRepo = FavoriteAddressesRepository();
  List<Map<String, dynamic>> _favorites = [];

  // ── Marqueurs départ/destination custom (remplacent la goutte Google) ────
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _deliveryIcon;

  // ── Animation d'apparition du point de départ (GPS détecté à l'entrée) ───
  // Chute + rebond du marqueur jusqu'à sa position — contrôleur partagé avec
  // l'écran d'accueil (voir LocationRevealController).
  late final _pickupReveal = LocationRevealController(
    vsync: this,
    onUpdate: () => setState(() {}),
  );

  // Anneau qui pulse en continu autour du point de départ, tant que l'écran
  // est affiché — même principe que le marqueur "ma position" de l'écran
  // d'accueil livreur (pas un one-shot qui s'arrête).
  ScreenCoordinate? _pickupScreenPos;
  LatLng? _pickupScreenPosSource;

  Future<void> _updatePickupScreenPos(LatLng target) async {
    if (_mapController == null) return;
    final coord = await _mapController!.getScreenCoordinate(target);
    if (mounted) setState(() => _pickupScreenPos = coord);
  }

  // Appelé depuis build() — ne recalcule que si le point suivi a changé,
  // pour éviter de spammer getScreenCoordinate() à chaque frame.
  void _maybeUpdatePickupScreenPos(LatLng current) {
    if (_pickupScreenPosSource == current) return;
    _pickupScreenPosSource = current;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updatePickupScreenPos(current),
    );
  }

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _loadMapStyle();
    _fetchGpsInit();
    _loadUser();
    _loadFavorites();
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    final results = await Future.wait([
      RouteMarkerIcons.pickup(AppColors.success),
      RouteMarkerIcons.delivery(AppColors.error),
    ]);
    if (mounted)
      setState(() {
        _pickupIcon = results[0];
        _deliveryIcon = results[1];
      });
  }

  Future<void> _loadFavorites() async {
    try {
      final list = await _favRepo.getAll();
      if (mounted) setState(() => _favorites = list);
    } catch (_) {}
  }

  void _applyFavorite(Map<String, dynamic> fav) {
    final lat = (fav['lat'] as num).toDouble();
    final lng = (fav['lng'] as num).toDouble();
    final addr = fav['address'] as String;
    setState(() {
      if (_isSelectingPickup) {
        _pickupCtrl.text = addr;
        _pickupLat = lat;
        _pickupLng = lng;
      } else {
        _deliveryCtrl.text = addr;
        _deliveryLat = lat;
        _deliveryLng = lng;
      }
      _suggestions = [];
    });
    _centerMap(LatLng(lat, lng));
    _updateEstimate();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _currentUser = user);
  }

  // Priorité 1 : un code enregistré depuis l'écran dédié "Code promo" (voir
  // promo_code_screen.dart) — pré-rempli et validé silencieusement.
  // Priorité 2 (sinon) : campagne auto-appliquée sans code. Dans les deux
  // cas, aucune erreur affichée si rien ne s'applique (cas normal) — un code
  // enregistré devenu invalide/expiré est juste discrètement oublié.
  Future<void> _checkAutoPromo() async {
    if (_estimatedPrice == null) return;
    final savedCode = await PromoCodeStorage.get();
    if (savedCode != null) {
      try {
        final result = await _repo.getPromoPreview(
          price: _estimatedPrice!.toInt(),
          demFee: _demFee.toInt(),
          code: savedCode,
        );
        if (!mounted) return;
        if (result != null) {
          setState(() {
            _promoCodeCtrl.text = savedCode;
            _discountAmount = (result['discountAmount'] as num?)?.toDouble();
            _promoLabel = result['promoCode'] as String?;
          });
          return;
        }
      } catch (_) {
        // Ne s'applique pas à CETTE commande précise (ex: minimum non
        // atteint) — pas forcément mort pour autant, on ne l'efface pas ici
        // (voir promo_code_screen.dart, qui revalide sans contexte de prix
        // et efface uniquement si le code est vraiment invalide/expiré).
      }
    }
    try {
      final result = await _repo.getPromoPreview(
        price: _estimatedPrice!.toInt(),
        demFee: _demFee.toInt(),
      );
      if (!mounted || result == null) return;
      setState(() {
        _discountAmount = (result['discountAmount'] as num?)?.toDouble();
        _promoLabel = result['promoCode'] as String?;
      });
    } catch (_) {} // jamais bloquant pour la création de commande
  }

  Future<void> _applyPromoCode() async {
    final code = _promoCodeCtrl.text.trim();
    if (code.isEmpty || _estimatedPrice == null) return;
    setState(() {
      _checkingPromo = true;
      _promoError = null;
    });
    try {
      final result = await _repo.getPromoPreview(
        price: _estimatedPrice!.toInt(),
        demFee: _demFee.toInt(),
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _discountAmount = (result?['discountAmount'] as num?)?.toDouble();
        _promoLabel = result?['promoCode'] as String?;
        _checkingPromo = false;
      });
      showDemToast(context, 'Code promo appliqué !');
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingPromo = false;
          _promoError = friendlyError(e);
          _discountAmount = null;
        });
      }
    }
  }

  void _fillMe(
    TextEditingController nameCtrl,
    TextEditingController phoneCtrl,
  ) {
    if (_currentUser != null) {
      nameCtrl.text = _currentUser!['name'] ?? _currentUser!['firstName'] ?? '';
      phoneCtrl.text = (_currentUser!['phone'] ?? '').replaceFirst('+221', '');
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _pickupReveal.dispose();
    _searchDebounce?.cancel();
    _surgeDebounce?.cancel();
    _priceTimeoutTimer?.cancel();
    _pickupCtrl.dispose();
    _deliveryCtrl.dispose();
    _pickupFocus.dispose();
    _deliveryFocus.dispose();
    _senderNameCtrl.dispose();
    _senderPhoneCtrl.dispose();
    _receiverNameCtrl.dispose();
    _receiverPhoneCtrl.dispose();
    _descriptionCtrl.dispose();
    _promoCodeCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Map style ────────────────────────────────────────────────────────────
  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleMapTheme() async {
    await ref.read(mapNightProvider.notifier).toggle();
    await _loadMapStyle();
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> _fetchGpsInit() async {
    setState(() => _loadingGps = true);
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos != null && mounted) {
        final ll = LatLng(pos.latitude, pos.longitude);
        _currentCameraPos = ll;
        _centerMap(ll);
        _pickupLat = ll.latitude;
        _pickupLng = ll.longitude;
        _pickupReveal.reveal();
        _reverseGeocode(ll, forPickup: true);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _centerMap(LatLng pos) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: pos, zoom: 14, tilt: 30),
      ),
    );
  }

  // ── Reverse geocoding ────────────────────────────────────────────────────
  // Google Geocoding en premier (couvre bien mieux Dakar que le géocodeur
  // natif) puis le géocodeur natif iOS/Android en secours — jamais de
  // coordonnées brutes affichées au client, illisibles et peu rassurantes
  // (retours utilisateurs : adresse affichée sous forme de "numéros").
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

    if (!mounted) return;
    final label = (addr != null && addr.isNotEmpty)
        ? addr
        : 'Position sélectionnée';
    setState(() {
      if (forPickup) {
        _pickupCtrl.text = label;
      } else {
        _deliveryCtrl.text = label;
      }
    });
  }

  // Récupère la position GPS actuelle pour le champ départ OU destination —
  // seul le départ en bénéficiait jusqu'ici (auto-rempli à l'ouverture).
  Future<void> _useCurrentLocationFor({required bool forPickup}) async {
    if (forPickup) setState(() => _loadingGps = true);
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos == null || !mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        if (forPickup) {
          _pickupLat = ll.latitude;
          _pickupLng = ll.longitude;
          _pickupManualEntry = false;
          _isSelectingPickup = true;
        } else {
          _deliveryLat = ll.latitude;
          _deliveryLng = ll.longitude;
          _deliveryManualEntry = false;
          _isSelectingPickup = false;
        }
        _isMapPlacementMode = false;
      });
      _centerMap(ll);
      await _reverseGeocode(ll, forPickup: forPickup);
      _updateEstimate();
    } catch (_) {
      if (mounted) {
        showDemToast(
          context,
          'Impossible de récupérer la position.',
          isError: true,
        );
      }
    } finally {
      if (forPickup && mounted) setState(() => _loadingGps = false);
    }
  }

  // Menu ouvert au tap sur la bulle départ/destination — voir
  // address_options_sheet.dart. Remplace le tap direct par un choix
  // explicite entre les façons de renseigner l'adresse.
  Future<void> _showAddressMenu({required bool forPickup}) async {
    final choice = await showAddressOptionsSheet(context, forPickup: forPickup);
    if (choice == null || !mounted) return;
    switch (choice) {
      case AddressOptionChoice.currentLocation:
        await _useCurrentLocationFor(forPickup: forPickup);
      case AddressOptionChoice.favorites:
        setState(() {
          _isSelectingPickup = forPickup;
          _isMapPlacementMode = false;
        });
      case AddressOptionChoice.map:
        FocusScope.of(context).unfocus();
        setState(() {
          _isSelectingPickup = forPickup;
          _isMapPlacementMode = true;
        });
      case AddressOptionChoice.manual:
        setState(() {
          _isSelectingPickup = forPickup;
          _isMapPlacementMode = false;
          if (forPickup) {
            _pickupManualEntry = true;
          } else {
            _deliveryManualEntry = true;
          }
        });
        (forPickup ? _pickupFocus : _deliveryFocus).requestFocus();
    }
  }

  // ── Confirm map placement ─────────────────────────────────────────────────
  Future<void> _confirmPlacement() async {
    setState(() {
      _isMapPlacementMode = false;
      if (_isSelectingPickup) {
        _pickupLat = _currentCameraPos.latitude;
        _pickupLng = _currentCameraPos.longitude;
      } else {
        _deliveryLat = _currentCameraPos.latitude;
        _deliveryLng = _currentCameraPos.longitude;
      }
    });
    _updateEstimate();
    await _reverseGeocode(_currentCameraPos, forPickup: _isSelectingPickup);
  }

  // ── Autocomplete Google Places ────────────────────────────────────────────
  void _onAddressChanged(String query, {required bool forPickup}) {
    setState(() => _isSelectingPickup = forPickup);
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _sessionToken ??= PlacesAutocompleteService.newSessionToken();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() {
        _isSearching = true;
        _searchError = null;
      });
      try {
        final preds = await _placesService.autocomplete(
          query: query,
          sessionToken: _sessionToken!,
        );
        if (mounted)
          setState(() {
            _suggestions = preds;
            _isSearching = false;
          });
      } catch (e) {
        if (mounted)
          setState(() {
            _isSearching = false;
            _searchError = friendlyError(e);
          });
      }
    });
  }

  void _retryAddressSearch() {
    final query = _isSelectingPickup ? _pickupCtrl.text : _deliveryCtrl.text;
    _onAddressChanged(query, forPickup: _isSelectingPickup);
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
    final wasSelectingPickup = _isSelectingPickup;
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = []);
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
        setState(() {
          if (wasSelectingPickup) {
            _pickupLat = lat;
            _pickupLng = lng;
            _pickupCtrl.text = name;
          } else {
            _deliveryLat = lat;
            _deliveryLng = lng;
            _deliveryCtrl.text = name;
          }
        });
        _centerMap(LatLng(lat, lng));
        _updateEstimate();

        // Départ confirmé et destination encore vide -> avance directement
        // le focus, plutôt que de forcer l'utilisateur à retaper sur le champ.
        if (wasSelectingPickup && _deliveryCtrl.text.isEmpty) {
          setState(() => _isSelectingPickup = false);
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _deliveryFocus.requestFocus();
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
    if (_pickupLat == null || _deliveryLat == null) return;
    _surgeDebounce?.cancel();
    _surgeDebounce = Timer(const Duration(milliseconds: 800), _computeEstimate);
  }

  void _retryEstimate() {
    setState(() => _priceTimedOut = false);
    _updateEstimate();
  }

  void _swapAddresses() {
    setState(() {
      final tmpText = _pickupCtrl.text;
      final tmpLat = _pickupLat;
      final tmpLng = _pickupLng;
      _pickupCtrl.text = _deliveryCtrl.text;
      _pickupLat = _deliveryLat;
      _pickupLng = _deliveryLng;
      _deliveryCtrl.text = tmpText;
      _deliveryLat = tmpLat;
      _deliveryLng = tmpLng;
      final tmpManual = _pickupManualEntry;
      _pickupManualEntry = _deliveryManualEntry;
      _deliveryManualEntry = tmpManual;
      _isSelectingPickup = true;
    });
    if (_pickupLat != null || _deliveryLat != null) _updateEstimate();
  }

  // ── Validation téléphone ─────────────────────────────────────────────────
  bool _validatePhone(TextEditingController ctrl, String label) {
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
    // Essaie Google Directions en premier (clé déjà configurée)
    final googleResult = await _fetchGoogleDirections(lat1, lng1, lat2, lng2);
    if (googleResult != null) return googleResult;
    // Fallback OSRM si la clé n'est pas dispo en Dart
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
    if (_pickupLat == null || _deliveryLat == null) return;
    setState(() {
      _loadingSurge = true;
      _priceTimedOut = false;
    });

    _priceTimeoutTimer?.cancel();
    _priceTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _loadingSurge) {
        setState(() {
          _loadingSurge = false;
          _priceTimedOut = true;
        });
      }
    });

    try {
      // Lance route (visuel) et estimation en parallèle — pas séquentiels
      final routeFuture = _fetchRouteAndDistance(
        _pickupLat!,
        _pickupLng!,
        _deliveryLat!,
        _deliveryLng!,
      );
      final estimateFuture = _repo.getEstimate(
        pickupLat: _pickupLat!,
        pickupLng: _pickupLng!,
        deliveryLat: _deliveryLat!,
        deliveryLng: _deliveryLng!,
        orderType: widget.orderType,
        priority: widget.priority,
      );

      // Affiche le prix dès que l'estimation revient (sans attendre la route)
      final estimate = await estimateFuture;
      if (estimate != null && mounted) {
        setState(() {
          _surgeMultiplier =
              (estimate['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
          _estimatedPrice = (estimate['price'] as num?)?.toDouble();
          _demFee = (estimate['demFee'] as num?)?.toDouble() ?? 0.0;
          _loadingSurge = false;
          _priceTimedOut = false;
        });
        _checkAutoPromo();
      } else if (mounted) {
        setState(() {
          _loadingSurge = false;
          _priceTimedOut = true;
        });
      }

      // Route visuelle — peut arriver après le prix, c'est OK
      final routeData = await routeFuture;
      if (routeData != null && mounted) {
        setState(() {
          _routePoints = routeData['points'] as List<LatLng>;
          _routeDistanceKm = (routeData['distance'] as num?)?.toDouble();
          _routeDurationMin = routeData['durationMin'] as int?;
        });
      } else if (mounted && _pickupLat != null && _deliveryLat != null) {
        setState(
          () => _routePoints = [
            LatLng(_pickupLat!, _pickupLng!),
            LatLng(_deliveryLat!, _deliveryLng!),
          ],
        );
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingSurge = false;
          _priceTimedOut = true;
        });
    } finally {
      _priceTimeoutTimer?.cancel();
    }
  }

  // Décode le format encoded polyline de Google Maps
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
  bool get _routeComplete => _pickupLat != null && _deliveryLat != null;

  void _goStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _panelDragOffset = 0.0;
      _isDragging = false;
    });
    _pageCtrl.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (step >= 1 && _pickupLat != null && _deliveryLat != null) {
      _fitBothPoints();
    }
  }

  void _fitBothPoints() {
    final sw = LatLng(
      min(_pickupLat!, _deliveryLat!),
      min(_pickupLng!, _deliveryLng!),
    );
    final ne = LatLng(
      max(_pickupLat!, _deliveryLat!),
      max(_pickupLng!, _deliveryLng!),
    );
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
        90,
      ),
    );
  }

  // ── Contacts ─────────────────────────────────────────────────────────────
  // Voir shared/widgets/contact_picker.dart (partagé avec Livraison groupée).

  // ── Submit ────────────────────────────────────────────────────────────────
  // ── Picker date/heure livraison programmée ───────────────────────────────
  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final minDate = now.add(const Duration(minutes: 10));

    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? minDate,
      firstDate: minDate,
      lastDate: now.add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.surface,
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledAt != null
          ? TimeOfDay(hour: _scheduledAt!.hour, minute: _scheduledAt!.minute)
          : TimeOfDay(
              hour: minDate.hour,
              minute: (minDate.minute ~/ 15 + 1) * 15 % 60,
            ),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.surface,
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (picked.isBefore(minDate)) {
      showDemToast(
        context,
        'Choisissez un créneau au moins 10 min dans le futur',
        isError: true,
      );
      return;
    }
    setState(() => _scheduledAt = picked);
  }

  static String _fmtScheduleDate(DateTime dt) {
    const months = [
      'jan',
      'fév',
      'mar',
      'avr',
      'mai',
      'jun',
      'jul',
      'aoû',
      'sep',
      'oct',
      'nov',
      'déc',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _fmtScheduleTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _submit() async {
    if (_pickupCtrl.text.trim().isEmpty) {
      _pickupCtrl.text =
          '${_pickupLat!.toStringAsFixed(4)}, ${_pickupLng!.toStringAsFixed(4)}';
    }
    if (_deliveryCtrl.text.trim().isEmpty) {
      _deliveryCtrl.text =
          '${_deliveryLat!.toStringAsFixed(4)}, ${_deliveryLng!.toStringAsFixed(4)}';
    }
    setState(() => _submitting = true);
    try {
      final order = await _repo.createOrder({
        'orderType': widget.orderType,
        'priority': widget.priority,
        'pickupAddress': _pickupCtrl.text.trim(),
        'pickupLatitude': _pickupLat,
        'pickupLongitude': _pickupLng,
        'deliveryAddress': _deliveryCtrl.text.trim(),
        'deliveryLatitude': _deliveryLat,
        'deliveryLongitude': _deliveryLng,
        if (_senderNameCtrl.text.trim().isNotEmpty)
          'senderName': _senderNameCtrl.text.trim(),
        if (_senderPhoneCtrl.text.trim().isNotEmpty)
          'senderPhone': '+221${_senderPhoneCtrl.text.trim()}',
        if (_receiverNameCtrl.text.trim().isNotEmpty)
          'receiverName': _receiverNameCtrl.text.trim(),
        if (_receiverPhoneCtrl.text.trim().isNotEmpty)
          'receiverPhone': '+221${_receiverPhoneCtrl.text.trim()}',
        if (widget.orderType == 'DELIVERY')
          'description': _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
        // `price`/`demFee` envoyés à titre indicatif seulement — le serveur
        // recalcule toujours tout lui-même, jamais fait confiance à un prix
        // client (voir orders.service.js:createOrder).
        if (_estimatedPrice != null) 'price': _estimatedPrice,
        if (_demFee > 0) 'demFee': _demFee,
        // Uniquement si saisi manuellement et validé (voir _applyPromoCode) —
        // une promo auto-appliquée n'a pas besoin d'être renvoyée, le serveur
        // la retrouve tout seul (voir promo.service.js:resolveOrderPromo).
        if (_promoError == null && _promoCodeCtrl.text.trim().isNotEmpty)
          'promoCode': _promoCodeCtrl.text.trim(),
        if (_isScheduled && _scheduledAt != null)
          'scheduledAt': _scheduledAt!.toUtc().toIso8601String(),
      });

      if (_estimatedPrice != null) order['price'] = _estimatedPrice;
      if (_demFee > 0) order['demFee'] = _demFee;

      if (!mounted) return;
      if (_isScheduled && _scheduledAt != null) {
        // Une commande programmée n'a rien à chercher maintenant (le cron
        // dispatcher s'en charge à l'heure voulue) — l'écran de confirmation
        // habituel ("Recherche d'un livreur…") n'aurait aucun sens ici.
        await showGradientInfoDialog(
          context,
          icon: Icons.event_available_rounded,
          iconColor: AppColors.primary,
          title: 'Livraison programmée !',
          message:
              'Votre livraison est prévue le ${_fmtScheduleDate(_scheduledAt!)} à ${_fmtScheduleTime(_scheduledAt!)}. '
              'Un livreur sera recherché automatiquement à l\'approche de l\'heure.',
          actionLabel: 'OK',
          onAction: () => Navigator.of(context).pop(),
        );
        if (mounted) context.go('/client/home');
      } else {
        context.pushReplacement('/orders/confirmation', extra: order);
      }
    } catch (e) {
      if (mounted) {
        showDemToast(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;
    // +24px supplémentaires pour les appareils avec indicateur maison (iPhone X+)
    final extraH = bottomSafeArea > 20 ? 24.0 : 0.0;
    final isTablet = MediaQuery.of(context).size.width > 600;
    final heights = isTablet ? _kPanelHeightsTablet : _kPanelHeightsPhone;
    // Le badge de type de livraison (Simple/Express) en haut de chaque
    // étape n'existait pas quand `_kPanelHeightsPhone`/`Tablet` ont été
    // réglées — +34 sur toutes les étapes pour l'absorber sans dépendre du
    // scroll de secours.
    double stepExtra = 34.0;
    // L'étape 3 (Résumé) empile la carte de prix SOUS un récap de trajet et
    // un champ promo — elle seule a besoin de ces suppléments pour ses
    // lignes optionnelles (distance/durée, réduction, total — toujours
    // affiché depuis peu). L'étape 0 affiche la carte de prix seule : lui
    // appliquer les mêmes suppléments laissait un grand vide sous la carte
    // (le badge +34 ci-dessus suffit largement, le scroll de secours couvre
    // le reste). Calculé ligne par ligne plutôt qu'avec un seul chiffre
    // magique, pour rester correct si d'autres lignes s'ajoutent encore.
    if (_step == 3 && _estimatedPrice != null) {
      stepExtra += 40; // Divider + "Total à payer" (toujours affiché)
      if (_routeDistanceKm != null && _routeDurationMin != null) {
        stepExtra += 26; // ligne distance/durée
      }
      if ((_discountAmount ?? 0) > 0) {
        stepExtra += 26; // ligne Réduction
      }
    }
    final panelH = _isMapPlacementMode
        ? 90.0
        : heights[_step] + extraH + stepExtra;

    // Polyline + inactive markers
    Set<Polyline> polylines = {};
    Set<Marker> markers = {};
    if (_pickupLat != null && _deliveryLat != null) {
      final routePts = _routePoints.isNotEmpty
          ? _routePoints
          : [
              LatLng(_pickupLat!, _pickupLng!),
              LatLng(_deliveryLat!, _deliveryLng!),
            ];
      // Halo translucide sous le tracé plein — plus visible sur un fond de
      // carte clair et allégé que la ligne fine d'origine.
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route-glow'),
          points: routePts,
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 10,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePts,
          color: AppColors.primary,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }
    if (_pickupLat != null && (!_isSelectingPickup || !_isMapPlacementMode)) {
      _maybeUpdatePickupScreenPos(LatLng(_pickupLat!, _pickupLng!));
      final pickupLabel = _pickupCtrl.text.isNotEmpty
          ? _pickupCtrl.text
          : 'Point de départ';
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupReveal.markerPosition(
            LatLng(_pickupLat!, _pickupLng!),
          ),
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
            FocusScope.of(context).unfocus();
            setState(() {
              _isSelectingPickup = true;
              _isMapPlacementMode = true;
            });
            _centerMap(LatLng(_pickupLat!, _pickupLng!));
          },
        ),
      );
    }
    if (_deliveryLat != null && (_isSelectingPickup || !_isMapPlacementMode)) {
      final deliveryLabel = _deliveryCtrl.text.isNotEmpty
          ? _deliveryCtrl.text
          : 'Destination';
      markers.add(
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(_deliveryLat!, _deliveryLng!),
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
            FocusScope.of(context).unfocus();
            setState(() {
              _isSelectingPickup = false;
              _isMapPlacementMode = true;
            });
            _centerMap(LatLng(_deliveryLat!, _deliveryLng!));
          },
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── MAP ────────────────────────────────────────────────────────────
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _dakar,
                zoom: 14,
                tilt: 30,
              ),
              onMapCreated: (c) => _mapController = c,
              style: _mapStyle,
              onTap: (_) => FocusScope.of(context).unfocus(),
              onCameraMoveStarted: () => setState(() => _isMapMoving = true),
              onCameraMove: (p) => _currentCameraPos = p.target,
              onCameraIdle: () {
                setState(() => _isMapMoving = false);
                // Recale l'anneau après un pan/zoom manuel (le point suivi n'a
                // pas changé donc _maybeUpdatePickupScreenPos ne se redéclenche
                // pas tout seul dans ce cas).
                if (_pickupLat != null)
                  _updatePickupScreenPos(LatLng(_pickupLat!, _pickupLng!));
              },
              polylines: polylines,
              markers: markers,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
            ),
          ),

          // ── Voile dégradé en haut de la carte ───────────────────────────────
          // Sans lui, un libellé de lieu Google Maps assez long (ex: nom de
          // quartier) peut parfois déborder dans les interstices entre la
          // barre du haut et les champs départ/destination — ces champs sont
          // quasi-opaques mais pas le petit espace qui les sépare de l'en-
          // tête. Ce voile assourdit tout ce qu'il y a derrière sur cette
          // zone, quel que soit le libellé qui s'y trouve.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.30),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Anneau continu autour du point de départ ────────────────────────
          if (_pickupLat != null &&
              (!_isSelectingPickup || !_isMapPlacementMode))
            ScreenPulseRing(
              position: _pickupScreenPos,
              color: AppColors.success,
              size: 66,
            ),

          // ── CENTER PIN (placement mode only) ───────────────────────────────
          if (_isMapPlacementMode)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 35),
                child: AnimatedScale(
                  scale: _isMapMoving ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: MapPlacementPin(
                    color: _isSelectingPickup
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ),
            ),

          // ── MAP THEME (gauche) + RECENTER (droite) — même niveau ─────────
          Positioned(
            left: 16,
            right: 16,
            bottom:
                max(_kMinPanelContent + 22.0, panelH - _panelDragOffset) +
                60 +
                keyboardH,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                MapThemeToggleButton(onTap: _toggleMapTheme, size: 44),
                FloatingMapButton(
                  icon: _loadingGps ? null : Icons.my_location,
                  loading: _loadingGps,
                  onTap: _fetchGpsInit,
                ),
              ],
            ),
          ),
          // ── BOTTOM PANEL ───────────────────────────────────────────────────
          // Le fond dégradé reste ancré au bas de l'écran en toutes
          // circonstances (jamais décalé par un margin lié au clavier) —
          // sinon un vide apparaît sous le panneau qui révèle la carte
          // derrière le clavier au lieu de la continuité du dégradé. Seul le
          // contenu (Column) reçoit un padding animé, ce qui fait aussi
          // grandir le conteneur (ancré en bas, non explicitement hauteur
          // fixe) vers le haut quand le clavier s'ouvre.
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: AppColors.gradientSplash,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                padding: EdgeInsets.only(bottom: keyboardH),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragStart: (_) =>
                            setState(() => _isDragging = true),
                        onVerticalDragUpdate: (d) {
                          final maxOffset = (panelH - 20) - _kMinPanelContent;
                          setState(() {
                            _panelDragOffset = (_panelDragOffset + d.delta.dy)
                                .clamp(0.0, max(0.0, maxOffset));
                          });
                        },
                        onVerticalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          final maxOffset = (panelH - 20) - _kMinPanelContent;
                          setState(() {
                            _isDragging = false;
                            _panelDragOffset =
                                (v > 200 || _panelDragOffset > maxOffset / 2)
                                ? maxOffset
                                : 0.0;
                          });
                        },
                        onTap: () {
                          final maxOffset = (panelH - 20) - _kMinPanelContent;
                          setState(() {
                            _isDragging = false;
                            _panelDragOffset = _panelDragOffset == 0
                                ? maxOffset
                                : 0.0;
                          });
                        },
                        child: SizedBox(
                          width: double.infinity,
                          height: 22,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Content via PageView (non scrollable)
                      AnimatedContainer(
                        duration: _isDragging
                            ? Duration.zero
                            : const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        height: _isMapPlacementMode
                            ? panelH - 20
                            : max(
                                _kMinPanelContent,
                                (panelH - 20) - _panelDragOffset,
                              ),
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            maxHeight: panelH - 20,
                            child: SizedBox(
                              height: panelH - 20,
                              child: _isMapPlacementMode
                                  ? MapPlacementConfirmPanel(
                                      color: _isSelectingPickup
                                          ? AppColors.success
                                          : AppColors.error,
                                      label: _isSelectingPickup
                                          ? 'Valider ce point de départ'
                                          : 'Valider cette destination',
                                      onConfirm: _confirmPlacement,
                                    )
                                  : PageView(
                                      controller: _pageCtrl,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      onPageChanged: (i) =>
                                          setState(() => _step = i),
                                      children: [
                                        _Step0Panel(
                                          priority: widget.priority,
                                          routeComplete: _routeComplete,
                                          estimatedPrice: _estimatedPrice,
                                          demFee: _demFee,
                                          surgeMultiplier: _surgeMultiplier,
                                          loadingSurge: _loadingSurge,
                                          timedOut: _priceTimedOut,
                                          onRetry: _retryEstimate,
                                          onNext: () => _goStep(1),
                                          distanceKm: _routeDistanceKm,
                                          durationMin: _routeDurationMin,
                                        ),
                                        _Step1Panel(
                                          priority: widget.priority,
                                          orderType: widget.orderType,
                                          nameCtrl: _senderNameCtrl,
                                          phoneCtrl: _senderPhoneCtrl,
                                          onPickContact: () => pickContact(
                                            context,
                                            nameCtrl: _senderNameCtrl,
                                            phoneCtrl: _senderPhoneCtrl,
                                          ),
                                          onPickMe: () {
                                            _fillMe(
                                              _senderNameCtrl,
                                              _senderPhoneCtrl,
                                            );
                                            if (_senderPhoneCtrl.text.length >=
                                                9)
                                              _goStep(2);
                                          },
                                          onPhoneComplete: () => _goStep(2),
                                          onNext: () {
                                            if (!_validatePhone(
                                              _senderPhoneCtrl,
                                              'expéditeur',
                                            ))
                                              return;
                                            _goStep(2);
                                          },
                                        ),
                                        _Step2Panel(
                                          priority: widget.priority,
                                          orderType: widget.orderType,
                                          nameCtrl: _receiverNameCtrl,
                                          phoneCtrl: _receiverPhoneCtrl,
                                          descriptionCtrl: _descriptionCtrl,
                                          onPickContact: () => pickContact(
                                            context,
                                            nameCtrl: _receiverNameCtrl,
                                            phoneCtrl: _receiverPhoneCtrl,
                                          ),
                                          onPickMe: () {
                                            _fillMe(
                                              _receiverNameCtrl,
                                              _receiverPhoneCtrl,
                                            );
                                            if (_receiverPhoneCtrl
                                                    .text
                                                    .length >=
                                                9) {
                                              _updateEstimate();
                                              _goStep(3);
                                            }
                                          },
                                          onPhoneComplete: () {
                                            _updateEstimate();
                                            _goStep(3);
                                          },
                                          onNext: () {
                                            if (!_validatePhone(
                                              _receiverPhoneCtrl,
                                              'destinataire',
                                            ))
                                              return;
                                            _updateEstimate();
                                            _goStep(3);
                                          },
                                        ),
                                        _Step3Panel(
                                          priority: widget.priority,
                                          pickupLabel:
                                              _pickupCtrl.text.isNotEmpty
                                              ? _pickupCtrl.text
                                              : 'Départ',
                                          deliveryLabel:
                                              _deliveryCtrl.text.isNotEmpty
                                              ? _deliveryCtrl.text
                                              : 'Destination',
                                          estimatedPrice: _estimatedPrice,
                                          demFee: _demFee,
                                          discountAmount: _discountAmount,
                                          promoLabel: _promoLabel,
                                          promoCodeCtrl: _promoCodeCtrl,
                                          promoError: _promoError,
                                          checkingPromo: _checkingPromo,
                                          onApplyPromo: _applyPromoCode,
                                          surgeMultiplier: _surgeMultiplier,
                                          loadingSurge: _loadingSurge,
                                          timedOut: _priceTimedOut,
                                          submitting: _submitting,
                                          canSubmit:
                                              _routeComplete &&
                                              _estimatedPrice != null,
                                          onRetry: _retryEstimate,
                                          onSubmit: _submit,
                                          distanceKm: _routeDistanceKm,
                                          durationMin: _routeDurationMin,
                                          isScheduled: _isScheduled,
                                          scheduledAt: _scheduledAt,
                                          onToggleScheduled: (v) {
                                            setState(() {
                                              _isScheduled = v;
                                              if (!v) _scheduledAt = null;
                                            });
                                            if (v) _pickScheduleDate();
                                          },
                                          onPickScheduleDate: _pickScheduleDate,
                                          onEditPickup: () {
                                            setState(
                                              () => _isSelectingPickup = true,
                                            );
                                            _goStep(0);
                                            Future.delayed(
                                              const Duration(milliseconds: 300),
                                              () => _pickupFocus.requestFocus(),
                                            );
                                          },
                                          onEditDelivery: () {
                                            setState(
                                              () => _isSelectingPickup = false,
                                            );
                                            _goStep(0);
                                            Future.delayed(
                                              const Duration(milliseconds: 300),
                                              () =>
                                                  _deliveryFocus.requestFocus(),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                            ), // SizedBox
                          ), // OverflowBox
                        ), // ClipRect
                      ), // AnimatedContainer
                    ],
                  ), // Column
                ), // SafeArea
              ), // AnimatedPadding
            ), // AnimatedContainer (gradient)
          ), // Align
          // ── TOP BAR ────────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  WizardTopBar(
                    title: widget.priority == 'EXPRESS'
                        ? 'Livraison Express ⚡'
                        : 'Livraison Simple',
                    step: _step,
                    onBack: () {
                      if (_step > 0) {
                        _goStep(_step - 1);
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const SizedBox(height: 8),

                  // Search fields (step 0 only, not in placement mode)
                  if (_step == 0) ...[
                    AddressField(
                      controller: _pickupCtrl,
                      focusNode: _pickupFocus,
                      hint: 'Localisation actuelle',
                      dotColor: AppColors.success,
                      active: _isSelectingPickup && !_isMapPlacementMode,
                      confirmed: _pickupLat != null,
                      readOnly: !_pickupManualEntry,
                      onTap: () {
                        if (!_pickupManualEntry) {
                          _showAddressMenu(forPickup: true);
                          return;
                        }
                        // Déjà en saisie libre — toujours focus son propre
                        // champ, un tap sur départ doit permettre de le
                        // corriger, pas sauter ailleurs.
                        setState(() {
                          _isSelectingPickup = true;
                          _isMapPlacementMode = false;
                        });
                        _pickupFocus.requestFocus();
                      },
                      onChanged: (v) => _onAddressChanged(v, forPickup: true),
                      onClear: () {
                        setState(() {
                          _pickupCtrl.clear();
                          _pickupLat = null;
                          _pickupLng = null;
                          _estimatedPrice = null;
                          _routeDistanceKm = null;
                          _routeDurationMin = null;
                          _suggestions = [];
                          _isSelectingPickup = true;
                          _isMapPlacementMode = false;
                          // Revient à l'état par défaut — un tap rouvrira le
                          // menu de choix plutôt que le clavier.
                          _pickupManualEntry = false;
                        });
                      },
                      onMapTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _isSelectingPickup = true;
                          _isMapPlacementMode = true;
                        });
                      },
                      onDotLongPress: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _isSelectingPickup = true;
                          _isMapPlacementMode = true;
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          // Aligné avec le centre des points colorés des champs
                          // d'adresse. Pointillés pleins (pas de transparence)
                          // façon Uber/Bolt — se lit comme "trajet en cours de
                          // construction", visible sur n'importe quel fond de
                          // carte contrairement à l'ancien trait translucide.
                          const SizedBox(width: 7.5),
                          SizedBox(
                            width: 3,
                            height: 20,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(
                                3,
                                (_) => Container(
                                  width: 3,
                                  height: 3,
                                  decoration: const BoxDecoration(
                                    color: AppColors.textMuted,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          // ── Swap départ ↔ arrivée — nettement à droite ──────
                          Pressable(
                            onTap: _swapAddresses,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.40,
                                  ),
                                ),
                                boxShadow: AppShadows.floating,
                              ),
                              child: const Icon(
                                Icons.swap_vert,
                                color: AppColors.primary,
                                size: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AddressField(
                      controller: _deliveryCtrl,
                      focusNode: _deliveryFocus,
                      hint: "Choisir l'adresse de destination",
                      dotColor: AppColors.error,
                      active: !_isSelectingPickup && !_isMapPlacementMode,
                      confirmed: _deliveryLat != null,
                      readOnly: !_deliveryManualEntry,
                      onTap: () {
                        if (!_deliveryManualEntry) {
                          _showAddressMenu(forPickup: false);
                          return;
                        }
                        // Déjà en saisie libre — même correctif que pour le
                        // champ départ, cf. commentaire ci-dessus.
                        setState(() {
                          _isSelectingPickup = false;
                          _isMapPlacementMode = false;
                        });
                        _deliveryFocus.requestFocus();
                      },
                      onChanged: (v) => _onAddressChanged(v, forPickup: false),
                      onClear: () {
                        setState(() {
                          _deliveryCtrl.clear();
                          _deliveryLat = null;
                          _deliveryLng = null;
                          _estimatedPrice = null;
                          _routeDistanceKm = null;
                          _routeDurationMin = null;
                          _suggestions = [];
                          _isSelectingPickup = false;
                          _isMapPlacementMode = false;
                          _deliveryManualEntry = false;
                        });
                      },
                      onMapTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _isSelectingPickup = false;
                          _isMapPlacementMode = true;
                        });
                      },
                      onDotLongPress: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _isSelectingPickup = false;
                          _isMapPlacementMode = true;
                        });
                      },
                    ),

                    // ── Chips adresses favorites ──────────────────────────
                    if (_favorites.isNotEmpty && !_isMapPlacementMode) ...[
                      const SizedBox(height: 6),
                      FavoriteAddressChips(
                        favorites: _favorites,
                        onSelect: _applyFavorite,
                      ),
                    ],

                    // Autocomplete dropdown
                    if (_isSearching ||
                        _suggestions.isNotEmpty ||
                        _searchError != null) ...[
                      const SizedBox(height: 6),
                      PlaceSuggestionsList(
                        suggestions: _suggestions,
                        loading: _isSearching,
                        error: _searchError,
                        onRetry: _retryAddressSearch,
                        onSelect: _selectSuggestion,
                        colors: _placeSuggestionsColors,
                        maxHeight:
                            (MediaQuery.of(context).size.height -
                                    MediaQuery.of(context).viewInsets.bottom -
                                    MediaQuery.of(context).padding.top -
                                    160)
                                .clamp(100.0, 320.0),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Panels de chaque step
// ─────────────────────────────────────────────────────────────────────────────

// Rappel du type de livraison choisi (Simple/Express) — répété en haut de
// chaque étape du tunnel pour que ce soit visible sans avoir à remonter à
// la barre du haut. Un seul widget pour éviter 4 copies divergentes.
class _DeliveryTypeBadge extends StatelessWidget {
  final String priority;
  const _DeliveryTypeBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final isExpress = priority == 'EXPRESS';
    // `AppColors.primary` (cyan) sur le dégradé bleu de fond (gradientSplash)
    // manque de contraste — les deux teintes sont trop proches, texte
    // presque illisible. Blanc pour Simple, l'ambre reste lisible tel quel
    // pour Express.
    final color = isExpress ? AppColors.warning : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isExpress ? Icons.bolt_rounded : Icons.inventory_2_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            isExpress
                ? 'Livraison Express — livreur le plus proche, +40%'
                : 'Livraison Simple — tarif standard',
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step0Panel extends StatelessWidget {
  final String priority;
  final bool routeComplete;
  final double? estimatedPrice;
  final double demFee;
  final double surgeMultiplier;
  final bool loadingSurge;
  final bool timedOut;
  final VoidCallback onRetry;
  final VoidCallback onNext;
  final double? distanceKm;
  final int? durationMin;
  const _Step0Panel({
    required this.priority,
    required this.routeComplete,
    required this.estimatedPrice,
    required this.demFee,
    required this.surgeMultiplier,
    required this.loadingSurge,
    required this.timedOut,
    required this.onRetry,
    required this.onNext,
    this.distanceKm,
    this.durationMin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `Expanded` + scroll plutôt qu'un `Spacer` fixe : le badge de
          // type de livraison ajouté au-dessus du conseil "Astuce" laissait
          // à peine quelques pixels de marge sur le budget de hauteur fixe
          // de cette étape — même remède que le panneau Résumé (voir plus
          // bas) pour ne plus jamais dépendre d'un calcul au pixel près.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rappel du type de livraison choisi — visible dès
                  // l'étape Trajet, avant même que le prix ne soit
                  // disponible, ET une fois le prix affiché (auparavant
                  // visible seulement dans l'état "Astuce", donc absent dès
                  // que le trajet était complet).
                  _DeliveryTypeBadge(priority: priority),
                  const SizedBox(height: 8),
                  // Le conseil "Astuce" cède la place au prix dès qu'il est
                  // disponible — évite d'empiler un texte devenu obsolète
                  // (l'action qu'il décrit est déjà faite) au-dessus de
                  // l'info la plus utile.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SizeTransition(
                        sizeFactor: anim,
                        alignment: Alignment.topCenter,
                        child: child,
                      ),
                    ),
                    child: routeComplete
                        ? _EstimatePriceCard(
                            key: const ValueKey('price'),
                            estimatedPrice: estimatedPrice,
                            demFee: demFee,
                            surgeMultiplier: surgeMultiplier,
                            loadingSurge: loadingSurge,
                            timedOut: timedOut,
                            onRetry: onRetry,
                            distanceKm: distanceKm,
                            durationMin: durationMin,
                          )
                        : Column(
                            key: const ValueKey('tip'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Astuce',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Appuie sur la barre de recherche pour choisir "
                                'comment renseigner tes adresses.',
                                maxLines: 3,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.70),
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Contacts',
            trailingIcon: Icons.arrow_forward,
            onTap: routeComplete ? onNext : null,
          ),
        ],
      ),
    );
  }
}

// ─── Carte de prix estimé — réutilisée à l'étape 0 (Trajet) et à l'étape 3
// (Résumé) pour un affichage cohérent, dès que l'estimation revient.
class _EstimatePriceCard extends StatelessWidget {
  final double? estimatedPrice;
  final double demFee;
  final double? discountAmount;
  final String? promoLabel;
  final double surgeMultiplier;
  final bool loadingSurge;
  final bool timedOut;
  final VoidCallback onRetry;
  final double? distanceKm;
  final int? durationMin;

  const _EstimatePriceCard({
    super.key,
    required this.estimatedPrice,
    required this.demFee,
    this.discountAmount,
    this.promoLabel,
    required this.surgeMultiplier,
    required this.loadingSurge,
    required this.timedOut,
    required this.onRetry,
    this.distanceKm,
    this.durationMin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: loadingSurge
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            )
          : timedOut && estimatedPrice == null
          // ── État timeout : impossible de calculer le prix ──
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_outlined,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Impossible de calculer le prix',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.40),
                      ),
                    ),
                    child: Text(
                      'Réessayer',
                      style: ClientText.body.copyWith(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            )
          // ── État normal : affichage du prix ──
          : Builder(
              builder: (context) {
                // Rien à détailler (pas de frais, pas de réduction) : Total
                // == Course exactement — inutile de répéter le même chiffre
                // deux fois. Un seul montant net et bien visible, comme
                // Uber/Bolt le font quand il n'y a rien à justifier. Dès
                // qu'il y a un frais ou une réduction, la ventilation
                // complète reprend son sens.
                final hasBreakdown = demFee > 0 || (discountAmount ?? 0) > 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasBreakdown) ...[
                      // Ligne : prix course + surge badge
                      Row(
                        children: [
                          const Icon(
                            Icons.two_wheeler_outlined,
                            color: AppColors.textSecondary,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Course',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (surgeMultiplier > 1.0) ...[
                            _SurgeBadge(surgeMultiplier: surgeMultiplier),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            estimatedPrice != null
                                ? formatFcfa(estimatedPrice!)
                                : '—',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ] else if (estimatedPrice != null) ...[
                      // Rien à détailler — un seul chiffre net.
                      Row(
                        children: [
                          if (surgeMultiplier > 1.0) ...[
                            _SurgeBadge(surgeMultiplier: surgeMultiplier),
                            const SizedBox(width: 8),
                          ],
                          const Text(
                            'Total à payer',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formatFcfa(estimatedPrice!),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Ligne : distance/durée estimées — comble le vide sous
                    // la carte de prix et confirme visuellement le trajet
                    // calculé.
                    if (estimatedPrice != null &&
                        distanceKm != null &&
                        durationMin != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.route_outlined,
                            color: AppColors.textSecondary,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '≈ ${distanceKm!.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.schedule_outlined,
                            color: AppColors.textSecondary,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$durationMin min',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (hasBreakdown) ...[
                      // Ligne : frais DEM (visible uniquement si > 0)
                      if (estimatedPrice != null && demFee > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.percent_outlined,
                              color: AppColors.textSecondary,
                              size: 13,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Frais DEM',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '+${formatFcfa(demFee)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Ligne : réduction promo (le livreur touche toujours
                      // le prix plein — voir orders.service.js côté serveur)
                      if (estimatedPrice != null &&
                          discountAmount != null &&
                          discountAmount! > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              promoLabel != null
                                  ? 'Réduction ($promoLabel)'
                                  : 'Réduction',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '-${formatFcfa(discountAmount!)}',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Total — toujours affiché dès qu'un prix existe,
                      // réduction ou non : le client ne doit jamais avoir à
                      // additionner Course + Frais DEM lui-même.
                      if (estimatedPrice != null) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Divider(
                            height: 1,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Row(
                          children: [
                            const Text(
                              'Total à payer',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              formatFcfa(
                                (estimatedPrice! +
                                        demFee -
                                        (discountAmount ?? 0))
                                    .clamp(0, double.infinity),
                              ),
                              // Accent cyan + taille nettement supérieure :
                              // c'est le seul chiffre qui compte vraiment
                              // pour le client, il doit sauter aux yeux sans
                              // lecture des lignes au-dessus.
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                );
              },
            ),
    );
  }
}

// Badge "×1.5" etc. — utilisé à la fois par la ligne "Course" (ventilation
// complète) et par la ligne "Total à payer" (vue simplifiée sans frais ni
// réduction), d'où l'extraction pour ne pas dupliquer ce petit morceau.
class _SurgeBadge extends StatelessWidget {
  final double surgeMultiplier;
  const _SurgeBadge({required this.surgeMultiplier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surge.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.surge.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flash_on, color: AppColors.surge, size: 11),
          const SizedBox(width: 2),
          Text(
            '×${surgeMultiplier.toStringAsFixed(1)}',
            style: const TextStyle(
              color: AppColors.surge,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Champ de saisie d'un code promo — n'affiche jamais le mot "erreur" pour un
// simple "pas de promo" (silencieux), seulement pour un code invalide.
class _PromoCodeField extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final bool checking;
  final bool applied;
  final VoidCallback onApply;

  const _PromoCodeField({
    required this.controller,
    this.error,
    required this.checking,
    required this.applied,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Code promo (optionnel)',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: checking ? null : onApply,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: applied
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (applied ? AppColors.success : AppColors.primary)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : Text(
                        applied ? 'Appliqué ✓' : 'Appliquer',
                        style: TextStyle(
                          color: applied
                              ? AppColors.success
                              : AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: const TextStyle(color: AppColors.error, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class _Step1Panel extends StatelessWidget {
  final String priority;
  final String orderType;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onPickContact;
  final VoidCallback? onPickMe;
  final VoidCallback? onPhoneComplete;
  final VoidCallback onNext;

  const _Step1Panel({
    required this.priority,
    required this.orderType,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.onPickContact,
    this.onPickMe,
    this.onPhoneComplete,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          _DeliveryTypeBadge(priority: priority),
          const SizedBox(height: 8),
          // `Expanded` + scroll : le badge ajouté au-dessus laissait trop
          // peu de marge sur le budget de hauteur fixe de cette étape
          // (quelques pixels à peine) — même remède que Step0/Step2/Step3
          // pour ne plus jamais dépendre d'un calcul au pixel près.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Utilisez vos contacts 👤 pour gagner du temps',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ContactMiniField(
                    label: 'Expéditeur',
                    dotColor: AppColors.success,
                    nameCtrl: nameCtrl,
                    phoneCtrl: phoneCtrl,
                    onPick: onPickContact,
                    onPickMe: onPickMe,
                    onPhoneComplete: onPhoneComplete,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Destinataire',
            trailingIcon: Icons.arrow_forward,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _Step2Panel extends StatelessWidget {
  final String priority;
  final String orderType;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController descriptionCtrl;
  final VoidCallback onPickContact;
  final VoidCallback? onPickMe;
  final VoidCallback? onPhoneComplete;
  final VoidCallback onNext;

  const _Step2Panel({
    required this.priority,
    required this.orderType,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.descriptionCtrl,
    required this.onPickContact,
    this.onPickMe,
    this.onPhoneComplete,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          _DeliveryTypeBadge(priority: priority),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Utilisez vos contacts 👤 pour gagner du temps',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ContactMiniField(
                    label: 'Destinataire',
                    dotColor: AppColors.error,
                    nameCtrl: nameCtrl,
                    phoneCtrl: phoneCtrl,
                    onPick: onPickContact,
                    onPickMe: onPickMe,
                    onPhoneComplete: onPhoneComplete,
                  ),
                  if (orderType == 'DELIVERY') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionCtrl,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Description du colis (optionnel)',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 14,
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8),
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.white.withValues(alpha: 0.65),
                            size: 18,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        fillColor: Colors.white.withValues(alpha: 0.14),
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Résumé',
            trailingIcon: Icons.arrow_forward,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _Step3Panel extends StatelessWidget {
  final String priority;
  final String pickupLabel;
  final String deliveryLabel;
  final double? estimatedPrice;
  final double demFee;
  final double? discountAmount;
  final String? promoLabel;
  final TextEditingController promoCodeCtrl;
  final String? promoError;
  final bool checkingPromo;
  final VoidCallback onApplyPromo;
  final double surgeMultiplier;
  final bool loadingSurge;
  final bool timedOut;
  final bool submitting;
  final bool canSubmit;
  final VoidCallback onRetry;
  final VoidCallback onSubmit;
  final VoidCallback? onEditPickup;
  final VoidCallback? onEditDelivery;
  final double? distanceKm;
  final int? durationMin;
  final bool isScheduled;
  final DateTime? scheduledAt;
  final ValueChanged<bool> onToggleScheduled;
  final VoidCallback onPickScheduleDate;

  const _Step3Panel({
    required this.priority,
    required this.pickupLabel,
    required this.deliveryLabel,
    required this.estimatedPrice,
    required this.demFee,
    this.discountAmount,
    this.promoLabel,
    required this.promoCodeCtrl,
    this.promoError,
    required this.checkingPromo,
    required this.onApplyPromo,
    required this.surgeMultiplier,
    required this.loadingSurge,
    required this.timedOut,
    required this.submitting,
    required this.canSubmit,
    required this.onRetry,
    required this.onSubmit,
    this.onEditPickup,
    this.onEditDelivery,
    this.distanceKm,
    this.durationMin,
    required this.isScheduled,
    required this.scheduledAt,
    required this.onToggleScheduled,
    required this.onPickScheduleDate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          _DeliveryTypeBadge(priority: priority),
          const SizedBox(height: 8),
          // `Expanded` + scroll plutôt qu'un simple `Column` : le contenu
          // ci-dessous (récap trajet, prix, code promo) a grandi plusieurs
          // fois depuis le premier réglage du budget de hauteur fixe de ce
          // panneau, provoquant à chaque fois un nouvel overflow. Avec un
          // scroll, un ajout futur réduit l'espace visible au pire, mais ne
          // peut plus jamais déborder — le bouton reste toujours visible en
          // bas, épinglé hors du scroll.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Route recap
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: onEditPickup,
                          child: Row(
                            children: [
                              Expanded(
                                child: AddressRow(
                                  icon: Icons.circle,
                                  iconColor: AppColors.success,
                                  address: pickupLabel,
                                  dark: true,
                                ),
                              ),
                              if (onEditPickup != null)
                                Icon(
                                  Icons.edit_outlined,
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.5,
                                  ),
                                  size: 14,
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            width: 2,
                            height: 14,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onEditDelivery,
                          child: Row(
                            children: [
                              Expanded(
                                child: AddressRow(
                                  icon: Icons.location_on,
                                  iconColor: AppColors.error,
                                  address: deliveryLabel,
                                  dark: true,
                                ),
                              ),
                              if (onEditDelivery != null)
                                Icon(
                                  Icons.edit_outlined,
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.5,
                                  ),
                                  size: 14,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Price card
                  _EstimatePriceCard(
                    estimatedPrice: estimatedPrice,
                    demFee: demFee,
                    discountAmount: discountAmount,
                    promoLabel: promoLabel,
                    surgeMultiplier: surgeMultiplier,
                    loadingSurge: loadingSurge,
                    timedOut: timedOut,
                    onRetry: onRetry,
                    distanceKm: distanceKm,
                    durationMin: durationMin,
                  ),
                  if (estimatedPrice != null && !loadingSurge && !timedOut) ...[
                    const SizedBox(height: 8),
                    _PromoCodeField(
                      controller: promoCodeCtrl,
                      error: promoError,
                      checking: checkingPromo,
                      applied: discountAmount != null && discountAmount! > 0,
                      onApply: onApplyPromo,
                    ),
                  ],
                  // Livraison programmée — manquait côté client (déjà
                  // disponible pour DEM Pro), écart concurrentiel réel face
                  // à Uber Eats/Glovo/Jumia qui permettent tous de
                  // programmer une commande à l'avance.
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isScheduled
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: SwitchListTile(
                      value: isScheduled,
                      onChanged: onToggleScheduled,
                      activeTrackColor: AppColors.primary,
                      activeThumbColor: Colors.white,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      title: const Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Programmer la livraison',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'Choisir une date et heure précise',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 11.5,
                        ),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                    ),
                  ),
                  if (isScheduled) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onPickScheduleDate,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheduledAt != null
                                ? AppColors.primary
                                : AppColors.warning,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: scheduledAt != null
                                  ? AppColors.primary
                                  : AppColors.warning,
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: scheduledAt != null
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _OrderCreateScreenState._fmtScheduleDate(
                                            scheduledAt!,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          _OrderCreateScreenState._fmtScheduleTime(
                                            scheduledAt!,
                                          ),
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.65,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Appuyez pour choisir la date',
                                      style: TextStyle(
                                        color: AppColors.warning,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            Icon(
                              Icons.edit_outlined,
                              color: scheduledAt != null
                                  ? Colors.white54
                                  : AppColors.warning,
                              size: 15,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // Le mode de paiement par défaut (cash) n'était jamais
                  // annoncé avant validation — le client ne savait pas s'il
                  // devait prévoir de l'espèces avant l'acceptation par un
                  // livreur. Purement informatif ici, le choix "payer en
                  // ligne" reste proposé après acceptation.
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.60),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Paiement en espèces à la livraison par défaut — le paiement en ligne sera aussi proposé une fois un livreur trouvé.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.60),
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Bouton toujours visible en bas — épinglé hors du scroll ci-dessus.
          PrimaryButton(
            label: isScheduled
                ? 'Programmer la livraison'
                : 'Trouvez un livreur',
            onTap:
                (canSubmit &&
                    !submitting &&
                    (!isScheduled || scheduledAt != null))
                ? onSubmit
                : null,
            loading: submitting,
          ),
        ],
      ),
    );
  }
}
