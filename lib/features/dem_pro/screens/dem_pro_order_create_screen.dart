import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/services/places_autocomplete_service.dart';
import '../../../core/storage/dem_pro_draft_storage.dart';
import '../../../core/storage/promo_code_storage.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../core/utils/senegal_phone.dart';
import '../../../shared/widgets/place_suggestions_list.dart';
import '../../deliveries/data/orders_repository.dart';
import '../../home_driver/navigation/directions_service.dart';
import '../../home_driver/navigation/navigation_service.dart';
import '../data/dem_pro_repository.dart';
import '../theme/dem_pro_colors.dart';
import '../utils/dem_pro_format.dart';
import '../theme/dem_pro_text.dart';

// ─────────────────────────────────────────────────────────────────────────────

const _dakar = LatLng(14.6937, -17.4441);

const _placeSuggestionsColors = PlaceSuggestionsColors(
  background: DemProColors.bg3,
  border: DemProColors.bg4,
  divider: DemProColors.bg4,
  iconBg: DemProColors.bg4,
  icon: DemProColors.accent,
  mainText: DemProColors.text,
  secondaryText: DemProColors.muted,
  accent: DemProColors.accent,
);

const _packageTypes = [
  ('documents', 'Documents',   Icons.description_outlined,  'Enveloppes, contrats, factures'),
  ('small',     'Petit colis', Icons.inventory_2_outlined,   'Léger — moins de 5 kg'),
  ('large',     'Grand colis', Icons.view_in_ar_outlined,    'Lourd ou encombrant'),
];

const _stepMeta = [
  (Icons.flag_outlined,           'Destination',  '1/3'),
  (Icons.inventory_2_outlined,    'Colis',        '2/3'),
  (Icons.check_circle_outline,    'Confirmation', '3/3'),
];

// ─────────────────────────────────────────────────────────────────────────────

class _Article {
  final nameCtrl = TextEditingController();
  final qtyCtrl  = TextEditingController(text: '1');
  final priceCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class DemProOrderCreateScreen extends StatefulWidget {
  final bool scheduled;
  final Map<String, dynamic>? reorderFrom;
  /// Demande soumise par un client final via le lien de commande public
  /// (dem.sn/commander/:merchantId) — préremplit destinataire/adresse texte,
  /// mais jamais les coordonnées (le client final n'en fournit pas), donc le
  /// commerçant doit toujours positionner le point de livraison lui-même
  /// avant de pouvoir avancer. Une fois la commande créée, la demande est
  /// marquée confirmée côté serveur (voir `_submit`).
  final Map<String, dynamic>? fromOrderRequest;
  const DemProOrderCreateScreen({super.key, this.scheduled = false, this.reorderFrom, this.fromOrderRequest});
  @override
  State<DemProOrderCreateScreen> createState() => _State();
}

class _State extends State<DemProOrderCreateScreen> {
  final _ordersRepo = OrdersRepository();
  final _proRepo    = DemProRepository(ApiClient.dio);

  // ── Navigation ──────────────────────────────────────────────────────────
  int _step = 0; // 0=Destination, 1=Colis, 2=Confirmation

  // ── Map ─────────────────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  LatLng _cameraPos   = _dakar;
  bool _isMapPlacement = false;
  bool _placingPickup  = false; // false = placing delivery
  final _sheetCtrl = DraggableScrollableController();

  // ── Départ (auto-rempli depuis ProAddress défaut) ────────────────────────
  List<Map<String, dynamic>> _proAddresses = [];
  Map<String, dynamic>? _selectedProAddr;
  double? _pickupLat, _pickupLng;
  String  _pickupAddress = '';
  bool    _loadingGps    = false;

  // ── Étape 1 — Destination ───────────────────────────────────────────────
  final _recipientNameCtrl  = TextEditingController();
  final _recipientPhoneCtrl = TextEditingController();
  final _landmarkCtrl       = TextEditingController();
  final _addressSearchCtrl  = TextEditingController();
  double? _deliveryLat, _deliveryLng;
  String  _deliveryAddress  = '';
  bool    _searchingAddress = false;
  String? _searchError;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _searchDebounce;
  final _publicDio = Dio();
  late final _placesService = PlacesAutocompleteService(_publicDio);
  String? _sessionToken;

  // ── Destinations récentes ────────────────────────────────────────────────
  List<Map<String, dynamic>> _recentDestinations = [];

  // ── Brouillon ────────────────────────────────────────────────────────────
  Timer? _draftSaveDebounce;

  // ── Étape 2 — Colis ─────────────────────────────────────────────────────
  String _packageType = 'small';
  final  _instructionsCtrl = TextEditingController();
  bool   _isFragile        = false;
  late bool _isScheduled = widget.scheduled;
  DateTime? _scheduledAt;

  // ── Route polyline ────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];

  // ── Articles ───────────────────────────────────────────────────────────
  final List<_Article> _articles = [_Article()];

  // ── Paiement ───────────────────────────────────────────────────────────
  String _paymentMode = 'merchant'; // 'merchant' | 'cod'

  // ── Étape 3 — Confirmation ──────────────────────────────────────────────
  Map<String, dynamic>? _estimate;
  bool _loadingEstimate = false;
  bool _submitting      = false;
  bool _geocoding       = false;

  // ── Promotion (voir promo.service.js côté serveur) ──────────────────────
  double? _discountAmount;
  String? _promoLabel;
  String? _promoError;
  bool _checkingPromo = false;
  final _promoCodeCtrl = TextEditingController();

  // ── Depuis une demande reçue (lien de commande public) ───────────────────
  String? _fromRequestId;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _loadProAddresses();
    _loadRecentDestinations();
    if (widget.fromOrderRequest != null) {
      _applyOrderRequest(widget.fromOrderRequest!);
    } else if (widget.reorderFrom != null) {
      _applyReorder(widget.reorderFrom!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowDraftPrompt());
    }
    if (widget.scheduled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickScheduleDate());
    }
  }

  /// Préremplit destinataire/adresse (texte) + repère/instructions depuis une
  /// demande reçue via la page publique. Ne fournit jamais de coordonnées —
  /// le client final n'en donne pas — donc `_deliveryLat/_deliveryLng`
  /// restent `null` et le commerçant doit positionner le point de livraison
  /// lui-même (recherche ou carte) avant de pouvoir avancer à l'étape 2.
  void _applyOrderRequest(Map<String, dynamic> request) {
    _fromRequestId = request['id'] as String?;
    _deliveryAddress = request['deliveryAddress'] as String? ?? '';
    _addressSearchCtrl.text = _deliveryAddress;

    final name  = request['customerName']  as String?;
    if (name != null && name.isNotEmpty) _recipientNameCtrl.text = name;

    final rawPhone = request['customerPhone'] as String?;
    if (rawPhone != null && rawPhone.isNotEmpty) {
      var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.startsWith('221') && digits.length > 9) digits = digits.substring(digits.length - 9);
      _recipientPhoneCtrl.text = digits.length > 9 ? digits.substring(digits.length - 9) : digits;
    }

    final landmark = request['landmark'] as String?;
    if (landmark != null && landmark.isNotEmpty) _landmarkCtrl.text = landmark;

    final notes = request['notes'] as String?;
    if (notes != null && notes.isNotEmpty) _instructionsCtrl.text = notes;
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _sheetCtrl.dispose();
    _searchDebounce?.cancel();
    _draftSaveDebounce?.cancel();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _landmarkCtrl.dispose();
    _addressSearchCtrl.dispose();
    _instructionsCtrl.dispose();
    _promoCodeCtrl.dispose();
    for (final a in _articles) { a.dispose(); }
    super.dispose();
  }

  // ── Destinations récentes ────────────────────────────────────────────────

  Future<void> _loadRecentDestinations() async {
    try {
      final list = await _proRepo.getRecentDestinations();
      if (mounted) setState(() => _recentDestinations = list);
    } catch (_) {}
  }

  void _applyRecentDestination(Map<String, dynamic> dest) {
    final lat = (dest['lat'] as num?)?.toDouble();
    final lng = (dest['lng'] as num?)?.toDouble();
    final address = dest['address'] as String? ?? '';
    if (lat == null || lng == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _deliveryLat = lat;
      _deliveryLng = lng;
      _deliveryAddress = address;
      _addressSearchCtrl.text = address;
      final name  = dest['receiverName']  as String?;
      final phone = dest['receiverPhone'] as String?;
      if (name != null && name.isNotEmpty) _recipientNameCtrl.text = name;
      if (phone != null && phone.isNotEmpty) {
        _recipientPhoneCtrl.text = phone.replaceFirst('+221', '');
      }
    });
    _recenterMap();
    _scheduleDraftSave();
  }

  // ── Recommander (reorder) ────────────────────────────────────────────────

  void _applyReorder(Map<String, dynamic> order) {
    final lat = (order['deliveryLatitude']  as num?)?.toDouble();
    final lng = (order['deliveryLongitude'] as num?)?.toDouble();
    _deliveryAddress = order['deliveryAddress'] as String? ?? '';
    _addressSearchCtrl.text = _deliveryAddress;
    if (lat != null && lng != null) { _deliveryLat = lat; _deliveryLng = lng; }
    final name  = order['receiverName']  as String?;
    final phone = order['receiverPhone'] as String?;
    if (name  != null && name.isNotEmpty)  _recipientNameCtrl.text  = name;
    if (phone != null && phone.isNotEmpty) _recipientPhoneCtrl.text = phone.replaceFirst('+221', '');

    final items = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isNotEmpty) {
      for (final a in _articles) { a.dispose(); }
      _articles.clear();
      for (final it in items) {
        final a = _Article();
        a.nameCtrl.text  = it['name'] as String? ?? '';
        a.qtyCtrl.text   = '${it['quantity'] ?? 1}';
        if (it['price'] != null) a.priceCtrl.text = '${it['price']}';
        _articles.add(a);
      }
    }
  }

  // ── Brouillon ─────────────────────────────────────────────────────────────

  Map<String, dynamic> _draftSnapshot() => {
    'deliveryLat': _deliveryLat,
    'deliveryLng': _deliveryLng,
    'deliveryAddress': _deliveryAddress,
    'recipientName': _recipientNameCtrl.text,
    'recipientPhone': _recipientPhoneCtrl.text,
    'landmark': _landmarkCtrl.text,
    'packageType': _packageType,
    'isFragile': _isFragile,
    'instructions': _instructionsCtrl.text,
    'paymentMode': _paymentMode,
    'articles': _articles
        .where((a) => a.nameCtrl.text.trim().isNotEmpty)
        .map((a) => {'name': a.nameCtrl.text, 'qty': a.qtyCtrl.text, 'price': a.priceCtrl.text})
        .toList(),
    'savedAt': DateTime.now().toIso8601String(),
  };

  void _scheduleDraftSave() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (_deliveryLat == null && _recipientPhoneCtrl.text.isEmpty) return;
      DemProDraftStorage.saveOrderDraft(_draftSnapshot());
    });
  }

  void _applyDraft(Map<String, dynamic> draft) {
    setState(() {
      _deliveryLat     = (draft['deliveryLat'] as num?)?.toDouble();
      _deliveryLng     = (draft['deliveryLng'] as num?)?.toDouble();
      _deliveryAddress = draft['deliveryAddress'] as String? ?? '';
      _addressSearchCtrl.text  = _deliveryAddress;
      _recipientNameCtrl.text  = draft['recipientName']  as String? ?? '';
      _recipientPhoneCtrl.text = draft['recipientPhone'] as String? ?? '';
      _landmarkCtrl.text       = draft['landmark']       as String? ?? '';
      _packageType             = draft['packageType']    as String? ?? 'small';
      _isFragile               = draft['isFragile']      as bool?   ?? false;
      _instructionsCtrl.text   = draft['instructions']   as String? ?? '';
      _paymentMode             = draft['paymentMode']    as String? ?? 'merchant';
      final articles = (draft['articles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (articles.isNotEmpty) {
        for (final a in _articles) { a.dispose(); }
        _articles.clear();
        for (final it in articles) {
          final a = _Article();
          a.nameCtrl.text  = it['name']  as String? ?? '';
          a.qtyCtrl.text   = it['qty']   as String? ?? '1';
          a.priceCtrl.text = it['price'] as String? ?? '';
          _articles.add(a);
        }
      }
    });
    _recenterMap();
  }

  Future<void> _maybeShowDraftPrompt() async {
    final draft = await DemProDraftStorage.getOrderDraft();
    if (draft == null || !mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _DraftResumeSheet(
        savedAt: draft['savedAt'] as String?,
        onResume: () { Navigator.pop(context); _applyDraft(draft); },
        onDiscard: () { Navigator.pop(context); DemProDraftStorage.clearOrderDraft(); },
      ),
    );
  }

  // ── Map style ────────────────────────────────────────────────────────────

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style_waze.json');
    if (mounted) setState(() => _mapStyle = style);
  }

  void _centerMap(LatLng pos) => _mapCtrl?.animateCamera(
    CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 15, tilt: 20)),
  );

  /// Centre la carte sur [pos] de sorte que le point soit visible dans la
  /// zone haute (au-dessus du panneau), et non caché derrière.
  /// Décale la cible caméra vers le SUD d'une distance égale à la moitié de
  /// la hauteur du panneau (convertie en degrés via la résolution Mercator
  /// au zoom utilisé) — [pos] apparaît alors plus au nord que le centre de
  /// l'écran, donc visuellement plus haut, au milieu de la zone visible.
  void _centerMapVisible(LatLng pos, {double zoom = 15}) {
    final panelH = _panelHeight + MediaQuery.of(context).viewPadding.bottom;
    final metersPerPixel = 156543.03392 * math.cos(pos.latitude * math.pi / 180) / math.pow(2, zoom);
    final latShift = (panelH / 2) * metersPerPixel / 111320.0;
    final adjusted = LatLng(pos.latitude - latShift, pos.longitude);
    _mapCtrl?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: adjusted, zoom: zoom, tilt: 20)),
    );
  }

  // ── ProAddresses — auto-remplissage du départ ────────────────────────────

  Future<void> _loadProAddresses() async {
    try {
      final list = await _proRepo.getAddresses();
      if (!mounted) return;
      setState(() => _proAddresses = list);
      // Auto-apply: adresse par défaut, sinon la première
      final def = list.firstWhere(
        (a) => a['isDefault'] == true,
        orElse: () => list.isEmpty ? {} : list.first,
      );
      if (def.isNotEmpty) {
        _applyProAddress(def);
      } else {
        _fetchGps(); // pas d'adresse pro → GPS en fallback
      }
    } catch (_) {
      _fetchGps();
    }
  }

  void _applyProAddress(Map<String, dynamic> addr) {
    final lat = (addr['lat'] as num?)?.toDouble();
    final lng = (addr['lng'] as num?)?.toDouble();
    final address = addr['address'] as String? ?? '';
    setState(() {
      _selectedProAddr = addr;
      _pickupAddress   = address;
      if (lat != null && lng != null) { _pickupLat = lat; _pickupLng = lng; }
    });
    if (lat != null && lng != null) _recenterMap();
    if (lat == null || lng == null) {
      _geocodePickupAddress(address);
    } else if (_step == 2) {
      _fetchEstimate();
      _fetchRoute();
    }
  }

  Future<void> _geocodePickupAddress(String address) async {
    if (address.isEmpty) { _fetchGps(); return; }
    try {
      final locations = await geo.locationFromAddress('$address, Dakar, Sénégal')
          .timeout(const Duration(seconds: 6));
      if (locations.isEmpty || !mounted) return;
      final loc = locations.first;
      setState(() {
        _pickupLat = loc.latitude;
        _pickupLng = loc.longitude;
      });
      _recenterMap();
      if (_step == 2) { _fetchEstimate(); _fetchRoute(); }
    } catch (_) {
      _fetchGps();
    }
  }

  // ── GPS ──────────────────────────────────────────────────────────────────

  Future<void> _fetchGps() async {
    setState(() { _loadingGps = true; _selectedProAddr = null; });
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (!mounted) return;
      if (pos == null) {
        showDemToast(context, 'Activez la localisation pour continuer', isError: true);
        return;
      }
      final ll = LatLng(pos.latitude, pos.longitude);
      _pickupLat = ll.latitude; _pickupLng = ll.longitude;
      _recenterMap();
      _reverseGeocode(ll, forPickup: true);
    } catch (_) {
      if (mounted) showDemToast(context, 'GPS indisponible', isError: true);
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  // ── Map placement ────────────────────────────────────────────────────────

  void _enterMapPlacement({required bool forPickup}) {
    setState(() { _isMapPlacement = true; _placingPickup = forPickup; });
    if (forPickup  && _pickupLat   != null) { _centerMap(LatLng(_pickupLat!,   _pickupLng!)); }
    if (!forPickup && _deliveryLat != null) { _centerMap(LatLng(_deliveryLat!, _deliveryLng!)); }
  }

  Future<void> _confirmPlacement() async {
    setState(() => _geocoding = true);
    final pos = _cameraPos;
    if (_placingPickup) {
      _pickupLat = pos.latitude; _pickupLng = pos.longitude;
      _selectedProAddr = null;
      await _reverseGeocode(pos, forPickup: true);
    } else {
      _deliveryLat = pos.latitude; _deliveryLng = pos.longitude;
      await _reverseGeocode(pos, forPickup: false);
    }
    if (mounted) {
      setState(() { _isMapPlacement = false; _geocoding = false; });
      if (_step == 2) {
        _fetchEstimate();
        _fetchRoute();
      } else {
        _recenterMap();
      }
      _scheduleDraftSave();
    }
  }

  void _onAddressChanged(String query) {
    _searchDebounce?.cancel();
    setState(() {}); // reflète immédiatement l'état vide/non-vide du champ (destinations récentes)
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _sessionToken ??= PlacesAutocompleteService.newSessionToken();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() { _searchingAddress = true; _searchError = null; });
      try {
        final preds = await _placesService.autocomplete(query: query, sessionToken: _sessionToken!);
        if (mounted) setState(() { _suggestions = preds; _searchingAddress = false; });
      } catch (e) {
        if (mounted) setState(() { _searchingAddress = false; _searchError = friendlyError(e); });
      }
    });
  }

  void _retryAddressSearch() => _onAddressChanged(_addressSearchCtrl.text);

  Future<void> _forwardGeocode(String query) async {
    if (query.trim().length < 3) return;
    FocusScope.of(context).unfocus();
    setState(() { _suggestions = []; _searchingAddress = true; });
    try {
      final locations = await geo.locationFromAddress('$query, Dakar, Sénégal')
          .timeout(const Duration(seconds: 6));
      if (locations.isEmpty || !mounted) return;
      final loc = locations.first;
      setState(() {
        _deliveryLat = loc.latitude;
        _deliveryLng = loc.longitude;
        _deliveryAddress = query.trim();
        _addressSearchCtrl.text = query.trim();
      });
      _recenterMap();
      _scheduleDraftSave();
    } catch (_) {
      if (mounted) showDemToast(context, 'Adresse introuvable', isError: true);
    } finally {
      if (mounted) setState(() => _searchingAddress = false);
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = []);
    final token = _sessionToken ?? PlacesAutocompleteService.newSessionToken();
    try {
      final result = await _placesService.details(placeId: placeId, sessionToken: token);
      if (result != null) {
        final loc = result['geometry']['location'];
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final name = (place['structured_formatting']?['main_text'] as String?)
            ?? place['description'] as String? ?? '';
        setState(() {
          _deliveryLat = lat;
          _deliveryLng = lng;
          _deliveryAddress = name;
          _addressSearchCtrl.text = name;
        });
        _recenterMap();
        _scheduleDraftSave();
      }
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      _sessionToken = null; // fin de session — la prochaine recherche en génère une nouvelle
    }
  }

  Future<void> _reverseGeocode(LatLng pos, {required bool forPickup}) async {
    try {
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude)
          .timeout(const Duration(seconds: 5));
      if (marks.isEmpty || !mounted) return;
      final p      = marks.first;
      final street = p.street ?? p.name ?? '';
      final local  = p.subLocality ?? p.locality ?? '';
      final addr   = street.isNotEmpty ? '$street, $local' : local;
      final result = addr.isNotEmpty ? addr
          : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      setState(() {
        if (forPickup) { _pickupAddress   = result; }
        else           { _deliveryAddress = result; }
      });
    } catch (_) {}
  }

  // ── Estimate & submit ────────────────────────────────────────────────────

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    const deg2rad = 3.141592653589793 / 180;
    final dLat = (lat2 - lat1) * deg2rad;
    final dLng = (lng2 - lng1) * deg2rad;
    final lat1R = lat1 * deg2rad;
    final lat2R = lat2 * deg2rad;
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final a = sinDLat * sinDLat + math.cos(lat1R) * math.cos(lat2R) * sinDLng * sinDLng;
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Map<String, dynamic> _localEstimate() {
    if (_pickupLat == null || _deliveryLat == null) return {};
    final distKm = _haversineKm(_pickupLat!, _pickupLng!, _deliveryLat!, _deliveryLng!);
    final raw = 600 + distKm * 250;
    final rounded = (raw / 50).round() * 50;
    final price = rounded < 900 ? 900 : rounded;
    return {
      'price': price,
      'demFee': 0,
      'totalClient': price,
      'distanceKm': (distKm * 10).round() / 10,
    };
  }

  Future<void> _fetchEstimate() async {
    if (_pickupLat == null || _deliveryLat == null) return;
    if (mounted) setState(() { _loadingEstimate = true; _estimate = null; });
    try {
      final est = await _ordersRepo.getEstimate(
        pickupLat: _pickupLat!,    pickupLng: _pickupLng!,
        deliveryLat: _deliveryLat!, deliveryLng: _deliveryLng!,
        orderType: 'DELIVERY',
      ).timeout(const Duration(seconds: 10));
      debugPrint('[ESTIMATE] result: $est');
      if (mounted) setState(() { _estimate = est; _loadingEstimate = false; });
      _checkAutoPromo();
    } catch (e) {
      debugPrint('[ESTIMATE] error: $e — using local fallback');
      if (mounted) setState(() { _estimate = _localEstimate(); _loadingEstimate = false; });
    }
  }

  // Priorité 1 : un code enregistré depuis l'écran dédié "Code promo" (voir
  // dem_pro_promo_code_screen.dart) — pré-rempli et validé silencieusement.
  // Priorité 2 (sinon) : campagne auto-appliquée sans code. Aucune erreur
  // affichée si rien ne s'applique (cas normal).
  Future<void> _checkAutoPromo() async {
    final price = (_estimate?['price'] as num?)?.toInt();
    if (price == null) return;
    final demFee = (_estimate?['demFee'] as num?)?.toInt() ?? 0;

    final savedCode = await PromoCodeStorage.get();
    if (savedCode != null) {
      try {
        final result = await _ordersRepo.getPromoPreview(price: price, demFee: demFee, code: savedCode);
        if (!mounted) return;
        if (result != null) {
          setState(() {
            _promoCodeCtrl.text = savedCode;
            _discountAmount = (result['discountAmount'] as num?)?.toDouble();
            _promoLabel     = result['promoCode'] as String?;
          });
          return;
        }
      } catch (_) {
        // Ne s'applique pas à CETTE commande précise (ex: minimum non
        // atteint) — on ne l'efface pas ici, voir dem_pro_promo_code_screen.dart.
      }
    }

    try {
      final result = await _ordersRepo.getPromoPreview(price: price, demFee: demFee);
      if (!mounted || result == null) return;
      setState(() {
        _discountAmount = (result['discountAmount'] as num?)?.toDouble();
        _promoLabel     = result['promoCode'] as String?;
      });
    } catch (_) {} // jamais bloquant
  }

  Future<void> _applyPromoCode() async {
    final code  = _promoCodeCtrl.text.trim();
    final price = (_estimate?['price'] as num?)?.toInt();
    if (code.isEmpty || price == null) return;
    final demFee = (_estimate?['demFee'] as num?)?.toInt() ?? 0;
    setState(() { _checkingPromo = true; _promoError = null; });
    try {
      final result = await _ordersRepo.getPromoPreview(price: price, demFee: demFee, code: code);
      if (!mounted) return;
      setState(() {
        _discountAmount = (result?['discountAmount'] as num?)?.toDouble();
        _promoLabel     = result?['promoCode'] as String?;
        _checkingPromo  = false;
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_pickupLat == null || _pickupLng == null) {
      showDemToast(context, 'Position de départ introuvable. Changez le point de départ.', isError: true);
      return;
    }
    if (_deliveryLat == null || _deliveryLng == null) {
      showDemToast(context, 'Destination introuvable.', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final parts = <String>[];
      final pkg = _packageTypes.firstWhere((p) => p.$1 == _packageType);
      parts.add(pkg.$2);
      if (_isFragile) parts.add('Fragile');
      if (_instructionsCtrl.text.trim().isNotEmpty) parts.add(_instructionsCtrl.text.trim());
      if (_landmarkCtrl.text.trim().isNotEmpty) parts.add('Repère: ${_landmarkCtrl.text.trim()}');

      final items = _articles
          .where((a) => a.nameCtrl.text.trim().isNotEmpty)
          .map((a) => {
                'name': a.nameCtrl.text.trim(),
                'quantity': int.tryParse(a.qtyCtrl.text.trim()) ?? 1,
                if (a.priceCtrl.text.trim().isNotEmpty)
                  'price': int.tryParse(a.priceCtrl.text.trim()) ?? 0,
              })
          .toList();

      final order = await _ordersRepo.createOrder({
        'orderType':         'DELIVERY',
        'pickupAddress':     _pickupAddress.isNotEmpty ? _pickupAddress : '${_pickupLat!.toStringAsFixed(4)}, ${_pickupLng!.toStringAsFixed(4)}',
        'pickupLatitude':    _pickupLat,
        'pickupLongitude':   _pickupLng,
        'deliveryAddress':   _deliveryAddress.isNotEmpty ? _deliveryAddress : '${_deliveryLat!.toStringAsFixed(4)}, ${_deliveryLng!.toStringAsFixed(4)}',
        'deliveryLatitude':  _deliveryLat,
        'deliveryLongitude': _deliveryLng,
        if (_recipientNameCtrl.text.trim().isNotEmpty)  'receiverName':  _recipientNameCtrl.text.trim(),
        if (_recipientPhoneCtrl.text.trim().isNotEmpty) 'receiverPhone': '+221${_recipientPhoneCtrl.text.trim()}',
        if (parts.isNotEmpty) 'description': parts.join(' · '),
        if (_estimate?['price']  != null) 'price':  (_estimate!['price']  as num).toDouble(),
        if (_estimate?['demFee'] != null) 'demFee': (_estimate!['demFee'] as num).toDouble(),
        if (_scheduledAt != null) 'scheduledAt': _scheduledAt!.toUtc().toIso8601String(),
        'paymentMode': _paymentMode,
        if (items.isNotEmpty) 'items': items,
        // Uniquement si saisi manuellement et validé (voir _applyPromoCode) —
        // une promo auto-appliquée n'a pas besoin d'être renvoyée.
        if (_promoError == null && _promoCodeCtrl.text.trim().isNotEmpty)
          'promoCode': _promoCodeCtrl.text.trim(),
      });

      if (_selectedProAddr != null) {
        _proRepo.incrementAddressUsage(_selectedProAddr!['id'] as String);
      }

      // Ferme la boucle côté serveur — la commande vient d'être créée avec
      // succès, donc on ne bloque jamais la navigation si cet appel échoue
      // (la demande resterait juste visible en "En attente", sans impact
      // sur la commande elle-même).
      if (_fromRequestId != null) {
        final orderId = order['id'] as String?;
        if (orderId != null) {
          () async {
            try { await _proRepo.confirmOrderRequest(_fromRequestId!, orderId); } catch (_) {}
          }();
        }
      }

      DemProDraftStorage.clearOrderDraft();
      if (mounted) context.pushReplacement('/dem-pro/orders/confirmation', extra: order);
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Validation ───────────────────────────────────────────────────────────

  bool get _canAdvance => switch (_step) {
    0 => _deliveryLat != null && isValidSenegalMobile(_recipientPhoneCtrl.text.trim()),
    1 => true,
    _ => false,
  };

  String get _stepError => switch (_step) {
    0 => _deliveryLat == null
        ? 'Définissez la destination sur la carte'
        : 'Numéro mobile invalide (7X XXX XX XX)',
    _ => '',
  };

  void _next() {
    FocusScope.of(context).unfocus();
    if (!_canAdvance) { showDemToast(context, _stepError, isError: true); return; }
    if (_step == 1) {
      _fetchEstimate();
      _fetchRoute();
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) { context.pop(); return; }
    setState(() => _step--);
  }

  // ── Map markers / polyline ────────────────────────────────────────────────

  Set<Marker> get _markers {
    final m = <Marker>{};
    if (_pickupLat != null) m.add(Marker(
      markerId: const MarkerId('pickup'),
      position: LatLng(_pickupLat!, _pickupLng!),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      infoWindow: const InfoWindow(title: 'Départ'),
    ));
    if (_deliveryLat != null) m.add(Marker(
      markerId: const MarkerId('delivery'),
      position: LatLng(_deliveryLat!, _deliveryLng!),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: const InfoWindow(title: 'Destination'),
    ));
    return m;
  }

  Set<Polyline> get _polylines {
    if (_pickupLat == null || _deliveryLat == null || _step < 2) return {};
    final pts = _routePoints.isNotEmpty
        ? _routePoints
        : [LatLng(_pickupLat!, _pickupLng!), LatLng(_deliveryLat!, _deliveryLng!)];
    return {Polyline(
      polylineId: const PolylineId('route'),
      points: pts,
      color: DemProColors.accent,
      width: 4,
    )};
  }

  Future<void> _fetchRoute() async {
    if (_pickupLat == null || _deliveryLat == null) return;
    final origin = LatLng(_pickupLat!, _pickupLng!);
    final dest   = LatLng(_deliveryLat!, _deliveryLng!);
    try {
      final result = await DirectionsService.getRoute(
        origin: origin,
        destination: dest,
        apiKey: AppConfig.mapsApiKey,
      );
      if (mounted) {
        setState(() => _routePoints = result.points);
        _fitBoundsVisible([origin, dest]);
      }
    } catch (_) {}
  }

  /// Ajuste le zoom pour que tous les [points] soient visibles au-dessus du
  /// panneau du bas — étend artificiellement la borne sud proportionnellement
  /// à la part d'écran cachée par le panneau, ce qui a pour effet de remonter
  /// visuellement le cluster de points dans la portion haute de l'écran.
  void _fitBoundsVisible(List<LatLng> points) {
    if (points.isEmpty || _mapCtrl == null) return;
    if (points.length == 1) { _centerMapVisible(points.first); return; }

    var south = points.first.latitude,  north = points.first.latitude;
    var west  = points.first.longitude, east  = points.first.longitude;
    for (final p in points.skip(1)) {
      if (p.latitude  < south) south = p.latitude;
      if (p.latitude  > north) north = p.latitude;
      if (p.longitude < west)  west  = p.longitude;
      if (p.longitude > east)  east  = p.longitude;
    }

    final screenH  = MediaQuery.of(context).size.height;
    final panelH   = _panelHeight + MediaQuery.of(context).viewPadding.bottom;
    final hiddenFrac  = (panelH / screenH).clamp(0.05, 0.85);
    final visibleFrac = (1 - hiddenFrac).clamp(0.15, 0.95);
    final latSpan  = (north - south).clamp(0.0015, 1.0);
    final extraSouth = latSpan * (hiddenFrac / visibleFrac);

    final bounds = LatLngBounds(
      southwest: LatLng(south - extraSouth, west),
      northeast: LatLng(north, east),
    );
    _mapCtrl?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
  }

  /// Recadre la carte sur l'ensemble des points actuellement connus
  /// (départ et/ou destination) — à appeler après tout changement de l'un
  /// des deux, pour garder les deux visibles dès qu'ils sont définis.
  void _recenterMap() {
    final points = <LatLng>[
      if (_pickupLat != null) LatLng(_pickupLat!, _pickupLng!),
      if (_deliveryLat != null) LatLng(_deliveryLat!, _deliveryLng!),
    ];
    _fitBoundsVisible(points);
  }

  double get _panelHeight {
    final h = MediaQuery.of(context).size.height;
    return h * _sheetMax;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _back(); },
      child: Scaffold(
      backgroundColor: DemProColors.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(children: [

        // Carte
        Positioned.fill(child: GoogleMap(
          onMapCreated: (c) => _mapCtrl = c,
          style: _mapStyle,
          initialCameraPosition: CameraPosition(target: _dakar, zoom: 13),
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          markers: _isMapPlacement ? {} : _markers,
          polylines: _polylines,
          onCameraMove: (pos) => _cameraPos = pos.target,
        )),

        // Pin central
        if (_isMapPlacement)
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              _placingPickup ? Icons.inventory_2_rounded : Icons.location_on,
              color: _placingPickup ? DemProColors.warning : DemProColors.success,
              size: 40,
              shadows: const [Shadow(color: Colors.black26, blurRadius: 8)],
            ),
            const SizedBox(height: 2),
            CircleAvatar(radius: 3, backgroundColor: _placingPickup ? DemProColors.warning : DemProColors.success),
          ])),

        // Header
        if (!_isMapPlacement)
          Positioned(top: 0, left: 0, right: 0,
            child: SafeArea(child: _buildHeader())),

        // Panel bas — placement
        if (_isMapPlacement)
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(
              height: 130 + MediaQuery.of(context).viewPadding.bottom,
              decoration: BoxDecoration(
                color: DemProColors.bg2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: _buildPlacementPanel(),
            ),
          ),

        // Panel bas (infos + CTA) — remontent ensemble de façon fluide
        // au-dessus du clavier (même logique que le sheet "Changer le
        // départ") et reviennent à leur position normale à la fermeture
        // du clavier. Le CTA reste hors du panneau rétractable lui-même
        // pour ne jamais pousser la poignée hors de l'écran quand celui-ci
        // est réduit au minimum.
        if (!_isMapPlacement)
          Positioned.fill(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Stack(children: [
                DraggableScrollableSheet(
                  controller: _sheetCtrl,
                  initialChildSize: _sheetMax,
                  minChildSize: _sheetMin,
                  maxChildSize: _sheetMax,
                  snap: true,
                  snapSizes: [_sheetMin, _sheetMax],
                  builder: (context, scrollCtrl) {
                    return Container(
                      decoration: BoxDecoration(
                        color: DemProColors.bg2,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, -4))],
                      ),
                      child: _buildPanel(scrollCtrl),
                    );
                  },
                ),
                Positioned(bottom: 0, left: 0, right: 0, child: _buildNavButtons()),
              ]),
            ),
          ),
      ]),
    ),
    );
  }

  double get _sheetMin => 0.12;
  double get _sheetMax => switch (_step) {
    1 => 0.60,
    2 => 0.60,
    _ => 0.58,
  };

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
    child: Row(children: [
      IconButton(
        onPressed: _back,
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: DemProColors.bg2.withValues(alpha: 0.9), shape: BoxShape.circle),
          child: const Icon(Icons.arrow_back, color: DemProColors.text, size: 20),
        ),
      ),
      const SizedBox(width: 4),
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: DemProColors.bg2.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              _isScheduled ? 'Programmer une livraison' : 'Nouvelle livraison',
              style: DemProText.subtitle,
            ),
            const Spacer(),
            Text(_stepMeta[_step].$3, style: DemProText.caption.copyWith(color: DemProColors.accent)),
          ]),
          const SizedBox(height: 6),
          Row(children: List.generate(3, (i) => Expanded(child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 3,
              decoration: BoxDecoration(
                color: i <= _step ? DemProColors.accent : DemProColors.bg4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )))),
        ]),
      )),
    ]),
  );

  // ── Panel placement ───────────────────────────────────────────────────────

  Widget _buildPlacementPanel() => SafeArea(top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, decoration: BoxDecoration(color: DemProColors.bg4, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Text(
          _placingPickup ? 'Positionnez le point de départ' : 'Positionnez la destination',
          style: DemProText.bodyStrong,
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(color: DemProColors.accent, borderRadius: BorderRadius.circular(12)),
            child: Material(color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _geocoding ? null : _confirmPlacement,
                child: Center(child: _geocoding
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirmer la position', style: DemProText.button),
                ),
              ),
            ),
          )),
      ]),
    ),
  );

  // ── Panel principal ───────────────────────────────────────────────────────

  // Le CTA (bouton Suivant/Confirmer) n'appartient pas à ce panneau — il
  // flotte en dehors (voir `build`) pour rester visible même quand le
  // panneau est réduit à sa taille minimale (poignée + bandeau uniquement).
  // Un tap dans une zone vide referme le clavier (au lieu d'obliger à
  // scroller pour retrouver un bouton).
  Widget _buildPanel(ScrollController scrollCtrl) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => FocusScope.of(context).unfocus(),
    child: CustomScrollView(
      controller: scrollCtrl,
      slivers: [
        // ── Handle drag ──────────────────────────────────────────────────────
        SliverToBoxAdapter(child: Center(child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Container(width: 36, height: 4, decoration: BoxDecoration(color: DemProColors.bg4, borderRadius: BorderRadius.circular(2))),
        ))),

        // ── Bandeau départ ────────────────────────────────────────────────────
        SliverToBoxAdapter(child: _DepartureBanner(
          label: _selectedProAddr?['label'] as String?,
          address: _pickupAddress,
          loading: _loadingGps,
          onTap: () => _showChangeDeparture(),
        )),

        // ── Titre étape ───────────────────────────────────────────────────────
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          child: Row(children: [
            Icon(_stepMeta[_step].$1, color: DemProColors.accent, size: 18),
            const SizedBox(width: 8),
            Text(_stepMeta[_step].$2, style: DemProText.title),
          ]),
        )),

        // ── Contenu — le padding bas laisse la place au CTA flottant ─────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          sliver: SliverToBoxAdapter(child: switch (_step) {
            0 => _buildStep0(),
            1 => _buildStep1(),
            _ => _buildStep2(),
          }),
        ),
      ],
    ),
  );

  // ── Étape 0 — Destination ─────────────────────────────────────────────────

  Widget _buildStep0() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

    // Champ recherche + bouton carte
    Row(children: [
      Expanded(
        child: TextField(
          controller: _addressSearchCtrl,
          style: DemProText.body,
          textInputAction: TextInputAction.search,
          onChanged: _onAddressChanged,
          onSubmitted: _forwardGeocode,
          decoration: InputDecoration(
            hintText: 'Saisir une adresse…',
            hintStyle: DemProText.caption,
            prefixIcon: _searchingAddress
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: DemProColors.accent, strokeWidth: 2)),
                  )
                : Icon(
                    _deliveryLat != null ? Icons.check_circle : Icons.search,
                    color: _deliveryLat != null ? DemProColors.success : DemProColors.muted,
                    size: 18,
                  ),
            suffixIcon: _addressSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: DemProColors.muted, size: 16),
                    onPressed: () {
                      _addressSearchCtrl.clear();
                      setState(() { _suggestions = []; _deliveryLat = null; _deliveryLng = null; _deliveryAddress = ''; });
                    },
                  )
                : null,
            filled: true,
            fillColor: DemProColors.bg3,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _deliveryLat != null ? DemProColors.success.withValues(alpha: 0.5) : DemProColors.bg4),
            ),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => _enterMapPlacement(forPickup: false),
        child: Container(
          width: 56, height: 48,
          decoration: BoxDecoration(
            color: DemProColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.map_outlined, color: DemProColors.accent, size: 18),
            const SizedBox(height: 1),
            Text('Carte', style: DemProText.micro.copyWith(color: DemProColors.accent)),
          ]),
        ),
      ),
    ]),

    // Destinations récentes (avant saisie)
    if (_addressSearchCtrl.text.isEmpty && _suggestions.isEmpty && _deliveryLat == null && _recentDestinations.isNotEmpty)
      Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: DemProColors.bg3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DemProColors.bg4),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(children: [
                const Icon(Icons.history, color: DemProColors.muted, size: 14),
                const SizedBox(width: 6),
                const Text('Destinations récentes', style: DemProText.micro),
              ]),
            ),
            ..._recentDestinations.map((d) {
              final address = d['address'] as String? ?? '';
              final name    = d['receiverName'] as String?;
              return InkWell(
                onTap: () => _applyRecentDestination(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(children: [
                    const Icon(Icons.place_outlined, color: DemProColors.accent, size: 16),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(address, style: DemProText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (name != null && name.isNotEmpty)
                        Text(name, style: DemProText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ])),
                  ]),
                ),
              );
            }),
          ],
        ),
      ),

    // Suggestions Google Places
    if (_suggestions.isNotEmpty || _searchingAddress || _searchError != null)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: PlaceSuggestionsList(
          suggestions: _suggestions,
          loading: _searchingAddress,
          error: _searchError,
          onRetry: _retryAddressSearch,
          onSelect: _selectSuggestion,
          colors: _placeSuggestionsColors,
        ),
      ),
    const SizedBox(height: 14),

    const Divider(color: DemProColors.bg3, height: 1),
    const SizedBox(height: 14),

    _FieldLabel('Nom du client (optionnel)'),
    const SizedBox(height: 6),
    _ProTextField(
      controller: _recipientNameCtrl,
      hint: 'Prénom Nom',
      textInputAction: TextInputAction.next,
      onChanged: (_) => _scheduleDraftSave(),
    ),
    const SizedBox(height: 14),

    _FieldLabel('Téléphone du client *'),
    const SizedBox(height: 6),
    _ProTextField(
      controller: _recipientPhoneCtrl,
      hint: '77 000 00 00',
      prefix: '+221 ',
      keyboardType: TextInputType.phone,
      maxLength: 9,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      onChanged: (_) { setState(() {}); _scheduleDraftSave(); },
      suffixIcon: _recipientPhoneCtrl.text.isEmpty ? null : Icon(
        isValidSenegalMobile(_recipientPhoneCtrl.text.trim()) ? Icons.check_circle : Icons.error_outline,
        color: isValidSenegalMobile(_recipientPhoneCtrl.text.trim()) ? DemProColors.success : DemProColors.danger,
        size: 18,
      ),
    ),
  ]);

  // ── Étape 1 — Colis ──────────────────────────────────────────────────────

  // ── Catalogue produits ────────────────────────────────────────────────────

  Future<void> _openProductPicker() async {
    final product = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductPickerSheet(repo: _proRepo),
    );
    if (product == null) return;

    final name  = product['name'] as String? ?? '';
    final price = product['defaultPrice'] as num?;
    setState(() {
      // Réutilise la dernière ligne si elle est encore vide (cas le plus
      // fréquent : premier article de la commande) plutôt que d'empiler une
      // ligne vide au-dessus de celle choisie dans le catalogue.
      final last = _articles.isNotEmpty ? _articles.last : null;
      final target = (last != null && last.nameCtrl.text.trim().isEmpty) ? last : _Article();
      if (!identical(target, last)) _articles.add(target);
      target.nameCtrl.text = name;
      target.priceCtrl.text = price != null ? price.toInt().toString() : '';
    });
    _scheduleDraftSave();

    final id = product['id'] as String?;
    if (id != null) _proRepo.incrementProductUsage(id);
  }

  Widget _buildStep1() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

    // ── Articles ──────────────────────────────────────────────────────────
    const _FieldLabel('Articles'),
    const SizedBox(height: 10),
    ...List.generate(_articles.length, (i) {
      final a = _articles[i];
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DemProColors.bg3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DemProColors.bg4),
        ),
        child: Column(children: [
          Row(children: [
            CircleAvatar(radius: 12, backgroundColor: DemProColors.accent.withValues(alpha: 0.15),
              child: Text('${i + 1}', style: DemProText.micro.copyWith(color: DemProColors.accent, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(child: _ProTextField(controller: a.nameCtrl, hint: 'Nom du produit', onChanged: (_) => _scheduleDraftSave())),
            if (_articles.length > 1) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () { setState(() { _articles[i].dispose(); _articles.removeAt(i); }); _scheduleDraftSave(); },
                child: const Icon(Icons.remove_circle_outline, color: DemProColors.danger, size: 20),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _ProTextField(controller: a.qtyCtrl, hint: 'Qté', keyboardType: TextInputType.number, onChanged: (_) => _scheduleDraftSave())),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _ProTextField(controller: a.priceCtrl, hint: 'Prix (FCFA)', keyboardType: TextInputType.number, onChanged: (_) => _scheduleDraftSave())),
          ]),
        ]),
      );
    }),
    if (_articles.length < 10)
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _openProductPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: DemProColors.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.inventory_2_outlined, color: DemProColors.accent, size: 16),
                const SizedBox(width: 6),
                Text('Catalogue', style: DemProText.bodyStrong.copyWith(color: DemProColors.accent)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () { setState(() => _articles.add(_Article())); _scheduleDraftSave(); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.add, color: DemProColors.accent, size: 16),
                const SizedBox(width: 6),
                Text('Ajouter', style: DemProText.bodyStrong.copyWith(color: DemProColors.accent)),
              ]),
            ),
          ),
        ),
      ]),
    const SizedBox(height: 16),
    const Divider(color: DemProColors.bg3, height: 1),
    const SizedBox(height: 14),

    // ── Type de colis ─────────────────────────────────────────────────────
    const _FieldLabel('Type de colis'),
    const SizedBox(height: 10),
    ..._packageTypes.map((t) => _PackageTypeRow(
      type: t.$1, label: t.$2, icon: t.$3, subtitle: t.$4,
      selected: _packageType == t.$1,
      onTap: () { setState(() => _packageType = t.$1); _scheduleDraftSave(); },
    )),
    const SizedBox(height: 14),
    Container(
      decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.bg4)),
      child: SwitchListTile(
        value: _isFragile,
        onChanged: (v) { setState(() => _isFragile = v); _scheduleDraftSave(); },
        activeTrackColor: DemProColors.warning,
        activeThumbColor: Colors.white,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: DemProColors.bg4,
        title: const Row(children: [
          Icon(Icons.warning_amber_outlined, color: DemProColors.warning, size: 18),
          SizedBox(width: 8),
          Text('Fragile', style: DemProText.subtitle),
        ]),
        subtitle: const Text('Le livreur sera notifié de faire attention', style: DemProText.caption),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
    ),
    const SizedBox(height: 16),
    const Divider(color: DemProColors.bg3, height: 1),
    const SizedBox(height: 14),

    // ── Paiement ──────────────────────────────────────────────────────────
    const _FieldLabel('Qui paie la livraison ?'),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: GestureDetector(
        onTap: () { setState(() => _paymentMode = 'merchant'); _scheduleDraftSave(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _paymentMode == 'merchant' ? DemProColors.accent.withValues(alpha: 0.12) : DemProColors.bg3,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _paymentMode == 'merchant' ? DemProColors.accent : DemProColors.bg4,
              width: _paymentMode == 'merchant' ? 1.5 : 1,
            ),
          ),
          child: Column(children: [
            Icon(Icons.storefront_outlined,
              color: _paymentMode == 'merchant' ? DemProColors.accent : DemProColors.muted, size: 22),
            const SizedBox(height: 6),
            Text('Je paie',
              style: DemProText.bodyStrong.copyWith(
                color: _paymentMode == 'merchant' ? DemProColors.accent : DemProColors.muted,
              )),
            const SizedBox(height: 2),
            Text('Paiement en ligne',
              style: DemProText.micro.copyWith(
                color: _paymentMode == 'merchant' ? DemProColors.accent.withValues(alpha: 0.7) : DemProColors.muted,
              )),
          ]),
        ),
      )),
      const SizedBox(width: 10),
      Expanded(child: GestureDetector(
        onTap: () { setState(() => _paymentMode = 'cod'); _scheduleDraftSave(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _paymentMode == 'cod' ? DemProColors.accent.withValues(alpha: 0.12) : DemProColors.bg3,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _paymentMode == 'cod' ? DemProColors.accent : DemProColors.bg4,
              width: _paymentMode == 'cod' ? 1.5 : 1,
            ),
          ),
          child: Column(children: [
            Icon(Icons.payments_outlined,
              color: _paymentMode == 'cod' ? DemProColors.accent : DemProColors.muted, size: 22),
            const SizedBox(height: 6),
            Text('Client paie',
              style: DemProText.bodyStrong.copyWith(
                color: _paymentMode == 'cod' ? DemProColors.accent : DemProColors.muted,
              )),
            const SizedBox(height: 2),
            Text('À la livraison',
              style: DemProText.micro.copyWith(
                color: _paymentMode == 'cod' ? DemProColors.accent.withValues(alpha: 0.7) : DemProColors.muted,
              )),
          ]),
        ),
      )),
    ]),
    const SizedBox(height: 16),
    const Divider(color: DemProColors.bg3, height: 1),
    const SizedBox(height: 14),

    // ── Instructions ──────────────────────────────────────────────────────
    _FieldLabel('Instructions pour le livreur (optionnel)'),
    const SizedBox(height: 6),
    _ProTextField(controller: _instructionsCtrl, hint: 'ex: Appeler à l\'arrivée…', maxLines: 3, onChanged: (_) => _scheduleDraftSave()),

    // ── Livraison programmée (uniquement si lancé depuis "Programmer") ──
    if (widget.scheduled) ...[
    const SizedBox(height: 16),
    const Divider(color: DemProColors.bg3, height: 1),
    const SizedBox(height: 14),
    Container(
      decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: _isScheduled ? DemProColors.accent.withValues(alpha: 0.4) : DemProColors.bg4)),
      child: SwitchListTile(
        value: _isScheduled,
        onChanged: (v) {
          setState(() { _isScheduled = v; if (!v) _scheduledAt = null; });
          if (v) _pickScheduleDate();
        },
        activeTrackColor: DemProColors.accent,
        activeThumbColor: Colors.white,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: DemProColors.bg4,
        title: const Row(children: [
          Icon(Icons.schedule, color: DemProColors.accent, size: 18),
          SizedBox(width: 8),
          Text('Programmer la livraison', style: DemProText.subtitle),
        ]),
        subtitle: const Text('Choisir une date et heure précise', style: DemProText.caption),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
    ),
    if (_isScheduled) ...[
      const SizedBox(height: 10),
      GestureDetector(
        onTap: _pickScheduleDate,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: DemProColors.bg3,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _scheduledAt != null ? DemProColors.accent : DemProColors.warning, width: 1.5),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today, color: _scheduledAt != null ? DemProColors.accent : DemProColors.warning, size: 18),
            const SizedBox(width: 10),
            Expanded(child: _scheduledAt != null
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_fmtDate(_scheduledAt!), style: DemProText.subtitle),
                    Text(_fmtTime(_scheduledAt!), style: DemProText.caption),
                  ])
                : Text('Appuyez pour choisir la date', style: DemProText.bodyStrong.copyWith(color: DemProColors.warning)),
            ),
            Icon(Icons.edit_outlined, color: _scheduledAt != null ? DemProColors.muted : DemProColors.warning, size: 16),
          ]),
        ),
      ),
    ],
    ], // end if (widget.scheduled)
  ]);

  // ── Étape 2 — Confirmation ────────────────────────────────────────────────

  Widget _buildStep2() {
    final totalClient = (_estimate?['totalClient'] as num?)?.toInt();
    final price  = (_estimate?['price']       as num?)?.toInt();
    final demFee = (_estimate?['demFee']      as num?)?.toInt() ?? 0;
    final dist   = (_estimate?['distanceKm']  as num?)?.toStringAsFixed(1);
    final dur    = (_estimate?['durationMin'] as num?)?.toInt();
    final total  = totalClient ?? (price != null ? price + demFee : null);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Résumé trajet
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(14), border: Border.all(color: DemProColors.bg4)),
        child: Column(children: [
          _RouteRow(icon: Icons.location_on, color: DemProColors.accent,
            label: _selectedProAddr != null
                ? '${_selectedProAddr!['label']} — $_pickupAddress'
                : _pickupAddress.isNotEmpty ? _pickupAddress : 'Départ'),
          Padding(padding: const EdgeInsets.only(left: 11),
            child: Column(children: List.generate(3, (_) => Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              width: 2, height: 6, color: DemProColors.muted.withValues(alpha: 0.3),
            )))),
          _RouteRow(icon: Icons.flag, color: DemProColors.danger,
            label: _deliveryAddress.isNotEmpty ? _deliveryAddress : 'Destination'),
          if (_recipientNameCtrl.text.trim().isNotEmpty || _recipientPhoneCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: DemProColors.bg4, height: 1),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.person_outline, color: DemProColors.muted, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                [
                  if (_recipientNameCtrl.text.trim().isNotEmpty) _recipientNameCtrl.text.trim(),
                  if (_recipientPhoneCtrl.text.trim().isNotEmpty) '+221 ${_recipientPhoneCtrl.text.trim()}',
                ].join(' · '),
                style: DemProText.caption,
              )),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 12),

      // Détails colis
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.bg4)),
        child: Row(children: [
          Icon(_packageTypes.firstWhere((t) => t.$1 == _packageType).$3, color: DemProColors.accent, size: 18),
          const SizedBox(width: 10),
          Text(_packageTypes.firstWhere((t) => t.$1 == _packageType).$2,
            style: DemProText.bodyStrong),
          if (_isFragile) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: DemProColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text('Fragile', style: DemProText.micro.copyWith(color: DemProColors.warning)),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 10),

      // Articles
      if (_articles.any((a) => a.nameCtrl.text.trim().isNotEmpty))
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.bg4)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.shopping_bag_outlined, color: DemProColors.accent, size: 16),
              SizedBox(width: 8),
              Text('Articles', style: DemProText.bodyStrong),
            ]),
            const SizedBox(height: 8),
            ..._articles.where((a) => a.nameCtrl.text.trim().isNotEmpty).map((a) {
              final qty = int.tryParse(a.qtyCtrl.text.trim()) ?? 1;
              final price = int.tryParse(a.priceCtrl.text.trim());
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Text('•  ', style: DemProText.caption),
                  Expanded(child: Text(
                    '${a.nameCtrl.text.trim()} × $qty',
                    style: DemProText.caption.copyWith(color: DemProColors.text),
                  )),
                  if (price != null)
                    Text('$price FCFA', style: DemProText.caption),
                ]),
              );
            }),
          ]),
        ),

      // Paiement
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.bg4)),
        child: Row(children: [
          Icon(_paymentMode == 'merchant' ? Icons.storefront_outlined : Icons.payments_outlined, color: DemProColors.accent, size: 18),
          const SizedBox(width: 10),
          Text(
            _paymentMode == 'merchant' ? 'Vous payez la livraison' : 'Le client paie à la livraison',
            style: DemProText.bodyStrong,
          ),
        ]),
      ),

      // Créneau programmé
      if (_scheduledAt != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: DemProColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DemProColors.accent.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.schedule, color: DemProColors.accent, size: 18),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Livraison programmée', style: DemProText.micro.copyWith(color: DemProColors.accent)),
              Text('${_fmtDate(_scheduledAt!)} à ${_fmtTime(_scheduledAt!)}',
                style: DemProText.bodyStrong),
            ]),
          ]),
        ),
      const SizedBox(height: 14),

      // Prix
      if (_loadingEstimate)
        const Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(color: DemProColors.accent, strokeWidth: 2),
        ))
      else if (total != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [DemProColors.bg3, DemProColors.bg4]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            // Le livreur touche toujours `total` en entier — la réduction ne
            // change que ce que DEM Pro/le destinataire paie réellement (voir
            // orders.service.js:confirmPayment côté serveur).
            if (_discountAmount != null && _discountAmount! > 0) ...[
              Text(DemProFormat.fcfa(total),
                  style: DemProText.caption.copyWith(decoration: TextDecoration.lineThrough)),
              const SizedBox(height: 2),
              Text(DemProFormat.fcfa((total - _discountAmount!).clamp(0, double.infinity)),
                  style: DemProText.hero.copyWith(color: DemProColors.success)),
              const SizedBox(height: 4),
              Text(_promoLabel != null ? 'Réduction appliquée ($_promoLabel)' : 'Réduction appliquée',
                  style: DemProText.caption.copyWith(color: DemProColors.success)),
            ] else
              Text(DemProFormat.fcfa(total), style: DemProText.hero),
            if (dist != null || dur != null) ...[
              const SizedBox(height: 4),
              Text([if (dist != null) '$dist km', if (dur != null) '~$dur min'].join(' · '),
                style: DemProText.caption),
            ],
          ]),
        )
      else
        GestureDetector(
          onTap: _fetchEstimate,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.warning.withValues(alpha: 0.4))),
            child: Row(children: [
              const Icon(Icons.refresh, color: DemProColors.warning, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('Impossible de calculer le prix. Appuyez pour réessayer.', style: DemProText.caption.copyWith(color: DemProColors.warning))),
            ]),
          ),
        ),
      if (total != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _promoCodeCtrl,
              textCapitalization: TextCapitalization.characters,
              style: DemProText.body,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Code promo (optionnel)',
                hintStyle: DemProText.caption,
                filled: true,
                fillColor: DemProColors.bg3,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _checkingPromo ? null : _applyPromoCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: (_discountAmount != null && _discountAmount! > 0)
                    ? DemProColors.success.withValues(alpha: 0.15)
                    : DemProColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _checkingPromo
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: DemProColors.accent))
                  : Text(
                      (_discountAmount != null && _discountAmount! > 0) ? 'Appliqué ✓' : 'Appliquer',
                      style: DemProText.bodyStrong.copyWith(
                        color: (_discountAmount != null && _discountAmount! > 0) ? DemProColors.success : DemProColors.accent,
                      ),
                    ),
            ),
          ),
        ]),
        if (_promoError != null) ...[
          const SizedBox(height: 4),
          Text(_promoError!, style: DemProText.caption.copyWith(color: DemProColors.danger)),
        ],
      ],
      const SizedBox(height: 8),
    ]);
  }

  // ── Boutons navigation ────────────────────────────────────────────────────

  Widget _buildNavButtons() => SafeArea(top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: _step < 2
          ? Row(children: [
              if (_step > 0) ...[
                Expanded(flex: 1, child: _NavBtn(label: 'Précédent', outline: true, onTap: _back)),
                const SizedBox(width: 12),
              ],
              Expanded(flex: 2, child: _NavBtn(label: 'Suivant', onTap: _canAdvance ? _next : null)),
            ])
          : _NavBtn(
              label: _scheduledAt != null ? 'Programmer la livraison' : 'Confirmer et envoyer',
              loading: _submitting,
              onTap: _submitting ? null : _submit,
            ),
    ),
  );

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
            primary: DemProColors.accent,
            onPrimary: Colors.white,
            surface: DemProColors.bg2,
            onSurface: DemProColors.text,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: DemProColors.bg2),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledAt != null
          ? TimeOfDay(hour: _scheduledAt!.hour, minute: _scheduledAt!.minute)
          : TimeOfDay(hour: minDate.hour, minute: (minDate.minute ~/ 15 + 1) * 15 % 60),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: DemProColors.accent,
            onPrimary: Colors.white,
            surface: DemProColors.bg2,
            onSurface: DemProColors.text,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: DemProColors.bg2),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(minDate)) {
      showDemToast(context, 'Choisissez un créneau au moins 10 min dans le futur', isError: true);
      return;
    }
    setState(() => _scheduledAt = picked);
    _scheduleDraftSave();
  }

  static String _fmtDate(DateTime dt) {
    const months = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun', 'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ── Sheet — changer le départ ─────────────────────────────────────────────

  void _showChangeDeparture() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChangeDepartureSheet(
        proAddresses:  _proAddresses,
        selectedId:    _selectedProAddr?['id'] as String?,
        loadingGps:    _loadingGps,
        dio:           _publicDio,
        onSelect:      (addr) { Navigator.pop(context); _applyProAddress(addr); },
        onGps:         () { Navigator.pop(context); _fetchGps(); },
        onMap:         () { Navigator.pop(context); _enterMapPlacement(forPickup: true); },
        onManualAddress: (lat, lng, address) { Navigator.pop(context); _applyManualPickup(lat, lng, address); },
      ),
    );
  }

  void _applyManualPickup(double lat, double lng, String address) {
    setState(() {
      _selectedProAddr = null;
      _pickupLat = lat;
      _pickupLng = lng;
      _pickupAddress = address;
    });
    _recenterMap();
    if (_step == 2) { _fetchEstimate(); _fetchRoute(); }
    _scheduleDraftSave();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget bandeau départ
// ─────────────────────────────────────────────────────────────────────────────

class _DepartureBanner extends StatelessWidget {
  final String? label;
  final String  address;
  final bool    loading;
  final VoidCallback onTap;
  const _DepartureBanner({required this.label, required this.address, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DemProColors.bg3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DemProColors.bg4),
      ),
      child: Row(children: [
        const Icon(Icons.location_on, color: DemProColors.accent, size: 18),
        const SizedBox(width: 8),
        Expanded(child: loading
            ? const Text('Localisation en cours…', style: DemProText.caption)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (label != null)
                  Text(label!, style: DemProText.caption.copyWith(color: DemProColors.text, fontWeight: FontWeight.w700)),
                Text(
                  address.isNotEmpty ? address : 'Aucun départ sélectionné',
                  style: DemProText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ])),
        const SizedBox(width: 8),
        Text('Changer', style: DemProText.caption.copyWith(color: DemProColors.accent, fontWeight: FontWeight.w700)),
        const Icon(Icons.chevron_right, color: DemProColors.accent, size: 16),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet — changer le départ
// ─────────────────────────────────────────────────────────────────────────────

class _ChangeDepartureSheet extends StatefulWidget {
  final List<Map<String, dynamic>> proAddresses;
  final String? selectedId;
  final bool    loadingGps;
  final Dio dio;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onGps;
  final VoidCallback onMap;
  final void Function(double lat, double lng, String address) onManualAddress;
  const _ChangeDepartureSheet({
    required this.proAddresses, required this.selectedId,
    required this.loadingGps, required this.dio,
    required this.onSelect, required this.onGps, required this.onMap,
    required this.onManualAddress,
  });

  @override
  State<_ChangeDepartureSheet> createState() => _ChangeDepartureSheetState();
}

class _ChangeDepartureSheetState extends State<_ChangeDepartureSheet> {
  static const _iconMap = {
    'store':     Icons.storefront_outlined,
    'warehouse': Icons.warehouse_outlined,
    'office':    Icons.business_outlined,
    'home':      Icons.home_outlined,
    'other':     Icons.place_outlined,
  };

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  String? _searchError;
  String? _sessionToken;
  late final _placesService = PlacesAutocompleteService(widget.dio);

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _sessionToken ??= PlacesAutocompleteService.newSessionToken();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() { _searching = true; _searchError = null; });
      try {
        final preds = await _placesService.autocomplete(query: query, sessionToken: _sessionToken!);
        if (mounted) setState(() { _suggestions = preds; _searching = false; });
      } catch (e) {
        if (mounted) setState(() { _searching = false; _searchError = friendlyError(e); });
      }
    });
  }

  void _retrySearch() => _onChanged(_searchCtrl.text);

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
    final token = _sessionToken ?? PlacesAutocompleteService.newSessionToken();
    try {
      final result = await _placesService.details(placeId: placeId, sessionToken: token);
      if (result != null) {
        final loc = result['geometry']['location'];
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final name = (place['structured_formatting']?['main_text'] as String?)
            ?? place['description'] as String? ?? '';
        widget.onManualAddress(lat, lng, name);
      }
    } catch (_) {
    } finally {
      _sessionToken = null;
    }
  }

  Future<void> _submitManual(String query) async {
    if (query.trim().length < 3) return;
    setState(() => _searching = true);
    try {
      final locations = await geo.locationFromAddress('$query, Dakar, Sénégal')
          .timeout(const Duration(seconds: 6));
      if (locations.isEmpty) return;
      final loc = locations.first;
      widget.onManualAddress(loc.latitude, loc.longitude, query.trim());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  // Remonte au-dessus du clavier (sinon le champ de recherche se retrouve
  // caché derrière une fois le focus pris) et devient scrollable pour ne
  // jamais déborder une fois le clavier ouvert.
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 120),
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
    decoration: const BoxDecoration(
      color: DemProColors.bg2,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
    child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(width: 36, height: 4, decoration: BoxDecoration(color: DemProColors.bg4, borderRadius: BorderRadius.circular(2))),
      )),
      const Text('Point de départ', style: DemProText.title),
      const SizedBox(height: 14),

      // Recherche manuelle avec autocomplete
      TextField(
        controller: _searchCtrl,
        style: DemProText.body,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        onSubmitted: _submitManual,
        decoration: InputDecoration(
          hintText: 'Saisir l\'adresse d\'expédition…',
          hintStyle: DemProText.caption,
          prefixIcon: _searching
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: DemProColors.accent, strokeWidth: 2)))
              : const Icon(Icons.search, color: DemProColors.muted, size: 18),
          filled: true,
          fillColor: DemProColors.bg3,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      if (_suggestions.isNotEmpty || _searching || _searchError != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PlaceSuggestionsList(
            suggestions: _suggestions,
            loading: _searching,
            error: _searchError,
            onRetry: _retrySearch,
            onSelect: _selectSuggestion,
            colors: _placeSuggestionsColors,
            maxHeight: 180,
          ),
        ),
      const SizedBox(height: 14),

      // Adresses Pro
      if (widget.proAddresses.isNotEmpty) ...[
        const Text('Mes adresses', style: DemProText.micro),
        const SizedBox(height: 8),
        ...widget.proAddresses.map((a) {
          final isSelected = a['id'] == widget.selectedId;
          final icon = _iconMap[a['icon'] as String? ?? 'other'] ?? Icons.place_outlined;
          return GestureDetector(
            onTap: () => widget.onSelect(a),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? DemProColors.accent.withValues(alpha: 0.10) : DemProColors.bg3,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? DemProColors.accent : DemProColors.bg4, width: isSelected ? 1.5 : 1),
              ),
              child: Row(children: [
                Icon(icon, color: DemProColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['label'] as String? ?? '', style: DemProText.bodyStrong),
                  Text(a['address'] as String? ?? '', style: DemProText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                if (isSelected) const Icon(Icons.check_circle, color: DemProColors.accent, size: 18),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
      ],

      // Actions alternatives
      _SheetAction(icon: Icons.my_location, label: 'Ma position actuelle', loading: widget.loadingGps, onTap: widget.onGps),
      const SizedBox(height: 8),
      _SheetAction(icon: Icons.map_outlined, label: 'Pointer sur la carte', onTap: widget.onMap),
    ])),
  ));
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, this.loading = false, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.bg4)),
      child: loading
          ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: DemProColors.accent, strokeWidth: 2)))
          : Row(children: [
              Icon(icon, color: DemProColors.muted, size: 18),
              const SizedBox(width: 10),
              Text(label, style: DemProText.bodyStrong),
            ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet — reprise de brouillon
// ─────────────────────────────────────────────────────────────────────────────

class _DraftResumeSheet extends StatelessWidget {
  final String? savedAt;
  final VoidCallback onResume;
  final VoidCallback onDiscard;
  const _DraftResumeSheet({required this.savedAt, required this.onResume, required this.onDiscard});

  String get _label {
    final dt = savedAt != null ? DateTime.tryParse(savedAt!)?.toLocal() : null;
    if (dt == null) return 'Vous avez une livraison en cours de saisie.';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return 'Brouillon enregistré à $h:$m.';
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DemProColors.bg2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DemProColors.bg4),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.description_outlined, color: DemProColors.accent, size: 32),
        const SizedBox(height: 12),
        const Text('Reprendre votre brouillon ?', style: DemProText.title),
        const SizedBox(height: 6),
        Text(_label, textAlign: TextAlign.center, style: DemProText.caption),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: onDiscard,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: DemProColors.bg4),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Nouvelle livraison', style: DemProText.bodyStrong.copyWith(color: DemProColors.muted)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: onResume,
            style: ElevatedButton.styleFrom(
              backgroundColor: DemProColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Reprendre', style: DemProText.button),
          )),
        ]),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers internes
// ─────────────────────────────────────────────────────────────────────────────


class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: DemProText.caption);
}

class _ProTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? prefix;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final void Function(String)? onChanged;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  const _ProTextField({required this.controller, required this.hint, this.prefix, this.keyboardType, this.maxLines = 1, this.maxLength, this.inputFormatters, this.onChanged, this.suffixIcon, this.textInputAction, this.onSubmitted});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    maxLines: maxLines,
    maxLength: maxLength,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    style: DemProText.body.copyWith(fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: DemProText.caption,
      prefixText: prefix,
      prefixStyle: DemProText.caption.copyWith(fontSize: 14),
      suffixIcon: suffixIcon,
      counterText: '',
      filled: true,
      fillColor: DemProColors.bg3,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

class _PackageTypeRow extends StatelessWidget {
  final String type, label, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _PackageTypeRow({required this.type, required this.label, required this.icon, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: selected ? DemProColors.accent.withValues(alpha: 0.10) : DemProColors.bg3,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: selected ? DemProColors.accent : DemProColors.bg4, width: selected ? 1.5 : 1),
    ),
    child: Material(color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(color: selected ? DemProColors.accent.withValues(alpha: 0.15) : DemProColors.bg4, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: selected ? DemProColors.accent : DemProColors.muted, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: DemProText.subtitle.copyWith(color: selected ? DemProColors.accent : DemProColors.text)),
              Text(subtitle, style: DemProText.caption),
            ])),
            if (selected) const Icon(Icons.check_circle, color: DemProColors.accent, size: 20),
          ]),
        ),
      ),
    ),
  );
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _RouteRow({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 22),
    const SizedBox(width: 10),
    Expanded(child: Text(label, style: DemProText.body, maxLines: 2, overflow: TextOverflow.ellipsis)),
  ]);
}

class _NavBtn extends StatelessWidget {
  final String label;
  final bool outline;
  final bool loading;
  final VoidCallback? onTap;
  const _NavBtn({required this.label, this.outline = false, this.loading = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !loading;
    return SizedBox(height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: outline ? DemProColors.bg2 : (disabled ? DemProColors.bg3 : DemProColors.accent),
          borderRadius: BorderRadius.circular(14),
          border: outline ? Border.all(color: DemProColors.bg4) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Material(color: Colors.transparent,
          child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap,
            child: Center(child: loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(label, style: DemProText.button.copyWith(color: outline ? DemProColors.muted : (disabled ? DemProColors.muted : Colors.white))),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet — choisir un article depuis le catalogue produits
// ─────────────────────────────────────────────────────────────────────────────

class _ProductPickerSheet extends StatefulWidget {
  final DemProRepository repo;
  const _ProductPickerSheet({required this.repo});
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _products; // null = chargement en cours
  bool _loadFailed = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() => _query = _search.text.toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _products = null; _loadFailed = false; });
    try {
      final products = await widget.repo.getProducts();
      if (mounted) setState(() => _products = products);
    } catch (_) {
      if (mounted) setState(() { _products = []; _loadFailed = true; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final list = _products ?? [];
    if (_query.isEmpty) return list;
    return list.where((p) => (p['name'] as String? ?? '').toLowerCase().contains(_query)).toList();
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
    decoration: const BoxDecoration(
      color: DemProColors.bg2,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewPadding.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Center(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(width: 36, height: 4, decoration: BoxDecoration(color: DemProColors.bg4, borderRadius: BorderRadius.circular(2))),
      )),
      Row(children: [
        Expanded(child: Text('Choisir dans mon catalogue', style: DemProText.title.copyWith(color: DemProColors.text, fontSize: 17))),
        GestureDetector(
          onTap: () => context.push('/dem-pro/products'),
          child: Text('Gérer', style: DemProText.caption.copyWith(color: DemProColors.accent, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 12),
      if (_products != null && _products!.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.bg4)),
          child: TextField(
            controller: _search,
            style: DemProText.body.copyWith(color: DemProColors.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Rechercher…',
              hintStyle: DemProText.body.copyWith(color: DemProColors.muted, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: DemProColors.muted, size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      Flexible(
        child: _products == null
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator(color: DemProColors.accent)),
              )
            : _loadFailed
                ? _buildMessage(Icons.wifi_off_rounded, 'Impossible de charger le catalogue.')
                : _filtered.isEmpty
                    ? _buildMessage(
                        Icons.inventory_2_outlined,
                        _products!.isEmpty
                            ? 'Aucun produit enregistré pour l\'instant.\nAjoutez-en un depuis "Gérer".'
                            : 'Aucun résultat.',
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = _filtered[i];
                          final price = p['defaultPrice'] as num?;
                          return GestureDetector(
                            onTap: () => Navigator.pop(context, p),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                    p['name'] as String? ?? '',
                                    style: DemProText.bodyStrong.copyWith(color: DemProColors.text),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (price != null) ...[
                                  const SizedBox(width: 8),
                                  Text(DemProFormat.fcfa(price), style: DemProText.caption.copyWith(color: DemProColors.success)),
                                ],
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right, color: DemProColors.muted, size: 18),
                              ]),
                            ),
                          );
                        },
                      ),
      ),
    ]),
  );

  Widget _buildMessage(IconData icon, String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: DemProColors.muted, size: 32),
      const SizedBox(height: 10),
      Text(msg, style: DemProText.body.copyWith(color: DemProColors.muted), textAlign: TextAlign.center),
    ]),
  );
}
