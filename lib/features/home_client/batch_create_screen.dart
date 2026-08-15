import 'dart:async';
import 'dart:math';

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
import '../../shared/widgets/floating_back_button.dart';
import '../../shared/widgets/floating_map_button.dart';
import '../../shared/widgets/map_placement_pin.dart';
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
  // AppColors.card (au lieu d'un bleu marine codé en dur légèrement
  // différent) — même fond que le reste de l'app (DEM Pro compris).
  background: AppColors.card,
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
  int _step = 0;

  // ── Hauteur réelle du panneau (mesurée) ───────────────────────────────────
  // Le panneau n'a plus de hauteur fixe (voir _estimatedPanelHeight) — les
  // boutons flottants (recentrage/retour) et le cadrage caméra ont besoin de
  // savoir où se trouve son bord haut *actuel*, mesuré après chaque frame.
  final _sheetKey = GlobalKey();
  double? _sheetHeight;

  // `AnimatedSize` anime le panneau sur ~220ms de façon autonome (son
  // propre AnimationController) — ça continue de peindre de nouvelles
  // frames SANS jamais redemander à ce widget de se reconstruire. Un seul
  // postFrameCallback ne capturait donc que la toute première frame de
  // l'animation (panneau encore petit) ; il fallait un rebuild "par
  // hasard" (un tap) pour re-déclencher une mesure et enfin voir la
  // hauteur finale. `addPostFrameCallback` se ré-enchaîne lui-même sur
  // chaque frame suivante tant que l'animation tourne (chaque frame
  // rendue en déclenche un nouveau, rebuild ou pas), pendant une fenêtre
  // large de 400ms — le temps que grandissement + fondu enchaîné soient
  // bien terminés.
  void _measureSheetHeight({int framesLeft = 24}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = _sheetKey.currentContext?.size?.height;
      if (h != null &&
          (_sheetHeight == null || (h - _sheetHeight!).abs() > 0.5)) {
        setState(() => _sheetHeight = h);
      }
      if (framesLeft > 0) {
        _measureSheetHeight(framesLeft: framesLeft - 1);
      }
    });
  }

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
  // Hauteur estimée du panneau du bas, pour cadrer la caméra au-dessus —
  // Hauteur mesurée du panneau une fois rendu (voir _sheetHeight) ; avant la
  // toute première mesure (premier frame), on retombe sur l'ancienne
  // estimation à 62% de l'écran — plafond du panneau, voir le Container plus
  // bas (BoxConstraints maxHeight). Même principe que DEM Pro (_panelHeight,
  // dem_pro_batch_create_screen.dart), qui reste sur l'estimation fixe.
  double get _estimatedPanelHeight =>
      _sheetHeight ?? MediaQuery.sizeOf(context).height * 0.62;

  // Centre la caméra sur [pos] en la décalant vers le SUD d'une distance
  // équivalente à la moitié de la hauteur du panneau (convertie en degrés
  // via la résolution Mercator au zoom utilisé) — [pos] apparaît alors plus
  // au nord que le centre de l'écran, donc visible au-dessus du panneau au
  // lieu d'être caché dessous. Même technique que Livraison simple/Express
  // et DEM Pro.
  void _centerMapVisible(LatLng pos, {double zoom = 14, double tilt = 30}) {
    final panelH = _estimatedPanelHeight;
    final metersPerPixel =
        156543.03392 * cos(pos.latitude * pi / 180) / pow(2, zoom);
    final latShift = (panelH / 2) * metersPerPixel / 111320.0;
    final adjusted = LatLng(pos.latitude - latShift, pos.longitude);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: adjusted, zoom: zoom, tilt: tilt),
      ),
    );
  }

  Future<void> _fetchGpsInit() async {
    setState(() => _loadingGps = true);
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos != null && mounted) {
        final ll = LatLng(pos.latitude, pos.longitude);
        _centerMapVisible(ll);
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
        final fav = await pickFavoriteAddress(
          context,
          favorites: _favorites,
          forPickup: field == 'pickup',
        );
        if (fav == null || !mounted) return;
        setState(() => _activeField = field);
        _applyFavorite(fav);
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
    // La transition visuelle entre étapes est gérée par AnimatedSwitcher/
    // AnimatedSize (voir build()) — plus besoin d'un PageController.
    setState(() => _step = step);
  }

  // Contenu de l'étape courante — remplace les 4 pages du PageView. La Key
  // distincte par étape est ce qui déclenche la transition d'AnimatedSwitcher
  // (sans elle, passer de _TrajetStep à _ExpediteurStep serait déjà détecté
  // via le runtimeType différent, mais une Key explicite est plus robuste).
  Widget _buildStepContent() {
    final Widget child;
    switch (_step) {
      case 0:
        child = _TrajetStep(
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
          onClearStop: _clearStop,
          onNext: () => _goStep(1),
          canNext: _readyForEstimate,
        );
      case 1:
        child = _ExpediteurStep(
          nameCtrl: _senderNameCtrl,
          phoneCtrl: _senderPhoneCtrl,
          onPickContact: () => pickContact(
            context,
            nameCtrl: _senderNameCtrl,
            phoneCtrl: _senderPhoneCtrl,
          ),
          onPickMe: () {
            _fillMe(_senderNameCtrl, _senderPhoneCtrl);
            if (_senderPhoneCtrl.text.length >= 9) _goStep(2);
          },
          onNext: () {
            if (!_validatePhone(context, _senderPhoneCtrl, 'expéditeur')) {
              return;
            }
            _goStep(2);
          },
        );
      case 2:
        child = _DestinatairesStep(
          stops: _stops,
          onNext: () {
            // Le numéro de chaque destinataire est désormais obligatoire —
            // sans lui, le livreur n'a aucun moyen de le joindre à
            // l'arrivée (voir _validatePhone, même règle que l'expéditeur).
            for (var i = 0; i < _stops.length; i++) {
              if (!_validatePhone(
                context,
                _stops[i].receiverPhoneCtrl,
                'destinataire — arrêt ${i + 1}',
              )) {
                return;
              }
            }
            _goStep(3);
          },
        );
      default:
        child = _ResumeStep(
          pickupLabel: _pickupCtrl.text,
          stops: _stops,
          estimate: _estimate,
          estimating: _estimating,
          error: _estimateError,
          ready: _readyForEstimate,
          submitting: _submitting,
          onEditTrajet: () => _goStep(0),
          onSubmit: _submit,
        );
    }
    return KeyedSubtree(key: ValueKey(_step), child: child);
  }

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  // Un padding uniforme (72px) ne suffisait pas à garder tous les points
  // visibles au-dessus du panneau, qui occupe 62% de l'écran — on étend
  // artificiellement la borne sud, proportionnellement à la part d'écran
  // cachée, même technique que Livraison simple/Express et DEM Pro
  // (_fitBoundsVisible).
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
    final south = lats.reduce((a, b) => a < b ? a : b);
    final north = lats.reduce((a, b) => a > b ? a : b);
    final west = lngs.reduce((a, b) => a < b ? a : b);
    final east = lngs.reduce((a, b) => a > b ? a : b);

    final screenH = MediaQuery.sizeOf(context).height;
    final panelH = _estimatedPanelHeight;
    final hiddenFrac = (panelH / screenH).clamp(0.05, 0.85);
    final visibleFrac = (1 - hiddenFrac).clamp(0.15, 0.95);
    final latSpan = (north - south).clamp(0.0015, 1.0);
    final extraSouth = latSpan * (hiddenFrac / visibleFrac);

    final bounds = LatLngBounds(
      southwest: LatLng(south - extraSouth, west),
      northeast: LatLng(north, east),
    );
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
  }

  void _addStop() {
    if (_stops.length >= _kMaxStops) return;
    final entry = _StopEntry();
    setState(() => _stops.add(entry));
    _attachFocusListener(_stops.length - 1);
  }

  // Vide un arrêt (bouton "X" du champ) — jusqu'ici fait inline dans
  // _StopCard sans setState(), donc le TextField se vidait (le
  // TextEditingController notifie tout seul) mais la carte gardait le
  // marqueur et "Suivant" son ancien état, jusqu'au prochain rebuild
  // déclenché par autre chose. Voir onPickupClear ci-dessus pour le
  // pendant côté collecte, qui lui faisait déjà ça correctement.
  void _clearStop(int index) {
    setState(() {
      _stops[index].addressCtrl.clear();
      _stops[index].lat = null;
      _stops[index].lng = null;
      _stops[index].manualEntry = false;
      _estimate = null;
    });
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
      // Écran de recherche (radar + motos fictives sur la carte) au lieu
      // d'aller directement sur le détail — même expérience que la
      // livraison Simple/Express pendant la recherche d'un livreur.
      context.pushReplacement('/orders/batch/confirmation', extra: batch);
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _measureSheetHeight();
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
                onReset: () {
                  if (_step == 0) return;
                  FocusScope.of(context).unfocus();
                  _goStep(0);
                },
              ),
            ),
          ),
          // Recentrage seul ici désormais — le bouton retour qui
          // l'accompagnait vit maintenant au-dessus du panneau (voir plus
          // bas), à cheval sur son bord haut, même position que DEM Pro. Le
          // mode nuit de la carte a lui migré vers Réglages (préférence
          // globale, voir mapNightProvider).
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            right: 16,
            bottom: _estimatedPanelHeight + 16,
            child: FloatingMapButton(
              icon: _loadingGps ? null : Icons.my_location,
              loading: _loadingGps,
              onTap: _fetchGpsInit,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              key: _sheetKey,
              width: double.infinity,
              // Plafond de sécurité — le panneau s'adapte désormais au
              // contenu de l'étape affichée (voir AnimatedSize plus bas) et
              // ne demande donc plus systématiquement ces 62% ; ça reste la
              // limite haute pour ne jamais déborder de l'écran (ex : 3
              // arrêts sur un petit device, voir _DestinatairesStep).
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
                          // Un tap dans une zone vide referme le clavier —
                          // même comportement que Livraison simple/Express
                          // et DEM Pro.
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => FocusScope.of(context).unfocus(),
                              // AnimatedSize + AnimatedSwitcher à la place du
                              // PageView : celui-ci forçait TOUTES les étapes
                              // à la même hauteur fixe (62% d'écran), d'où le
                              // vide sous le bouton dès qu'une étape était
                              // plus courte que la plus haute. Le swipe était
                              // déjà désactivé (NeverScrollableScrollPhysics)
                              // — la navigation reste 100% par boutons, donc
                              // rien ne dépendait du PageController lui-même.
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                        opacity: anim,
                                        child: child,
                                      ),
                                  child: _buildStepContent(),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── RETOUR flottant — même niveau que le bouton de recentrage ───────
          // Placé APRÈS (donc AU-DESSUS, z-order) le panneau — sinon celui-ci
          // se dessine par-dessus et cache le bouton. La logique "reculer
          // d'une étape" est désormais exclusive à ce bouton (le header ne
          // fait plus que "retour à zéro", voir onReset).
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 16,
            bottom: _estimatedPanelHeight + 16,
            child: FloatingBackButton(
              onTap: () {
                if (_step > 0) {
                  _goStep(_step - 1);
                } else {
                  context.pop();
                }
              },
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
  final ValueChanged<int> onClearStop;
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
    required this.onClearStop,
    required this.onNext,
    required this.canNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        // min : sans ça, ce Column (comme les 3 autres étapes) remplit
        // systématiquement toute la hauteur allouée par AnimatedSize/
        // Flexible même quand son contenu est plus court — le vide ne
        // disparaît pas, il se contente de changer de forme. C'est ce
        // réglage, sur les 4 étapes, qui fait vraiment fonctionner le
        // panneau à hauteur adaptative (voir build() dans l'écran parent).
        mainAxisSize: MainAxisSize.min,
        children: [
          // SingleChildScrollView simple, sans Flexible — un Flexible ici
          // empêchait AnimatedSize (voir build() de l'écran parent) de
          // détecter la vraie hauteur du contenu : Flexible s'adapte à
          // l'espace qu'on lui donne plutôt que de réclamer ce dont il a
          // réellement besoin, donc AnimatedSize se figeait sur une hauteur
          // trop courte et le bas du contenu restait inaccessible sans
          // scroller. Même pattern que l'étape Expéditeur (jamais eu ce
          // problème). Le plafond de sécurité à 62% de l'écran reste géré
          // plus haut (Container maxHeight, voir build()).
          SingleChildScrollView(
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
                    onClear: () => onClearStop(i),
                    active: activeField == i,
                  ),
                  if (activeField == i && (suggestions.isNotEmpty || searching))
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
                          const Icon(Icons.add, color: Colors.white, size: 18),
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
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Suivant — Expéditeur',
            trailingIcon: Icons.arrow_forward,
            onTap: canNext ? onNext : null,
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
  final VoidCallback onClear;
  const _StopCard({
    required this.index,
    required this.entry,
    required this.canRemove,
    required this.active,
    required this.onRemove,
    required this.onQueryChanged,
    required this.onTap,
    required this.onClear,
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
            // Délègue au parent (setState) — voir _clearStop dans
            // _BatchCreateScreenState. Muter `entry` ici sans setState
            // laissait la carte et le bouton "Suivant" avec leur ancien
            // état jusqu'au prochain rebuild déclenché par autre chose.
            onClear: onClear,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Veuillez renseigner les informations de l\'expéditeur',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Même astuce que Destinataires (voir plus bas) et Livraison
          // Simple/Express — cohérence entre les flux.
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Astuce : ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.70),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'sélectionnez un contact pour gagner du temps',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Pas d'Expanded ici (contrairement à _DestinatairesStep, qui peut
          // avoir 2-3 cartes et déborder) — une seule carte, taille fixe.
          // Avec Expanded, ce contenu était étiré pour remplir toute la
          // hauteur du panneau (62% de l'écran), poussant le bouton tout en
          // bas et laissant un grand vide entre la carte et "Suivant".
          SingleChildScrollView(
            child: ContactMiniField(
              label: 'Expéditeur',
              dotColor: AppColors.success,
              nameCtrl: nameCtrl,
              phoneCtrl: phoneCtrl,
              onPick: onPickContact,
              onPickMe: onPickMe,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            // Plus "(optionnel)" — le numéro du destinataire est désormais
            // obligatoire (voir onNext dans _buildStepContent) : sans lui,
            // le livreur n'a aucun moyen de joindre le destinataire à
            // l'arrivée.
            child: Text(
              'Veuillez renseigner les informations des destinataires',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Astuce : ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.70),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'sélectionnez un contact pour gagner du temps',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // SingleChildScrollView simple, sans Flexible — voir le
          // commentaire équivalent dans _TrajetStep : Flexible empêchait
          // AnimatedSize de détecter la vraie hauteur du contenu.
          SingleChildScrollView(
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // SingleChildScrollView simple, sans Flexible — voir le
          // commentaire équivalent dans _TrajetStep : Flexible empêchait
          // AnimatedSize de détecter la vraie hauteur du contenu.
          SingleChildScrollView(
            child: Column(
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
          const SizedBox(height: 12),
          PrimaryButton(
            label: estimate != null
                ? 'Confirmer — ${formatFcfa((estimate!['total'] as num).toInt())}'
                : 'Confirmer la tournée',
            onTap: (estimate != null && !submitting) ? onSubmit : null,
            loading: submitting,
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
        // Même carte sombre que le trajet juste au-dessus (AppColors.card)
        // plutôt qu'un lavis vert sombre — le vert `_kBatchAccent` (assez
        // foncé) sur son propre fond teinté de la même couleur écrasait le
        // contraste et jurait avec le reste de l'écran, tout en bleu.
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.successBright,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Vous économisez ${formatFcfa(discount)} en groupant vos livraisons',
                    style: const TextStyle(
                      // successBright (vert clair) au lieu de _kBatchAccent —
                      // lisible sur la carte sombre, au lieu du vert foncé
                      // sur fond vert foncé d'avant.
                      color: AppColors.successBright,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
