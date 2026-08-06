import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/error/app_exception.dart';
import '../../core/services/places_autocomplete_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/theme/map_theme_provider.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/address_options_sheet.dart';
import '../../shared/widgets/colored_address_field.dart';
import '../../shared/widgets/contact_mini_field.dart';
import '../../shared/widgets/contact_picker.dart';
import '../../shared/widgets/favorite_address_chips.dart';
import '../../shared/widgets/floating_map_button.dart';
import '../../shared/widgets/map_placement_pin.dart';
import '../../shared/widgets/map_theme_toggle_button.dart';
import '../../shared/widgets/place_suggestions_list.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/wizard_top_bar.dart';
import '../client_profile/data/favorite_addresses_repository.dart';
import '../deliveries/data/orders_repository.dart';
import '../home_driver/navigation/map_theme.dart';
import '../home_driver/navigation/navigation_service.dart';

const _kBatchAccent = Color(0xFF0C7A5C);
const _placeSuggestionsColors = PlaceSuggestionsColors(
  background: Color(0xFF1A2540),
  border: Colors.white24,
  divider: _kBatchAccent,
  iconBg: _kBatchAccent,
  icon: Colors.white,
  mainText: Colors.white,
  secondaryText: _kBatchAccent,
  accent: _kBatchAccent,
);

const _dakar = LatLng(14.6937, -17.4441);
const int _kMinStops = 2;
const int _kMaxStops = 3;
const int _kStepCount = 4; // Trajet · Expéditeur · Destinataire(s) · Résumé

class _StopEntry {
  final addressCtrl = TextEditingController();
  final receiverNameCtrl = TextEditingController();
  final receiverPhoneCtrl = TextEditingController();
  final focusNode = FocusNode();
  double? lat;
  double? lng;
  // Tant que false, la bulle s'ouvre sur le menu de choix au tap plutôt que
  // le clavier — même logique que order_create_screen.dart.
  bool manualEntry = false;

  void dispose() {
    addressCtrl.dispose();
    receiverNameCtrl.dispose();
    receiverPhoneCtrl.dispose();
    focusNode.dispose();
  }
}

bool _validatePhone(
  BuildContext context,
  TextEditingController ctrl,
  String label,
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

// ── Livraison groupée — même parcours par étapes que "Livraison simple"
// (Trajet → Expéditeur → Destinataire → Résumé, WizardTopBar, champs
// colorés) plutôt qu'un unique écran fourre-tout. Voir colored_address_field
// .dart / contact_mini_field.dart / contact_picker.dart, partagés avec
// order_create_screen.dart.
class BatchCreateScreen extends ConsumerStatefulWidget {
  const BatchCreateScreen({super.key});

  @override
  ConsumerState<BatchCreateScreen> createState() => _BatchCreateScreenState();
}

class _BatchCreateScreenState extends ConsumerState<BatchCreateScreen> {
  final _repo = OrdersRepository();
  GoogleMapController? _mapController;
  String? _mapStyle;
  final _pageCtrl = PageController();
  int _step = 0;

  late final _publicDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  late final _placesService = PlacesAutocompleteService(_publicDio);
  String _sessionToken = PlacesAutocompleteService.newSessionToken();

  final _pickupCtrl = TextEditingController();
  final _pickupFocus = FocusNode();
  double? _pickupLat;
  double? _pickupLng;
  bool _loadingGps = false;
  bool _pickupManualEntry = false;

  // ── Mode "pointer sur la carte" ──────────────────────────────────────────
  bool _isMapPlacementMode = false;
  bool _isMapMoving = false;
  LatLng _currentCameraPos = _dakar;

  final _favRepo = FavoriteAddressesRepository();
  List<Map<String, dynamic>> _favorites = [];

  final _senderNameCtrl = TextEditingController();
  final _senderPhoneCtrl = TextEditingController();
  Map<String, dynamic>? _currentUser;

  final List<_StopEntry> _stops = [_StopEntry(), _StopEntry()];

  // Champ actuellement en recherche (pour savoir où afficher les
  // suggestions) : 'pickup' ou l'index d'un arrêt.
  Object? _activeField;
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;

  Map<String, dynamic>? _estimate;
  bool _estimating = false;
  String? _estimateError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _loadUser();
    _loadFavorites();
    _fetchGpsInit();
    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus) setState(() => _activeField = 'pickup');
    });
    for (var i = 0; i < _stops.length; i++) {
      _attachFocusListener(i);
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final list = await _favRepo.getAll();
      if (mounted) setState(() => _favorites = list);
    } catch (_) {}
  }

  // Même logique que order_create_screen.dart : remplit le champ
  // actuellement en recherche (collecte ou l'arrêt en cours), 'pickup' ou
  // un index — voir _selectSuggestion pour le même aiguillage.
  void _applyFavorite(Map<String, dynamic> fav) {
    final field = _activeField;
    final lat = (fav['lat'] as num).toDouble();
    final lng = (fav['lng'] as num).toDouble();
    final addr = fav['address'] as String;
    setState(() {
      if (field == 'pickup') {
        _pickupCtrl.text = addr;
        _pickupLat = lat;
        _pickupLng = lng;
      } else if (field is int) {
        _stops[field].addressCtrl.text = addr;
        _stops[field].lat = lat;
        _stops[field].lng = lng;
      }
      _suggestions = [];
      _activeField = null;
    });
    FocusScope.of(context).unfocus();
    _updateEstimate();
    _fitMapToMarkers();
  }

  void _attachFocusListener(int index) {
    _stops[index].focusNode.addListener(() {
      if (_stops[index].focusNode.hasFocus) {
        setState(() => _activeField = index);
      }
    });
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  // Même comportement que Livraison simple/Express : la collecte démarre
  // pré-remplie avec la position actuelle du client, modifiable ensuite via
  // la recherche — évite d'avoir à taper sa propre adresse à chaque fois.
  Future<void> _fetchGpsInit() async {
    setState(() => _loadingGps = true);
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos != null && mounted) {
        final ll = LatLng(pos.latitude, pos.longitude);
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: ll, zoom: 14, tilt: 30),
          ),
        );
        setState(() {
          _pickupLat = ll.latitude;
          _pickupLng = ll.longitude;
        });
        await _reverseGeocodePickup(ll);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _reverseGeocodePickup(LatLng pos) async {
    final addr = await _reverseGeocodeLabel(pos);
    if (!mounted) return;
    setState(() => _pickupCtrl.text = addr);
  }

  Future<String> _reverseGeocodeLabel(LatLng pos) async {
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
    return (addr != null && addr.isNotEmpty) ? addr : 'Position sélectionnée';
  }

  // Position actuelle pour la collecte OU un arrêt donné — même geste que
  // order_create_screen.dart, généralisé au-delà de la seule collecte pour
  // la parité Simple/Express ↔ Groupée.
  Future<void> _useCurrentLocationFor(Object field) async {
    if (field == 'pickup') setState(() => _loadingGps = true);
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos == null || !mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      final label = await _reverseGeocodeLabel(ll);
      if (!mounted) return;
      setState(() {
        if (field == 'pickup') {
          _pickupLat = ll.latitude;
          _pickupLng = ll.longitude;
          _pickupCtrl.text = label;
          _pickupManualEntry = false;
        } else if (field is int) {
          _stops[field].lat = ll.latitude;
          _stops[field].lng = ll.longitude;
          _stops[field].addressCtrl.text = label;
          _stops[field].manualEntry = false;
        }
      });
      _updateEstimate();
      _fitMapToMarkers();
    } catch (_) {
      if (mounted) {
        showDemToast(
          context,
          'Impossible de récupérer la position.',
          isError: true,
        );
      }
    } finally {
      if (field == 'pickup' && mounted) setState(() => _loadingGps = false);
    }
  }

  // Menu ouvert au tap sur la bulle collecte/arrêt — voir
  // address_options_sheet.dart.
  Future<void> _showAddressMenu(Object field) async {
    final choice = await showAddressOptionsSheet(
      context,
      forPickup: field == 'pickup',
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case AddressOptionChoice.currentLocation:
        await _useCurrentLocationFor(field);
      case AddressOptionChoice.favorites:
        setState(() => _activeField = field);
      case AddressOptionChoice.map:
        _enterMapPlacement(field);
      case AddressOptionChoice.manual:
        setState(() {
          _activeField = field;
          if (field == 'pickup') {
            _pickupManualEntry = true;
          } else if (field is int) {
            _stops[field].manualEntry = true;
          }
        });
        if (field == 'pickup') {
          _pickupFocus.requestFocus();
        } else if (field is int) {
          _stops[field].focusNode.requestFocus();
        }
    }
  }

  // ── Mode "pointer sur la carte" ──────────────────────────────────────────
  // N'existait pas du tout sur cet écran (contrairement à Livraison
  // simple/Express) — même mécanique : un curseur fixe au centre de la
  // carte, le client déplace la carte en dessous, "Valider" lit la position
  // du centre au moment de la confirmation.
  void _enterMapPlacement(Object field) {
    FocusScope.of(context).unfocus();
    // Centre la caméra sur la position actuelle du champ visé si elle est
    // déjà connue, pour ne pas repartir de zéro si le client veut juste
    // affiner un point déjà posé.
    double? lat, lng;
    if (field == 'pickup') {
      lat = _pickupLat;
      lng = _pickupLng;
    } else if (field is int) {
      lat = _stops[field].lat;
      lng = _stops[field].lng;
    }
    if (lat != null && lng != null) {
      final target = LatLng(lat, lng);
      _currentCameraPos = target;
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    }
    setState(() {
      _activeField = field;
      _isMapPlacementMode = true;
    });
  }

  void _cancelMapPlacement() {
    setState(() => _isMapPlacementMode = false);
  }

  Future<void> _confirmMapPlacement() async {
    final field = _activeField;
    final pos = _currentCameraPos;
    setState(() {
      _isMapPlacementMode = false;
      if (field == 'pickup') {
        _pickupLat = pos.latitude;
        _pickupLng = pos.longitude;
      } else if (field is int) {
        _stops[field].lat = pos.latitude;
        _stops[field].lng = pos.longitude;
      }
    });
    final label = await _reverseGeocodeLabel(pos);
    if (!mounted) return;
    setState(() {
      if (field == 'pickup') {
        _pickupCtrl.text = label;
      } else if (field is int) {
        _stops[field].addressCtrl.text = label;
      }
    });
    _updateEstimate();
    _fitMapToMarkers();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _currentUser = user);
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

  void _goStep(int step) {
    setState(() => _step = step);
    _pageCtrl.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleMapTheme() async {
    await ref.read(mapNightProvider.notifier).toggle();
    await _loadMapStyle();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pageCtrl.dispose();
    _pickupCtrl.dispose();
    _pickupFocus.dispose();
    _senderNameCtrl.dispose();
    _senderPhoneCtrl.dispose();
    for (final s in _stops) {
      s.dispose();
    }
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _searching = true);
      try {
        final results = await _placesService.autocomplete(
          query: query,
          sessionToken: _sessionToken,
        );
        if (mounted) {
          setState(() {
            _suggestions = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _searching = false;
          });
        }
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final field = _activeField;
    final fmt = place['structured_formatting'] as Map<String, dynamic>?;
    final label =
        (fmt?['main_text'] as String?) ??
        (place['description'] as String? ?? '');
    setState(() => _suggestions = []);
    try {
      final details = await _placesService.details(
        placeId: place['place_id'] as String,
        sessionToken: _sessionToken,
      );
      final loc = details?['geometry']?['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      _sessionToken = PlacesAutocompleteService.newSessionToken();

      if (!mounted) return;
      setState(() {
        if (field == 'pickup') {
          _pickupCtrl.text = label;
          _pickupLat = lat;
          _pickupLng = lng;
        } else if (field is int) {
          _stops[field].addressCtrl.text = label;
          _stops[field].lat = lat;
          _stops[field].lng = lng;
        }
        _activeField = null;
      });
      FocusScope.of(context).unfocus();
      _updateEstimate();
      _fitMapToMarkers();
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _fitMapToMarkers() async {
    final controller = _mapController;
    if (controller == null) return;
    final points = <LatLng>[
      if (_pickupLat != null) LatLng(_pickupLat!, _pickupLng!),
      for (final s in _stops)
        if (s.lat != null) LatLng(s.lat!, s.lng!),
    ];
    if (points.length < 2) return;
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    final bounds = LatLngBounds(
      southwest: LatLng(
        lats.reduce((a, b) => a < b ? a : b),
        lngs.reduce((a, b) => a < b ? a : b),
      ),
      northeast: LatLng(
        lats.reduce((a, b) => a > b ? a : b),
        lngs.reduce((a, b) => a > b ? a : b),
      ),
    );
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  void _addStop() {
    if (_stops.length >= _kMaxStops) return;
    final entry = _StopEntry();
    setState(() => _stops.add(entry));
    _attachFocusListener(_stops.length - 1);
  }

  void _removeStop(int index) {
    if (_stops.length <= _kMinStops) return;
    setState(() {
      _stops[index].dispose();
      _stops.removeAt(index);
      _estimate = null;
    });
    _updateEstimate();
  }

  bool get _readyForEstimate =>
      _pickupLat != null &&
      _stops.length >= _kMinStops &&
      _stops.every((s) => s.lat != null && s.lng != null);

  Future<void> _updateEstimate() async {
    if (!_readyForEstimate) {
      setState(() {
        _estimate = null;
        _estimateError = null;
      });
      return;
    }
    setState(() {
      _estimating = true;
      _estimateError = null;
    });
    try {
      final result = await _repo.estimateBatch(
        pickupLatitude: _pickupLat!,
        pickupLongitude: _pickupLng!,
        stops: _stops
            .map(
              (s) => {
                'deliveryAddress': s.addressCtrl.text,
                'deliveryLatitude': s.lat,
                'deliveryLongitude': s.lng,
              },
            )
            .toList(),
      );
      if (mounted) {
        setState(() {
          _estimate = result;
          _estimating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _estimateError = friendlyError(e);
          _estimating = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_estimate == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final batch = await _repo.createBatch({
        'pickupAddress': _pickupCtrl.text.trim(),
        'pickupLatitude': _pickupLat,
        'pickupLongitude': _pickupLng,
        if (_senderNameCtrl.text.trim().isNotEmpty)
          'senderName': _senderNameCtrl.text.trim(),
        if (_senderPhoneCtrl.text.trim().isNotEmpty)
          'senderPhone': '+221${_senderPhoneCtrl.text.trim()}',
        'stops': _stops
            .map(
              (s) => {
                'deliveryAddress': s.addressCtrl.text.trim(),
                'deliveryLatitude': s.lat,
                'deliveryLongitude': s.lng,
                if (s.receiverNameCtrl.text.trim().isNotEmpty)
                  'receiverName': s.receiverNameCtrl.text.trim(),
                if (s.receiverPhoneCtrl.text.trim().isNotEmpty)
                  'receiverPhone': '+221${s.receiverPhoneCtrl.text.trim()}',
              },
            )
            .toList(),
      });
      if (!mounted) return;
      showDemToast(context, 'Tournée créée — recherche d\'un livreur…');
      context.pushReplacement('/orders/batch/mine/${batch['id']}');
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      if (_pickupLat != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(_pickupLat!, _pickupLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Collecte'),
        ),
      for (var i = 0; i < _stops.length; i++)
        if (_stops[i].lat != null)
          Marker(
            markerId: MarkerId('stop-$i'),
            position: LatLng(_stops[i].lat!, _stops[i].lng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(title: 'Arrêt ${i + 1}'),
          ),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _dakar,
                zoom: 12,
              ),
              onMapCreated: (c) => _mapController = c,
              style: _mapStyle,
              markers: markers,
              onCameraMoveStarted: () => setState(() => _isMapMoving = true),
              onCameraMove: (p) => _currentCameraPos = p.target,
              onCameraIdle: () => setState(() => _isMapMoving = false),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          // ── Curseur central (mode placement uniquement) ──────────────────
          if (_isMapPlacementMode)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 35),
                child: AnimatedScale(
                  scale: _isMapMoving ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: MapPlacementPin(
                    color: _activeField == 'pickup'
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ),
            ),
          // Voile dégradé en haut — même correctif que Livraison simple :
          // un libellé de lieu Google Maps un peu long peut sinon déborder
          // dans l'interstice entre le bandeau et le reste de l'écran.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
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
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: WizardTopBar(
                title: 'Livraison groupée',
                step: _step,
                stepCount: _kStepCount,
                onBack: () {
                  if (_step > 0) {
                    _goStep(_step - 1);
                  } else {
                    context.pop();
                  }
                },
              ),
            ),
          ),
          // `bottom: 16` seul plaçait ce bouton sous la feuille du bas (elle
          // occupe toujours 62% de l'écran, cf. Container ci-dessous) — donc
          // invisible en pratique. Positionné juste au-dessus, avec le
          // nouveau bouton de recentrage GPS à côté (même paire que
          // Livraison simple/Express).
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.sizeOf(context).height * 0.62 + 16,
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.62,
              ),
              decoration: const BoxDecoration(
                gradient: AppColors.gradientSplash,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Flexible(
                      child: _isMapPlacementMode
                          ? MapPlacementConfirmPanel(
                              color: _activeField == 'pickup'
                                  ? AppColors.success
                                  : AppColors.error,
                              label: _activeField == 'pickup'
                                  ? 'Valider ce point de collecte'
                                  : 'Valider ce point de destination',
                              onConfirm: _confirmMapPlacement,
                              onCancel: _cancelMapPlacement,
                            )
                          : PageView(
                              controller: _pageCtrl,
                              physics: const NeverScrollableScrollPhysics(),
                              onPageChanged: (i) => setState(() => _step = i),
                              children: [
                                _TrajetStep(
                                  pickupCtrl: _pickupCtrl,
                                  pickupFocus: _pickupFocus,
                                  pickupConfirmed: _pickupLat != null,
                                  pickupManualEntry: _pickupManualEntry,
                                  stops: _stops,
                                  activeField: _activeField,
                                  suggestions: _suggestions,
                                  searching: _searching,
                                  favorites: _favorites,
                                  onSelectFavorite: _applyFavorite,
                                  onPickupTap: () {
                                    if (!_pickupManualEntry) {
                                      _showAddressMenu('pickup');
                                      return;
                                    }
                                    setState(() => _activeField = 'pickup');
                                    _pickupFocus.requestFocus();
                                  },
                                  onStopTap: (i) {
                                    if (!_stops[i].manualEntry) {
                                      _showAddressMenu(i);
                                      return;
                                    }
                                    setState(() => _activeField = i);
                                    _stops[i].focusNode.requestFocus();
                                  },
                                  onQueryChanged: _onQueryChanged,
                                  onSelectSuggestion: _selectSuggestion,
                                  onPickupClear: () {
                                    setState(() {
                                      _pickupCtrl.clear();
                                      _pickupLat = null;
                                      _pickupLng = null;
                                      _estimate = null;
                                      _pickupManualEntry = false;
                                    });
                                  },
                                  onAddStop: _addStop,
                                  onRemoveStop: _removeStop,
                                  onNext: () => _goStep(1),
                                  canNext: _readyForEstimate,
                                ),
                                _ExpediteurStep(
                                  nameCtrl: _senderNameCtrl,
                                  phoneCtrl: _senderPhoneCtrl,
                                  onPickContact: () => pickContact(
                                    context,
                                    nameCtrl: _senderNameCtrl,
                                    phoneCtrl: _senderPhoneCtrl,
                                  ),
                                  onPickMe: () {
                                    _fillMe(_senderNameCtrl, _senderPhoneCtrl);
                                    if (_senderPhoneCtrl.text.length >= 9)
                                      _goStep(2);
                                  },
                                  onNext: () {
                                    if (!_validatePhone(
                                      context,
                                      _senderPhoneCtrl,
                                      'expéditeur',
                                    )) {
                                      return;
                                    }
                                    _goStep(2);
                                  },
                                ),
                                _DestinatairesStep(
                                  stops: _stops,
                                  onNext: () => _goStep(3),
                                ),
                                _ResumeStep(
                                  pickupLabel: _pickupCtrl.text,
                                  stops: _stops,
                                  estimate: _estimate,
                                  estimating: _estimating,
                                  error: _estimateError,
                                  ready: _readyForEstimate,
                                  submitting: _submitting,
                                  onEditTrajet: () => _goStep(0),
                                  onSubmit: _submit,
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Étape 0 — Trajet ─────────────────────────────────────────────────────────
class _TrajetStep extends StatelessWidget {
  final TextEditingController pickupCtrl;
  final FocusNode pickupFocus;
  final bool pickupConfirmed;
  final bool pickupManualEntry;
  final List<_StopEntry> stops;
  final Object? activeField;
  final List<Map<String, dynamic>> suggestions;
  final bool searching;
  final List<Map<String, dynamic>> favorites;
  final ValueChanged<Map<String, dynamic>> onSelectFavorite;
  final VoidCallback onPickupTap;
  final ValueChanged<int> onStopTap;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Map<String, dynamic>> onSelectSuggestion;
  final VoidCallback onPickupClear;
  final VoidCallback onAddStop;
  final ValueChanged<int> onRemoveStop;
  final VoidCallback onNext;
  final bool canNext;

  const _TrajetStep({
    required this.pickupCtrl,
    required this.pickupFocus,
    required this.pickupConfirmed,
    required this.pickupManualEntry,
    required this.stops,
    required this.activeField,
    required this.suggestions,
    required this.searching,
    required this.favorites,
    required this.onSelectFavorite,
    required this.onPickupTap,
    required this.onStopTap,
    required this.onQueryChanged,
    required this.onSelectSuggestion,
    required this.onPickupClear,
    required this.onAddStop,
    required this.onRemoveStop,
    required this.onNext,
    required this.canNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1 collecte, jusqu\'à $_kMaxStops destinations — -20% sur le total.',
                    style: ClientText.body.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  AddressField(
                    controller: pickupCtrl,
                    focusNode: pickupFocus,
                    hint: 'Adresse de collecte',
                    dotColor: AppColors.success,
                    active: activeField == 'pickup',
                    confirmed: pickupConfirmed,
                    readOnly: !pickupManualEntry,
                    onTap: onPickupTap,
                    onChanged: onQueryChanged,
                    onClear: onPickupClear,
                  ),
                  if (activeField == 'pickup' &&
                      (suggestions.isNotEmpty || searching))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: PlaceSuggestionsList(
                        suggestions: suggestions,
                        loading: searching,
                        colors: _placeSuggestionsColors,
                        onSelect: onSelectSuggestion,
                      ),
                    ),
                  if (activeField == 'pickup' && favorites.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: FavoriteAddressChips(
                        favorites: favorites,
                        onSelect: onSelectFavorite,
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    'Destinations (${stops.length}/$_kMaxStops)',
                    style: ClientText.bodyStrong.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < stops.length; i++) ...[
                    _StopCard(
                      index: i,
                      entry: stops[i],
                      canRemove: stops.length > _kMinStops,
                      onRemove: () => onRemoveStop(i),
                      onQueryChanged: onQueryChanged,
                      onTap: () => onStopTap(i),
                      active: activeField == i,
                    ),
                    if (activeField == i &&
                        (suggestions.isNotEmpty || searching))
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 6),
                        child: PlaceSuggestionsList(
                          suggestions: suggestions,
                          loading: searching,
                          colors: _placeSuggestionsColors,
                          onSelect: onSelectSuggestion,
                        ),
                      ),
                    if (activeField == i && favorites.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: FavoriteAddressChips(
                          favorites: favorites,
                          onSelect: onSelectFavorite,
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  if (stops.length < _kMaxStops)
                    Pressable(
                      onTap: onAddStop,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Ajouter un arrêt',
                              style: ClientText.body.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Suivant — Expéditeur',
            trailingIcon: Icons.arrow_forward,
            onTap: canNext ? onNext : null,
            color: _kBatchAccent,
          ),
        ],
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  final int index;
  final _StopEntry entry;
  final bool canRemove;
  final bool active;
  final VoidCallback onRemove;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onTap;
  const _StopCard({
    required this.index,
    required this.entry,
    required this.canRemove,
    required this.active,
    required this.onRemove,
    required this.onQueryChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Arrêt ${index + 1}',
                style: ClientText.body.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (canRemove)
                GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  // Zone de tap élargie (bulle colorée) plutôt qu'une icône
                  // nue de 16px — trop petite/discrète pour être repérée
                  // comme une action de suppression sur un vrai appareil.
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.error,
                      size: 15,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AddressField(
            controller: entry.addressCtrl,
            focusNode: entry.focusNode,
            hint: 'Adresse de destination',
            dotColor: AppColors.error,
            active: active,
            confirmed: entry.lat != null,
            readOnly: !entry.manualEntry,
            onTap: onTap,
            onChanged: onQueryChanged,
            onClear: () {
              entry.addressCtrl.clear();
              entry.lat = null;
              entry.lng = null;
              entry.manualEntry = false;
            },
          ),
        ],
      ),
    );
  }
}

// ── Étape 1 — Expéditeur ─────────────────────────────────────────────────────
class _ExpediteurStep extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onPickContact;
  final VoidCallback onPickMe;
  final VoidCallback onNext;

  const _ExpediteurStep({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.onPickContact,
    required this.onPickMe,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Qui dépose le colis au point de collecte ?',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.70),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: ContactMiniField(
                label: 'Expéditeur',
                dotColor: AppColors.success,
                nameCtrl: nameCtrl,
                phoneCtrl: phoneCtrl,
                onPick: onPickContact,
                onPickMe: onPickMe,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Destinataire',
            trailingIcon: Icons.arrow_forward,
            onTap: onNext,
            color: _kBatchAccent,
          ),
        ],
      ),
    );
  }
}

// ── Étape 2 — Destinataire(s) ────────────────────────────────────────────────
class _DestinatairesStep extends StatelessWidget {
  final List<_StopEntry> stops;
  final VoidCallback onNext;
  const _DestinatairesStep({required this.stops, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Qui réceptionne à chaque arrêt ? (optionnel)',
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
                  for (var i = 0; i < stops.length; i++) ...[
                    ContactMiniField(
                      label: 'Destinataire — Arrêt ${i + 1}',
                      dotColor: AppColors.error,
                      nameCtrl: stops[i].receiverNameCtrl,
                      phoneCtrl: stops[i].receiverPhoneCtrl,
                      onPick: () => pickContact(
                        context,
                        nameCtrl: stops[i].receiverNameCtrl,
                        phoneCtrl: stops[i].receiverPhoneCtrl,
                      ),
                    ),
                    if (i < stops.length - 1) const SizedBox(height: 10),
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
            color: _kBatchAccent,
          ),
        ],
      ),
    );
  }
}

// ── Étape 3 — Résumé ─────────────────────────────────────────────────────────
class _ResumeStep extends StatelessWidget {
  final String pickupLabel;
  final List<_StopEntry> stops;
  final Map<String, dynamic>? estimate;
  final bool estimating;
  final String? error;
  final bool ready;
  final bool submitting;
  final VoidCallback onEditTrajet;
  final VoidCallback onSubmit;

  const _ResumeStep({
    required this.pickupLabel,
    required this.stops,
    required this.estimate,
    required this.estimating,
    required this.error,
    required this.ready,
    required this.submitting,
    required this.onEditTrajet,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: onEditTrajet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.circle,
                                color: AppColors.success,
                                size: 12,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pickupLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.edit_outlined,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.5,
                                ),
                                size: 14,
                              ),
                            ],
                          ),
                          for (final s in stops) ...[
                            Padding(
                              padding: const EdgeInsets.only(left: 5),
                              child: Container(
                                width: 2,
                                height: 12,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: AppColors.error,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.addressCtrl.text,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PriceSummary(
                    estimate: estimate,
                    estimating: estimating,
                    error: error,
                    ready: ready,
                  ),
                  // Même rappel que Simple/Express : le mode de paiement par
                  // défaut n'était jamais annoncé avant validation.
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: estimate != null
                ? 'Confirmer — ${formatFcfa((estimate!['total'] as num).toInt())}'
                : 'Confirmer la tournée',
            onTap: (estimate != null && !submitting) ? onSubmit : null,
            loading: submitting,
            color: _kBatchAccent,
          ),
        ],
      ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  final Map<String, dynamic>? estimate;
  final bool estimating;
  final String? error;
  final bool ready;
  const _PriceSummary({
    required this.estimate,
    required this.estimating,
    required this.error,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Renseignez la collecte et au moins $_kMinStops destinations pour voir le prix.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    if (estimating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(
            color: _kBatchAccent,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          error!,
          style: const TextStyle(color: AppColors.error, fontSize: 12),
        ),
      );
    }
    if (estimate == null) return const SizedBox.shrink();

    final rawTotal = (estimate!['rawTotal'] as num).toInt();
    final discount = (estimate!['discountAmount'] as num).toInt();
    final total = (estimate!['total'] as num).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBatchAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBatchAccent.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Total tournée',
                style: ClientText.body.copyWith(color: Colors.white70),
              ),
              const Spacer(),
              if (discount > 0)
                Text(
                  formatFcfa(rawTotal),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                formatFcfa(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (discount > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Vous économisez ${formatFcfa(discount)} en groupant vos livraisons',
              style: const TextStyle(
                color: _kBatchAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
