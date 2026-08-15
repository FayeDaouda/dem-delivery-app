import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/map_theme_provider.dart';
import '../../home_driver/navigation/map_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/services/places_autocomplete_service.dart';
import '../../../core/storage/dem_pro_draft_storage.dart';
import '../../../core/storage/promo_code_storage.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../core/utils/senegal_phone.dart';
import '../../../shared/widgets/place_suggestions_list.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../deliveries/data/orders_repository.dart';
import '../../home_driver/navigation/directions_service.dart';
import '../../home_driver/navigation/navigation_service.dart';
import '../data/dem_pro_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/theme/client_text.dart';

// ─────────────────────────────────────────────────────────────────────────────

const _dakar = LatLng(14.6937, -17.4441);

const _placeSuggestionsColors = PlaceSuggestionsColors(
  background: AppColors.card,
  border: AppColors.primaryDark,
  divider: AppColors.primaryDark,
  iconBg: AppColors.primaryDark,
  icon: AppColors.primary,
  mainText: AppColors.textPrimary,
  secondaryText: AppColors.textSecondary,
  accent: AppColors.primary,
);

const _packageTypes = [
  (
    'documents',
    'Documents',
    Icons.description_outlined,
    'Enveloppes, contrats, factures',
  ),
  ('small', 'Petit colis', Icons.inventory_2_outlined, 'Léger — moins de 5 kg'),
  ('large', 'Grand colis', Icons.view_in_ar_outlined, 'Lourd ou encombrant'),
];

const _stepMeta = [
  (Icons.flag_outlined, 'Destination', '1/5'),
  (Icons.shopping_bag_outlined, 'Articles', '2/5'),
  (Icons.inventory_2_outlined, 'Colis', '3/5'),
  (Icons.payments_outlined, 'Livraison', '4/5'),
  (Icons.check_circle_outline, 'Confirmation', '5/5'),
];

// ─────────────────────────────────────────────────────────────────────────────

class _Article {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController();
  // Rempli uniquement quand l'article vient du catalogue (voir
  // _openProductPicker) — sert au décrément de stock automatique côté
  // serveur. Un article tapé librement reste null, jamais décrémenté.
  String? productId;

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class DemProOrderCreateScreen extends ConsumerStatefulWidget {
  final bool scheduled;
  final String priority; // NORMAL | EXPRESS — voir orders.service.js
  final Map<String, dynamic>? reorderFrom;

  /// Demande soumise par un client final via le lien de commande public
  /// (dem.sn/commander/:merchantId) — préremplit destinataire/adresse texte,
  /// mais jamais les coordonnées (le client final n'en fournit pas), donc le
  /// commerçant doit toujours positionner le point de livraison lui-même
  /// avant de pouvoir avancer. Une fois la commande créée, la demande est
  /// marquée confirmée côté serveur (voir `_submit`).
  final Map<String, dynamic>? fromOrderRequest;
  const DemProOrderCreateScreen({
    super.key,
    this.scheduled = false,
    this.priority = 'NORMAL',
    this.reorderFrom,
    this.fromOrderRequest,
  });
  @override
  ConsumerState<DemProOrderCreateScreen> createState() => _State();
}

class _State extends ConsumerState<DemProOrderCreateScreen> {
  final _ordersRepo = OrdersRepository();
  final _proRepo = DemProRepository(ApiClient.dio);

  // ── Navigation ──────────────────────────────────────────────────────────
  int _step =
      0; // 0=Destination, 1=Articles, 2=Colis, 3=Livraison, 4=Confirmation

  // ── Hauteur réelle du panneau (mesurée) ───────────────────────────────────
  // Le commentaire historique sur `_panelHeight` annonçait déjà un panneau
  // qui "épouse son contenu" — mais `Flexible(child: SingleChildScrollView)`
  // (voir build()) force en réalité le panneau à toujours grandir jusqu'au
  // plafond de 86% de l'écran, quel que soit le contenu réel (Flexible
  // alloue l'espace disponible à son enfant, qui le remplit sans jamais
  // hériter d'un `mainAxisSize.min`) — même bug que celui déjà corrigé sur
  // Livraison simple/Express et groupée (voir diagnostic pré-prod). Ce
  // mécanisme de mesure comble l'écart entre l'intention du commentaire et
  // ce que le code faisait réellement.
  final _sheetKey = GlobalKey();
  double? _sheetHeight;

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

  // ── Map ─────────────────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  LatLng _cameraPos = _dakar;
  bool _isMapPlacement = false;
  bool _placingPickup = false; // false = placing delivery

  // ── Départ (auto-rempli depuis ProAddress défaut) ────────────────────────
  List<Map<String, dynamic>> _proAddresses = [];
  Map<String, dynamic>? _selectedProAddr;
  double? _pickupLat, _pickupLng;
  String _pickupAddress = '';
  bool _loadingGps = false;

  // ── Étape 1 — Destination ───────────────────────────────────────────────
  final _recipientNameCtrl = TextEditingController();
  final _recipientPhoneCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _addressSearchCtrl = TextEditingController();
  double? _deliveryLat, _deliveryLng;
  String _deliveryAddress = '';
  Timer? _searchDebounce;
  final _publicDio = Dio();

  // ── Destinations récentes ────────────────────────────────────────────────
  List<Map<String, dynamic>> _recentDestinations = [];

  // ── Brouillon ────────────────────────────────────────────────────────────
  Timer? _draftSaveDebounce;

  // ── Étape 2 — Colis ─────────────────────────────────────────────────────
  String _packageType = 'small';
  final _instructionsCtrl = TextEditingController();
  bool _isFragile = false;
  late final bool _isScheduled = widget.scheduled;
  DateTime? _scheduledAt;

  // ── Route polyline ────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];

  // ── Articles ───────────────────────────────────────────────────────────
  final List<_Article> _articles = [_Article()];

  // ── Paiement ───────────────────────────────────────────────────────────
  String _paymentMode = 'cod'; // 'merchant' | 'cod' — le client paie par défaut

  // ── Étape 3 — Confirmation ──────────────────────────────────────────────
  Map<String, dynamic>? _estimate;
  bool _loadingEstimate = false;
  bool _submitting = false;
  bool _geocoding = false;

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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeShowDraftPrompt(),
      );
    }
    if (widget.scheduled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickScheduleDate());
    }
  }

  /// Préremplit destinataire/adresse/articles depuis une demande reçue via la
  /// page publique — tout y est déjà (voir ci-dessous), donc pas besoin de
  /// refaire cliquer le commerçant sur 4 étapes déjà remplies : on saute
  /// directement au résumé/finalisation (étape 4) si les infos obligatoires
  /// sont là. Sinon (adresse sans coordonnées, téléphone invalide...), on
  /// reste à l'étape 0 pour qu'il complète lui-même avant de continuer.
  void _applyOrderRequest(Map<String, dynamic> request) {
    _fromRequestId = request['id'] as String?;
    _deliveryAddress = request['deliveryAddress'] as String? ?? '';
    _addressSearchCtrl.text = _deliveryAddress;

    // La boutique publique capture désormais activement les coordonnées
    // (GPS ou géocodage côté web) — auparavant ce champ existait déjà mais
    // n'était jamais rempli en pratique par l'ancien formulaire texte.
    final lat = (request['deliveryLatitude'] as num?)?.toDouble();
    final lng = (request['deliveryLongitude'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      _deliveryLat = lat;
      _deliveryLng = lng;
    }

    final name = request['customerName'] as String?;
    if (name != null && name.isNotEmpty) _recipientNameCtrl.text = name;

    final rawPhone = request['customerPhone'] as String?;
    if (rawPhone != null && rawPhone.isNotEmpty) {
      var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.startsWith('221') && digits.length > 9)
        digits = digits.substring(digits.length - 9);
      _recipientPhoneCtrl.text = digits.length > 9
          ? digits.substring(digits.length - 9)
          : digits;
    }

    final landmark = request['landmark'] as String?;
    if (landmark != null && landmark.isNotEmpty) _landmarkCtrl.text = landmark;

    final notes = request['notes'] as String?;
    if (notes != null && notes.isNotEmpty) _instructionsCtrl.text = notes;

    // Panier déjà choisi par le client sur la boutique publique — évite au
    // DEM Pro de tout retaper à la main (voir Order.items pour le même
    // format de snapshot {name, quantity, price, productId}).
    final items =
        (request['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isNotEmpty) {
      for (final a in _articles) {
        a.dispose();
      }
      _articles.clear();
      for (final item in items) {
        final a = _Article();
        a.nameCtrl.text = item['name'] as String? ?? '';
        a.qtyCtrl.text = '${item['quantity'] ?? 1}';
        final price = item['price'] as num?;
        if (price != null) a.priceCtrl.text = price.toInt().toString();
        a.productId = item['productId'] as String?;
        _articles.add(a);
      }
    }

    // Même condition que _canAdvance pour l'étape 0 — si elle est déjà
    // remplie, pas besoin de la refaire valider manuellement. Le point de
    // départ (pickup) charge en asynchrone (voir _loadProAddresses) : une
    // fois prêt, _applyProAddress/_geocodePickupAddress/_fetchGps
    // déclenchent déjà l'estimation dès qu'ils voient _step == 4, donc rien
    // d'autre à faire ici pour que le résumé arrive rempli.
    if (_deliveryLat != null &&
        isValidSenegalMobile(_recipientPhoneCtrl.text.trim())) {
      _step = 4;
    }
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _searchDebounce?.cancel();
    _draftSaveDebounce?.cancel();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _landmarkCtrl.dispose();
    _addressSearchCtrl.dispose();
    _instructionsCtrl.dispose();
    _promoCodeCtrl.dispose();
    for (final a in _articles) {
      a.dispose();
    }
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
      final name = dest['receiverName'] as String?;
      final phone = dest['receiverPhone'] as String?;
      if (name != null && name.isNotEmpty) _recipientNameCtrl.text = name;
      if (phone != null && phone.isNotEmpty) {
        _recipientPhoneCtrl.text = phone.replaceFirst('+221', '');
      }
    });
    if (_step == 4) {
      _recenterMap();
    } else {
      _centerMapVisible(LatLng(lat, lng));
    }
    _scheduleDraftSave();
  }

  // ── Recommander (reorder) ────────────────────────────────────────────────

  void _applyReorder(Map<String, dynamic> order) {
    final lat = (order['deliveryLatitude'] as num?)?.toDouble();
    final lng = (order['deliveryLongitude'] as num?)?.toDouble();
    _deliveryAddress = order['deliveryAddress'] as String? ?? '';
    _addressSearchCtrl.text = _deliveryAddress;
    if (lat != null && lng != null) {
      _deliveryLat = lat;
      _deliveryLng = lng;
    }
    final name = order['receiverName'] as String?;
    final phone = order['receiverPhone'] as String?;
    if (name != null && name.isNotEmpty) _recipientNameCtrl.text = name;
    if (phone != null && phone.isNotEmpty)
      _recipientPhoneCtrl.text = phone.replaceFirst('+221', '');

    final items = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isNotEmpty) {
      for (final a in _articles) {
        a.dispose();
      }
      _articles.clear();
      for (final it in items) {
        final a = _Article();
        a.nameCtrl.text = it['name'] as String? ?? '';
        a.qtyCtrl.text = '${it['quantity'] ?? 1}';
        if (it['price'] != null) a.priceCtrl.text = '${it['price']}';
        a.productId = it['productId'] as String?;
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
        .map(
          (a) => {
            'name': a.nameCtrl.text,
            'qty': a.qtyCtrl.text,
            'price': a.priceCtrl.text,
            if (a.productId != null) 'productId': a.productId,
          },
        )
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
      _deliveryLat = (draft['deliveryLat'] as num?)?.toDouble();
      _deliveryLng = (draft['deliveryLng'] as num?)?.toDouble();
      _deliveryAddress = draft['deliveryAddress'] as String? ?? '';
      _addressSearchCtrl.text = _deliveryAddress;
      _recipientNameCtrl.text = draft['recipientName'] as String? ?? '';
      _recipientPhoneCtrl.text = draft['recipientPhone'] as String? ?? '';
      _landmarkCtrl.text = draft['landmark'] as String? ?? '';
      _packageType = draft['packageType'] as String? ?? 'small';
      _isFragile = draft['isFragile'] as bool? ?? false;
      _instructionsCtrl.text = draft['instructions'] as String? ?? '';
      _paymentMode = draft['paymentMode'] as String? ?? 'cod';
      final articles =
          (draft['articles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (articles.isNotEmpty) {
        for (final a in _articles) {
          a.dispose();
        }
        _articles.clear();
        for (final it in articles) {
          final a = _Article();
          a.nameCtrl.text = it['name'] as String? ?? '';
          a.qtyCtrl.text = it['qty'] as String? ?? '1';
          a.priceCtrl.text = it['price'] as String? ?? '';
          a.productId = it['productId'] as String?;
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
        onResume: () {
          Navigator.pop(context);
          _applyDraft(draft);
        },
        onDiscard: () {
          Navigator.pop(context);
          DemProDraftStorage.clearOrderDraft();
        },
      ),
    );
  }

  // ── Map style ────────────────────────────────────────────────────────────

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  void _centerMap(LatLng pos) => _mapCtrl?.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(target: pos, zoom: 15, tilt: 20),
    ),
  );

  /// Centre la carte sur [pos] de sorte que le point soit visible dans la
  /// zone haute (au-dessus du panneau), et non caché derrière.
  /// Décale la cible caméra vers le SUD d'une distance égale à la moitié de
  /// la hauteur du panneau (convertie en degrés via la résolution Mercator
  /// au zoom utilisé) — [pos] apparaît alors plus au nord que le centre de
  /// l'écran, donc visuellement plus haut, au milieu de la zone visible.
  void _centerMapVisible(LatLng pos, {double zoom = 15}) {
    final panelH = _panelHeight + MediaQuery.of(context).viewPadding.bottom;
    final metersPerPixel =
        156543.03392 *
        math.cos(pos.latitude * math.pi / 180) /
        math.pow(2, zoom);
    final latShift = (panelH / 2) * metersPerPixel / 111320.0;
    final adjusted = LatLng(pos.latitude - latShift, pos.longitude);
    _mapCtrl?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: adjusted, zoom: zoom, tilt: 20),
      ),
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
      _pickupAddress = address;
      if (lat != null && lng != null) {
        _pickupLat = lat;
        _pickupLng = lng;
      }
    });
    if (lat == null || lng == null) {
      _geocodePickupAddress(address);
    } else if (_step == 4) {
      _fetchEstimate();
      _fetchRoute();
    } else {
      _centerMapVisible(LatLng(lat, lng));
    }
  }

  void _applyProAddressAsDelivery(Map<String, dynamic> addr) {
    final lat = (addr['lat'] as num?)?.toDouble();
    final lng = (addr['lng'] as num?)?.toDouble();
    final address = addr['address'] as String? ?? '';
    setState(() {
      _deliveryAddress = address;
      _addressSearchCtrl.text = address;
      if (lat != null && lng != null) {
        _deliveryLat = lat;
        _deliveryLng = lng;
      }
    });
    if (lat != null && lng != null) {
      if (_step == 4) {
        _fetchEstimate();
        _fetchRoute();
      } else {
        _centerMapVisible(LatLng(lat, lng));
      }
    }
    _scheduleDraftSave();
  }

  Future<void> _geocodePickupAddress(String address) async {
    if (address.isEmpty) {
      _fetchGps();
      return;
    }
    try {
      final locations = await geo
          .locationFromAddress('$address, Dakar, Sénégal')
          .timeout(const Duration(seconds: 6));
      if (locations.isEmpty || !mounted) return;
      final loc = locations.first;
      setState(() {
        _pickupLat = loc.latitude;
        _pickupLng = loc.longitude;
      });
      if (_step == 4) {
        _fetchEstimate();
        _fetchRoute();
      } else {
        _centerMapVisible(LatLng(loc.latitude, loc.longitude));
      }
    } catch (_) {
      _fetchGps();
    }
  }

  // ── GPS ──────────────────────────────────────────────────────────────────

  Future<void> _fetchGps({bool forPickup = true}) async {
    setState(() {
      _loadingGps = true;
      if (forPickup) _selectedProAddr = null;
    });
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (!mounted) return;
      if (pos == null) {
        showDemToast(
          context,
          'Activez la localisation pour continuer',
          isError: true,
        );
        return;
      }
      final ll = LatLng(pos.latitude, pos.longitude);
      if (forPickup) {
        _pickupLat = ll.latitude;
        _pickupLng = ll.longitude;
      } else {
        _deliveryLat = ll.latitude;
        _deliveryLng = ll.longitude;
      }
      if (_step == 4) {
        _recenterMap();
      } else {
        _centerMapVisible(ll);
      }
      _reverseGeocode(ll, forPickup: forPickup);
    } catch (_) {
      if (mounted) showDemToast(context, 'GPS indisponible', isError: true);
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  // ── Map placement ────────────────────────────────────────────────────────

  void _enterMapPlacement({required bool forPickup}) {
    setState(() {
      _isMapPlacement = true;
      _placingPickup = forPickup;
    });
    if (forPickup && _pickupLat != null) {
      _centerMap(LatLng(_pickupLat!, _pickupLng!));
    }
    if (!forPickup && _deliveryLat != null) {
      _centerMap(LatLng(_deliveryLat!, _deliveryLng!));
    }
  }

  Future<void> _confirmPlacement() async {
    setState(() => _geocoding = true);
    final pos = _cameraPos;
    if (_placingPickup) {
      _pickupLat = pos.latitude;
      _pickupLng = pos.longitude;
      _selectedProAddr = null;
      await _reverseGeocode(pos, forPickup: true);
    } else {
      _deliveryLat = pos.latitude;
      _deliveryLng = pos.longitude;
      await _reverseGeocode(pos, forPickup: false);
    }
    if (mounted) {
      setState(() {
        _isMapPlacement = false;
        _geocoding = false;
      });
      if (_step == 4) {
        _fetchEstimate();
        _fetchRoute();
      } else {
        _centerMapVisible(pos);
      }
      _scheduleDraftSave();
    }
  }

  Future<void> _reverseGeocode(LatLng pos, {required bool forPickup}) async {
    try {
      final marks = await geo
          .placemarkFromCoordinates(pos.latitude, pos.longitude)
          .timeout(const Duration(seconds: 5));
      if (marks.isEmpty || !mounted) return;
      final p = marks.first;
      final street = p.street ?? p.name ?? '';
      final local = p.subLocality ?? p.locality ?? '';
      final addr = street.isNotEmpty ? '$street, $local' : local;
      final result = addr.isNotEmpty
          ? addr
          : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      setState(() {
        if (forPickup) {
          _pickupAddress = result;
        } else {
          _deliveryAddress = result;
        }
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
    final a =
        sinDLat * sinDLat +
        math.cos(lat1R) * math.cos(lat2R) * sinDLng * sinDLng;
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Map<String, dynamic> _localEstimate() {
    if (_pickupLat == null || _deliveryLat == null) return {};
    final distKm = _haversineKm(
      _pickupLat!,
      _pickupLng!,
      _deliveryLat!,
      _deliveryLng!,
    );
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
    if (mounted)
      setState(() {
        _loadingEstimate = true;
        _estimate = null;
      });
    try {
      final est = await _ordersRepo
          .getEstimate(
            pickupLat: _pickupLat!,
            pickupLng: _pickupLng!,
            deliveryLat: _deliveryLat!,
            deliveryLng: _deliveryLng!,
            orderType: 'DELIVERY',
            priority: widget.priority,
          )
          .timeout(const Duration(seconds: 10));
      debugPrint('[ESTIMATE] result: $est');
      if (mounted)
        setState(() {
          _estimate = est;
          _loadingEstimate = false;
        });
      _checkAutoPromo();
    } catch (e) {
      debugPrint('[ESTIMATE] error: $e — using local fallback');
      if (mounted)
        setState(() {
          _estimate = _localEstimate();
          _loadingEstimate = false;
        });
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
        final result = await _ordersRepo.getPromoPreview(
          price: price,
          demFee: demFee,
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
        // atteint) — on ne l'efface pas ici, voir dem_pro_promo_code_screen.dart.
      }
    }

    try {
      final result = await _ordersRepo.getPromoPreview(
        price: price,
        demFee: demFee,
      );
      if (!mounted || result == null) return;
      setState(() {
        _discountAmount = (result['discountAmount'] as num?)?.toDouble();
        _promoLabel = result['promoCode'] as String?;
      });
    } catch (_) {} // jamais bloquant
  }

  Future<void> _applyPromoCode() async {
    final code = _promoCodeCtrl.text.trim();
    final price = (_estimate?['price'] as num?)?.toInt();
    if (code.isEmpty || price == null) return;
    final demFee = (_estimate?['demFee'] as num?)?.toInt() ?? 0;
    setState(() {
      _checkingPromo = true;
      _promoError = null;
    });
    try {
      final result = await _ordersRepo.getPromoPreview(
        price: price,
        demFee: demFee,
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_pickupLat == null || _pickupLng == null) {
      showDemToast(
        context,
        'Position de départ introuvable. Changez le point de départ.',
        isError: true,
      );
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
      if (_instructionsCtrl.text.trim().isNotEmpty)
        parts.add(_instructionsCtrl.text.trim());
      if (_landmarkCtrl.text.trim().isNotEmpty)
        parts.add('Repère: ${_landmarkCtrl.text.trim()}');

      final items = _articles
          .where((a) => a.nameCtrl.text.trim().isNotEmpty)
          .map(
            (a) => {
              'name': a.nameCtrl.text.trim(),
              'quantity': int.tryParse(a.qtyCtrl.text.trim()) ?? 1,
              if (a.priceCtrl.text.trim().isNotEmpty)
                'price': int.tryParse(a.priceCtrl.text.trim()) ?? 0,
              if (a.productId != null) 'productId': a.productId,
            },
          )
          .toList();

      final order = await _ordersRepo.createOrder({
        'orderType': 'DELIVERY',
        'priority': widget.priority,
        'pickupAddress': _pickupAddress.isNotEmpty
            ? _pickupAddress
            : '${_pickupLat!.toStringAsFixed(4)}, ${_pickupLng!.toStringAsFixed(4)}',
        'pickupLatitude': _pickupLat,
        'pickupLongitude': _pickupLng,
        'deliveryAddress': _deliveryAddress.isNotEmpty
            ? _deliveryAddress
            : '${_deliveryLat!.toStringAsFixed(4)}, ${_deliveryLng!.toStringAsFixed(4)}',
        'deliveryLatitude': _deliveryLat,
        'deliveryLongitude': _deliveryLng,
        if (_recipientNameCtrl.text.trim().isNotEmpty)
          'receiverName': _recipientNameCtrl.text.trim(),
        if (_recipientPhoneCtrl.text.trim().isNotEmpty)
          'receiverPhone': '+221${_recipientPhoneCtrl.text.trim()}',
        if (parts.isNotEmpty) 'description': parts.join(' · '),
        if (_estimate?['price'] != null)
          'price': (_estimate!['price'] as num).toDouble(),
        if (_estimate?['demFee'] != null)
          'demFee': (_estimate!['demFee'] as num).toDouble(),
        if (_scheduledAt != null)
          'scheduledAt': _scheduledAt!.toUtc().toIso8601String(),
        'paymentMode': _paymentMode,
        if (_selectedProAddr?['id'] != null)
          'proAddressId': _selectedProAddr!['id'],
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
            try {
              await _proRepo.confirmOrderRequest(_fromRequestId!, orderId);
            } catch (_) {}
          }();
        }
      }

      DemProDraftStorage.clearOrderDraft();
      if (mounted)
        context.pushReplacement('/dem-pro/orders/confirmation', extra: order);
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Validation ───────────────────────────────────────────────────────────

  bool get _canAdvance => switch (_step) {
    0 =>
      _deliveryLat != null &&
          isValidSenegalMobile(_recipientPhoneCtrl.text.trim()),
    1 || 2 || 3 => true,
    _ => false,
  };

  String get _stepError => switch (_step) {
    0 =>
      _deliveryLat == null
          ? 'Définissez la destination sur la carte'
          : 'Numéro mobile invalide (7X XXX XX XX)',
    _ => '',
  };

  void _next() {
    FocusScope.of(context).unfocus();
    if (!_canAdvance) {
      showDemToast(context, _stepError, isError: true);
      return;
    }
    if (_step == 3) {
      _fetchEstimate();
      _fetchRoute();
    }
    setState(() => _step++);
  }

  // Sur la première étape, un simple `pop()` laisserait l'utilisateur sans
  // sortie s'il n'y a rien à dépiler (écran atteint sans pile de navigation,
  // ex. lien profond) — on retombe alors sur le tableau de bord DEM Pro.
  void _back() {
    if (_step == 0) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(appStartupNotifier.homeForRole);
      }
      return;
    }
    setState(() => _step--);
  }

  // Retourne directement à la première étape — conserve les données déjà
  // saisies (contrairement à un vrai reset du formulaire), simple
  // raccourci de navigation.
  void _resetToStart() {
    if (_step == 0) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = 0);
  }

  // ── Map markers / polyline ────────────────────────────────────────────────

  Set<Marker> get _markers {
    final m = <Marker>{};
    if (_pickupLat != null)
      m.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(_pickupLat!, _pickupLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: const InfoWindow(title: 'Départ'),
        ),
      );
    if (_deliveryLat != null)
      m.add(
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(_deliveryLat!, _deliveryLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    return m;
  }

  Set<Polyline> get _polylines {
    if (_pickupLat == null || _deliveryLat == null || _step < 4) return {};
    final pts = _routePoints.isNotEmpty
        ? _routePoints
        : [
            LatLng(_pickupLat!, _pickupLng!),
            LatLng(_deliveryLat!, _deliveryLng!),
          ];
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: pts,
        color: AppColors.primary,
        width: 4,
      ),
    };
  }

  Future<void> _fetchRoute() async {
    if (_pickupLat == null || _deliveryLat == null) return;
    final origin = LatLng(_pickupLat!, _pickupLng!);
    final dest = LatLng(_deliveryLat!, _deliveryLng!);
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
    if (points.length == 1) {
      _centerMapVisible(points.first);
      return;
    }

    var south = points.first.latitude, north = points.first.latitude;
    var west = points.first.longitude, east = points.first.longitude;
    for (final p in points.skip(1)) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }

    final screenH = MediaQuery.of(context).size.height;
    final panelH = _panelHeight + MediaQuery.of(context).viewPadding.bottom;
    final hiddenFrac = (panelH / screenH).clamp(0.05, 0.85);
    final visibleFrac = (1 - hiddenFrac).clamp(0.15, 0.95);
    final latSpan = (north - south).clamp(0.0015, 1.0);
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

  // Hauteur réelle du panneau — mesurée (voir _sheetHeight), avec un
  // fallback par step avant la toute première mesure. Sert à la fois à
  // cadrer la caméra ET au layout du panneau lui-même (voir build()).
  double get _panelHeight {
    if (_sheetHeight != null) return _sheetHeight!;
    final h = MediaQuery.of(context).size.height;
    return h *
        switch (_step) {
          3 => 0.5, // Livraison
          4 => 0.62, // Confirmation
          _ => 0.4,
        };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _measureSheetHeight();
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Carte
            Positioned.fill(
              child: GoogleMap(
                // Recale sur le point pertinent dès que le contrôleur devient
                // disponible — nécessaire pour "Recommander cette commande"
                // (_applyReorder), qui préremplit la destination en
                // synchrone dans initState, bien avant que la carte existe.
                onMapCreated: (c) {
                  _mapCtrl = c;
                  if (_deliveryLat != null) {
                    _centerMapVisible(LatLng(_deliveryLat!, _deliveryLng!));
                  } else if (_pickupLat != null) {
                    _centerMapVisible(LatLng(_pickupLat!, _pickupLng!));
                  }
                },
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
              ),
            ),

            // Pin central
            if (_isMapPlacement)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _placingPickup
                          ? Icons.inventory_2_rounded
                          : Icons.location_on,
                      color: _placingPickup
                          ? AppColors.warning
                          : AppColors.success,
                      size: 40,
                      shadows: const [
                        Shadow(color: Colors.black26, blurRadius: 8),
                      ],
                    ),
                    const SizedBox(height: 2),
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: _placingPickup
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ],
                ),
              ),

            // Header
            if (!_isMapPlacement)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(child: _buildHeader()),
              ),

            // Panel bas — placement
            if (_isMapPlacement)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 130 + MediaQuery.of(context).viewPadding.bottom,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientSplash,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: _buildPlacementPanel(),
                ),
              ),

            // Panel bas (infos + CTA) — hauteur qui épouse son contenu au
            // lieu d'une fraction d'écran fixe (l'ancienne
            // DraggableScrollableSheet laissait un grand vide entre le
            // contenu court d'une étape et le bouton CTA). Le fond reste
            // ancré au bas de l'écran en toutes circonstances (jamais
            // décalé par le clavier) : seul le CONTENU interne remonte
            // au-dessus du clavier via un padding animé local, ce qui fait
            // grandir le panneau vers le haut de façon naturelle. Une
            // hauteur max sert de garde-fou : au-delà, le contenu défile en
            // interne (étape Confirmation) plutôt que de déborder.
            if (!_isMapPlacement)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                // `Clip.none` laisse le bouton retour flottant déborder
                // au-dessus du panneau (dans la zone carte) sans être
                // rogné par les coins arrondis du panneau lui-même.
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.86,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientSplash,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: AnimatedPadding(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSheetHandle(),
                              // `Flexible` ici forçait le panneau à toujours
                              // grandir jusqu'au ConstrainedBox(maxHeight:
                              // 0.86*écran) ci-dessus, quel que soit le
                              // contenu réel de l'étape (voir _panelHeight
                              // et le diagnostic pré-prod) — AnimatedSize
                              // fait maintenant épouser la vraie hauteur du
                              // contenu, avec transition douce entre steps.
                              Container(
                                key: _sheetKey,
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: SingleChildScrollView(
                                    child: _buildPanel(),
                                  ),
                                ),
                              ),
                              _buildNavButtons(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -22,
                      left: 20,
                      child: _buildFloatingBackButton(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Poignée décorative centrée en haut du panneau — le bouton retour vit
  // à part, flottant au-dessus du panneau (plus visible).
  Widget _buildSheetHandle() => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );

  // Bouton retour flottant, à cheval sur le bord haut du panneau (dans la
  // zone carte) pour être plus visible qu'une icône noyée dans l'en-tête
  // du panneau.
  Widget _buildFloatingBackButton() => GestureDetector(
    onTap: _back,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.arrow_back, color: AppColors.primary, size: 22),
    ),
  );

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
    child: Row(
      children: [
        IconButton(
          onPressed: _resetToStart,
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: AppColors.gradientSplash,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isScheduled
                          ? 'Programmer une livraison'
                          : widget.priority == 'EXPRESS'
                          ? 'Livraison Express ⚡'
                          : 'Nouvelle livraison',
                      style: ClientText.subtitle.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    Text(
                      _stepMeta[_step].$3,
                      style: ClientText.label.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: List.generate(
                    _stepMeta.length,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i < _stepMeta.length - 1 ? 4 : 0,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 3,
                          decoration: BoxDecoration(
                            color: i <= _step
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  // ── Panel placement ───────────────────────────────────────────────────────

  Widget _buildPlacementPanel() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _placingPickup
                ? 'Positionnez le point de départ'
                : 'Positionnez la destination',
            style: ClientText.bodyStrong.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _geocoding ? null : _confirmPlacement,
                  child: Center(
                    child: _geocoding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Confirmer la position',
                            style: ClientText.button.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Panel principal ───────────────────────────────────────────────────────

  // Le CTA (bouton Suivant/Confirmer) n'appartient pas à ce panneau — il est
  // pinné en dehors, sous le `SingleChildScrollView` qui héberge ce contenu
  // (voir `build`), pour rester toujours visible même quand le contenu
  // défile en interne. Un tap dans une zone vide referme le clavier.
  Widget _buildPanel() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => FocusScope.of(context).unfocus(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Bandeau départ ───────────────────────────────────────────────────
        // Uniquement à l'étape Destination — répété sur chaque étape suivante,
        // c'était redondant (le récap final montre déjà le trajet complet).
        if (_step == 0)
          _DepartureBanner(
            fixedLabel: 'EXPÉDITION',
            placeholder: 'Choisir le lieu d\'expédition',
            proLabel: _selectedProAddr?['label'] as String?,
            address: _pickupAddress,
            loading: _loadingGps,
            onTap: () => _showChangeDeparture(),
          ),

        // ── Titre étape ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
          child: Row(
            children: [
              Icon(_stepMeta[_step].$1, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                _stepMeta[_step].$2,
                style: ClientText.title.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),

        // ── Contenu ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) {
                0 => _buildStep0(),
                1 => _buildStepArticles(),
                2 => _buildStepColis(),
                3 => _buildStepLivraison(),
                _ => _buildStep2(),
              },
            ),
          ),
        ),
      ],
    ),
  );

  // ── Étape 0 — Destination ─────────────────────────────────────────────────

  Widget _buildStep0() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Bandeau destination — même comportement que le bandeau expédition
      // (adresse préenregistrée / position actuelle / saisie manuelle /
      // pointer sur la carte), au lieu d'un champ de recherche isolé sans les
      // 3 autres façons de renseigner l'adresse.
      _DepartureBanner(
        fixedLabel: 'DESTINATION',
        placeholder: 'Choisir l\'adresse de destination',
        address: _deliveryAddress,
        loading: false,
        onTap: () => _showChangeDestination(),
      ),
      const SizedBox(height: 14),

      Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),
      const SizedBox(height: 14),

      _FieldLabel('Nom du client (optionnel)'),
      const SizedBox(height: 6),
      _ProTextField(
        controller: _recipientNameCtrl,
        hint: 'Nom du client',
        textInputAction: TextInputAction.next,
        onChanged: (_) => _scheduleDraftSave(),
      ),
      const SizedBox(height: 14),

      _FieldLabel('Téléphone du client *'),
      const SizedBox(height: 6),
      _ProTextField(
        controller: _recipientPhoneCtrl,
        hint: 'Numéro de téléphone',
        prefix: '+221 ',
        keyboardType: TextInputType.phone,
        maxLength: 9,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        onChanged: (_) {
          setState(() {});
          _scheduleDraftSave();
        },
        suffixIcon: _recipientPhoneCtrl.text.isEmpty
            ? null
            : Icon(
                isValidSenegalMobile(_recipientPhoneCtrl.text.trim())
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: isValidSenegalMobile(_recipientPhoneCtrl.text.trim())
                    ? AppColors.success
                    : AppColors.error,
                size: 18,
              ),
      ),
    ],
  );

  // ── Étape 1 — Colis ──────────────────────────────────────────────────────

  // ── Catalogue produits ────────────────────────────────────────────────────

  Future<void> _openProductPicker() async {
    final product = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductPickerSheet(
        repo: _proRepo,
        proAddressId: _selectedProAddr?['id'] as String?,
      ),
    );
    if (product == null) return;

    final name = product['name'] as String? ?? '';
    final price = product['defaultPrice'] as num?;
    final id = product['id'] as String?;
    setState(() {
      // Réutilise la dernière ligne si elle est encore vide (cas le plus
      // fréquent : premier article de la commande) plutôt que d'empiler une
      // ligne vide au-dessus de celle choisie dans le catalogue.
      final last = _articles.isNotEmpty ? _articles.last : null;
      final target = (last != null && last.nameCtrl.text.trim().isEmpty)
          ? last
          : _Article();
      if (!identical(target, last)) _articles.add(target);
      target.nameCtrl.text = name;
      target.priceCtrl.text = price != null ? price.toInt().toString() : '';
      target.productId = id;
    });
    _scheduleDraftSave();

    if (id != null) _proRepo.incrementProductUsage(id);
  }

  // ── Étape 1 — Articles ───────────────────────────────────────────────────

  Widget _buildStepArticles() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ── Articles ──────────────────────────────────────────────────────────
      const _FieldLabel('Articles'),
      const SizedBox(height: 10),
      // Une seule ligne compacte par article (badge + nom + qté + prix +
      // retirer) au lieu de 2 lignes empilées — une commande de 10+ articles
      // (le max autorisé) reste raisonnablement scrollable au lieu de
      // s'étirer sur des écrans entiers.
      ...List.generate(_articles.length, (i) {
        final a = _articles[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  '${i + 1}',
                  style: ClientText.micro.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProTextField(
                  controller: a.nameCtrl,
                  hint: 'Produit',
                  onChanged: (_) => _scheduleDraftSave(),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 52,
                child: _ProTextField(
                  controller: a.qtyCtrl,
                  hint: 'Qté',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _scheduleDraftSave(),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 84,
                child: _ProTextField(
                  controller: a.priceCtrl,
                  hint: 'Prix',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _scheduleDraftSave(),
                ),
              ),
              if (_articles.length > 1) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _articles[i].dispose();
                      _articles.removeAt(i);
                    });
                    _scheduleDraftSave();
                  },
                  child: const Icon(
                    Icons.remove_circle_outline,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
        );
      }),
      if (_articles.length < 10)
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _openProductPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Catalogue',
                        style: ClientText.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _articles.add(_Article()));
                  _scheduleDraftSave();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Ajouter',
                        style: ClientText.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    ],
  );

  // ── Étape 2 — Colis ──────────────────────────────────────────────────────

  Widget _buildStepColis() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ── Type de colis ─────────────────────────────────────────────────────
      const _FieldLabel('Type de colis'),
      const SizedBox(height: 10),
      ..._packageTypes.map(
        (t) => _PackageTypeRow(
          type: t.$1,
          label: t.$2,
          icon: t.$3,
          subtitle: t.$4,
          selected: _packageType == t.$1,
          onTap: () {
            setState(() => _packageType = t.$1);
            _scheduleDraftSave();
          },
        ),
      ),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: SwitchListTile(
          value: _isFragile,
          onChanged: (v) {
            setState(() => _isFragile = v);
            _scheduleDraftSave();
          },
          activeTrackColor: AppColors.warning,
          activeThumbColor: Colors.white,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_outlined,
                color: AppColors.warning,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Fragile',
                style: ClientText.subtitle.copyWith(color: Colors.white),
              ),
            ],
          ),
          subtitle: Text(
            'Le livreur sera notifié de faire attention',
            style: ClientText.label.copyWith(color: Colors.white),
          ),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
        ),
      ),
    ],
  );

  // ── Étape 3 — Livraison (paiement, instructions, programmation) ────────────

  Widget _buildStepLivraison() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ── Paiement ──────────────────────────────────────────────────────────
      const _FieldLabel('Qui paie la livraison ?'),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _paymentMode = 'merchant');
                _scheduleDraftSave();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: _paymentMode == 'merchant' ? 0.24 : 0.14,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: _paymentMode == 'merchant' ? 0.6 : 0.25,
                    ),
                    width: _paymentMode == 'merchant' ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Je paie',
                      style: ClientText.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Paiement en ligne',
                      style: ClientText.micro.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _paymentMode = 'cod');
                _scheduleDraftSave();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: _paymentMode == 'cod' ? 0.24 : 0.14,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: _paymentMode == 'cod' ? 0.6 : 0.25,
                    ),
                    width: _paymentMode == 'cod' ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Client paie',
                      style: ClientText.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'À la livraison',
                      style: ClientText.micro.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),
      const SizedBox(height: 14),

      // ── Instructions ──────────────────────────────────────────────────────
      _FieldLabel('Instructions pour le livreur (optionnel)'),
      const SizedBox(height: 6),
      _ProTextField(
        controller: _instructionsCtrl,
        hint: 'ex: Appeler à l\'arrivée…',
        maxLines: 3,
        onChanged: (_) => _scheduleDraftSave(),
      ),

      // ── Livraison programmée (uniquement si lancé depuis "Programmer") ──
      // Un interrupteur marche/arrêt n'a pas de sens ici — cet écran n'est
      // atteint QUE via l'entrée "Programmée", programmer n'est donc jamais
      // optionnel dans ce flux (contrairement à Simple/Express, qui n'a pas
      // cette section du tout). On affiche directement la date choisie,
      // modifiable au tap.
      if (widget.scheduled) ...[
        const SizedBox(height: 16),
        Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.schedule, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Livraison programmée',
              style: ClientText.subtitle.copyWith(color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickScheduleDate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _scheduledAt != null
                    ? AppColors.primary
                    : AppColors.warning,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: _scheduledAt != null
                      ? AppColors.primary
                      : AppColors.warning,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _scheduledAt != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fmtDate(_scheduledAt!),
                              style: ClientText.subtitle.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              _fmtTime(_scheduledAt!),
                              style: ClientText.label.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'Appuyez pour choisir la date',
                          style: ClientText.bodyStrong.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                ),
                Icon(
                  Icons.edit_outlined,
                  color: _scheduledAt != null
                      ? Colors.white.withValues(alpha: 0.75)
                      : AppColors.warning,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  // ── Étape 2 — Confirmation ────────────────────────────────────────────────

  Widget _buildStep2() {
    final totalClient = (_estimate?['totalClient'] as num?)?.toInt();
    final price = (_estimate?['price'] as num?)?.toInt();
    final demFee = (_estimate?['demFee'] as num?)?.toInt() ?? 0;
    final dist = (_estimate?['distanceKm'] as num?)?.toStringAsFixed(1);
    final dur = (_estimate?['durationMin'] as num?)?.toInt();
    final total = totalClient ?? (price != null ? price + demFee : null);
    // Valeur totale des articles (prix unitaire × quantité, additionnés) —
    // distincte du prix de la livraison ci-dessous : la livraison peut être
    // payée par le client final à la réception, la valeur des articles
    // reste une information pour le commerçant (facturation/suivi).
    final articlesTotal = _articles.fold<int>(0, (sum, a) {
      final unitPrice = int.tryParse(a.priceCtrl.text.trim());
      if (unitPrice == null) return sum;
      final qty = int.tryParse(a.qtyCtrl.text.trim()) ?? 1;
      return sum + unitPrice * qty;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Résumé trajet
        StaggeredEntrance(
          index: 0,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                _RouteRow(
                  icon: Icons.location_on,
                  color: AppColors.primary,
                  label: _selectedProAddr != null
                      ? '${_selectedProAddr!['label']} — $_pickupAddress'
                      : _pickupAddress.isNotEmpty
                      ? _pickupAddress
                      : 'Départ',
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Column(
                    children: List.generate(
                      3,
                      (_) => Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        width: 2,
                        height: 6,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                _RouteRow(
                  icon: Icons.flag,
                  color: AppColors.error,
                  label: _deliveryAddress.isNotEmpty
                      ? _deliveryAddress
                      : 'Destination',
                ),
                if (_recipientNameCtrl.text.trim().isNotEmpty ||
                    _recipientPhoneCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.25),
                    height: 1,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: Colors.white.withValues(alpha: 0.75),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          [
                            if (_recipientNameCtrl.text.trim().isNotEmpty)
                              _recipientNameCtrl.text.trim(),
                            if (_recipientPhoneCtrl.text.trim().isNotEmpty)
                              '+221 ${_recipientPhoneCtrl.text.trim()}',
                          ].join(' · '),
                          style: ClientText.label.copyWith(color: Colors.white),
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

        // Détails (colis + paiement) — regroupés en une seule carte compacte
        StaggeredEntrance(
          index: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _packageTypes.firstWhere((t) => t.$1 == _packageType).$3,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _packageTypes.firstWhere((t) => t.$1 == _packageType).$2,
                      style: ClientText.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    if (_isFragile) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Fragile',
                          style: ClientText.micro.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Divider(color: Colors.white.withValues(alpha: 0.18), height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      _paymentMode == 'merchant'
                          ? Icons.storefront_outlined
                          : Icons.payments_outlined,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _paymentMode == 'merchant'
                          ? 'Vous payez la livraison'
                          : 'Le client paie à la livraison',
                      style: ClientText.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Articles
        if (_articles.any((a) => a.nameCtrl.text.trim().isNotEmpty))
          StaggeredEntrance(
            index: 2,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Articles',
                        style: ClientText.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._articles
                      .where((a) => a.nameCtrl.text.trim().isNotEmpty)
                      .map((a) {
                        final qty = int.tryParse(a.qtyCtrl.text.trim()) ?? 1;
                        final unitPrice = int.tryParse(a.priceCtrl.text.trim());
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text(
                                '•  ',
                                style: ClientText.label.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${a.nameCtrl.text.trim()} × $qty',
                                  style: ClientText.label.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (unitPrice != null)
                                Text(
                                  formatFcfa(unitPrice * qty),
                                  style: ClientText.label.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                  if (articlesTotal > 0) ...[
                    const SizedBox(height: 6),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.25),
                      height: 1,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Total articles',
                          style: ClientText.bodyStrong.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatFcfa(articlesTotal),
                          style: ClientText.bodyStrong.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Créneau programmé
        if (_scheduledAt != null)
          StaggeredEntrance(
            index: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Livraison programmée',
                        style: ClientText.micro.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        '${_fmtDate(_scheduledAt!)} à ${_fmtTime(_scheduledAt!)}',
                        style: ClientText.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),

        // Prix
        if (_loadingEstimate)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          )
        else if (total != null)
          StaggeredEntrance(
            index: 4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Ne s'affiche que si une valeur d'articles est montrée
                  // juste au-dessus — sinon ce prix est la seule somme à
                  // l'écran, pas besoin de préciser de quoi il s'agit.
                  if (articlesTotal > 0) ...[
                    Text(
                      'FRAIS DE LIVRAISON',
                      style: ClientText.label.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  // Le livreur touche toujours `total` en entier — la réduction ne
                  // change que ce que DEM Pro/le destinataire paie réellement (voir
                  // orders.service.js:confirmPayment côté serveur).
                  if (_discountAmount != null && _discountAmount! > 0) ...[
                    Text(
                      formatFcfa(total),
                      style: ClientText.label.copyWith(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatFcfa(
                        (total - _discountAmount!).clamp(0, double.infinity),
                      ),
                      style: ClientText.hero.copyWith(color: AppColors.success),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _promoLabel != null
                          ? 'Réduction appliquée ($_promoLabel)'
                          : 'Réduction appliquée',
                      style: ClientText.label.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ] else
                    Text(
                      formatFcfa(total),
                      style: ClientText.hero.copyWith(color: AppColors.primary),
                    ),
                  if (dist != null || dur != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (dist != null) '$dist km',
                        if (dur != null) '~$dur min',
                      ].join(' · '),
                      style: ClientText.label.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          GestureDetector(
            onTap: _fetchEstimate,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.refresh, color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Impossible de calculer le prix. Appuyez pour réessayer.',
                      style: ClientText.label.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (total != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoCodeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: ClientText.body.copyWith(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Code promo (optionnel)',
                    hintStyle: ClientText.label.copyWith(color: Colors.white),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.14),
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
                onTap: _checkingPromo ? null : _applyPromoCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: (_discountAmount != null && _discountAmount! > 0)
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _checkingPromo
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Text(
                          (_discountAmount != null && _discountAmount! > 0)
                              ? 'Appliqué ✓'
                              : 'Appliquer',
                          style: ClientText.bodyStrong.copyWith(
                            color:
                                (_discountAmount != null &&
                                    _discountAmount! > 0)
                                ? AppColors.success
                                : AppColors.primary,
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (_promoError != null) ...[
            const SizedBox(height: 4),
            Text(
              _promoError!,
              style: ClientText.label.copyWith(color: AppColors.error),
            ),
          ],
        ],

        // Montant réel que le livreur doit récupérer auprès du client final —
        // valeur des articles + frais de livraison (remise déduite). Ne
        // s'affiche qu'en paiement à la livraison : en mode "vous payez la
        // livraison", le commerçant règle les frais lui-même, ce total
        // combiné n'a pas de sens pour lui.
        if (_paymentMode == 'cod' && articlesTotal > 0 && total != null) ...[
          const SizedBox(height: 10),
          StaggeredEntrance(
            index: 5,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Total à collecter au client',
                      style: ClientText.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    formatFcfa(
                      articlesTotal +
                          (total - (_discountAmount ?? 0)).clamp(
                            0,
                            double.infinity,
                          ),
                    ),
                    style: ClientText.hero.copyWith(color: AppColors.success),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Boutons navigation ────────────────────────────────────────────────────

  Widget _buildNavButtons() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: _step < 4
          ? Row(
              children: [
                if (_step > 0) ...[
                  Expanded(
                    flex: 1,
                    child: _NavBtn(
                      label: 'Précédent',
                      outline: true,
                      onTap: _back,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: _NavBtn(
                    label: 'Suivant',
                    onTap: _canAdvance ? _next : null,
                  ),
                ),
              ],
            )
          : _NavBtn(
              label: _scheduledAt != null
                  ? 'Programmer la livraison'
                  : 'Confirmer et envoyer',
              loading: _submitting,
              onTap: _submitting ? null : _submit,
            ),
    ),
  );

  // ── Picker date/heure livraison programmée ───────────────────────────────

  // Thème dégradé cyan pour les pickers natifs date/heure — `surface`
  // transparent laisse le dégradé du Container englobant traverser tout
  // l'intérieur du dialogue (grille du calendrier, cadran de l'heure),
  // `dialogTheme.backgroundColor` transparent retire le fond uni foncé que
  // Flutter peint par défaut derrière. Le rayon doit suivre celui du
  // dialogue Material 3 (28) sinon le dégradé dépasse en carré aux coins
  // arrondis.
  Widget _gradientPickerTheme(Widget? child) => Theme(
    data: ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: Colors.transparent,
        onSurface: Colors.white,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    ),
    child: Container(
      decoration: BoxDecoration(
        gradient: AppColors.gradientSplash,
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    ),
  );

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final minDate = now.add(const Duration(minutes: 10));

    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? minDate,
      firstDate: minDate,
      lastDate: now.add(const Duration(days: 30)),
      builder: (ctx, child) => _gradientPickerTheme(child),
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
      builder: (ctx, child) => _gradientPickerTheme(child),
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
    _scheduleDraftSave();
  }

  static String _fmtDate(DateTime dt) {
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
      builder: (_) => _ChangeAddressSheet(
        title: 'Point de départ',
        searchHint: 'Saisir l\'adresse d\'expédition…',
        proAddresses: _proAddresses,
        selectedId: _selectedProAddr?['id'] as String?,
        loadingGps: _loadingGps,
        dio: _publicDio,
        onSelect: (addr) {
          Navigator.pop(context);
          _applyProAddress(addr);
        },
        onGps: () {
          Navigator.pop(context);
          _fetchGps();
        },
        onMap: () {
          Navigator.pop(context);
          _enterMapPlacement(forPickup: true);
        },
        onManualAddress: (lat, lng, address) {
          Navigator.pop(context);
          _applyManualPickup(lat, lng, address);
        },
      ),
    );
  }

  void _showChangeDestination() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChangeAddressSheet(
        title: 'Adresse de destination',
        searchHint: 'Saisir l\'adresse de livraison…',
        proAddresses: _proAddresses,
        selectedId: null,
        loadingGps: _loadingGps,
        dio: _publicDio,
        onSelect: (addr) {
          Navigator.pop(context);
          _applyProAddressAsDelivery(addr);
        },
        onGps: () {
          Navigator.pop(context);
          _fetchGps(forPickup: false);
        },
        onMap: () {
          Navigator.pop(context);
          _enterMapPlacement(forPickup: false);
        },
        onManualAddress: (lat, lng, address) {
          Navigator.pop(context);
          _applyManualDelivery(lat, lng, address);
        },
        recentAddresses: _recentDestinations,
        onSelectRecent: (d) {
          Navigator.pop(context);
          _applyRecentDestination(d);
        },
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
    if (_step == 4) {
      _fetchEstimate();
      _fetchRoute();
    } else {
      _centerMapVisible(LatLng(lat, lng));
    }
    _scheduleDraftSave();
  }

  void _applyManualDelivery(double lat, double lng, String address) {
    setState(() {
      _deliveryLat = lat;
      _deliveryLng = lng;
      _deliveryAddress = address;
      _addressSearchCtrl.text = address;
    });
    if (_step == 4) {
      _fetchEstimate();
      _fetchRoute();
    } else {
      _centerMapVisible(LatLng(lat, lng));
    }
    _scheduleDraftSave();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget bandeau départ / destination
// ─────────────────────────────────────────────────────────────────────────────

class _DepartureBanner extends StatelessWidget {
  // Libellé fixe ("EXPÉDITION"/"DESTINATION") — toujours affiché, distinct
  // du nom de l'adresse pro éventuellement sélectionnée (proLabel).
  final String fixedLabel;
  final String placeholder;
  final String? proLabel;
  final String address;
  final bool loading;
  final VoidCallback onTap;
  const _DepartureBanner({
    required this.fixedLabel,
    required this.placeholder,
    this.proLabel,
    required this.address,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 24, bottom: 6),
        child: Text(
          fixedLabel,
          style: ClientText.micro.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: loading
                    ? Text(
                        'Localisation en cours…',
                        style: ClientText.body.copyWith(color: Colors.white),
                      )
                    : Text(
                        proLabel != null
                            ? '$proLabel — $address'
                            : (address.isNotEmpty ? address : placeholder),
                        style: ClientText.body.copyWith(
                          color: address.isNotEmpty || proLabel != null
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.65),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.75),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet — changer une adresse (expédition ou destination) : même choix des 4
// façons de la renseigner des deux côtés (adresse préenregistrée, position
// actuelle, saisie manuelle, pointer sur la carte) — un seul composant pour
// ne pas faire diverger les deux champs.
// ─────────────────────────────────────────────────────────────────────────────

class _ChangeAddressSheet extends StatefulWidget {
  final String title;
  final String searchHint;
  final List<Map<String, dynamic>> proAddresses;
  final String? selectedId;
  final bool loadingGps;
  final Dio dio;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onGps;
  final VoidCallback onMap;
  final void Function(double lat, double lng, String address) onManualAddress;
  // Destinations récentes — uniquement côté destination (null côté départ).
  final List<Map<String, dynamic>>? recentAddresses;
  final void Function(Map<String, dynamic>)? onSelectRecent;
  const _ChangeAddressSheet({
    required this.title,
    required this.searchHint,
    required this.proAddresses,
    required this.selectedId,
    required this.loadingGps,
    required this.dio,
    required this.onSelect,
    required this.onGps,
    required this.onMap,
    required this.onManualAddress,
    this.recentAddresses,
    this.onSelectRecent,
  });

  @override
  State<_ChangeAddressSheet> createState() => _ChangeAddressSheetState();
}

class _ChangeAddressSheetState extends State<_ChangeAddressSheet> {
  static const _iconMap = {
    'store': Icons.storefront_outlined,
    'warehouse': Icons.warehouse_outlined,
    'office': Icons.business_outlined,
    'home': Icons.home_outlined,
    'other': Icons.place_outlined,
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
      setState(() {
        _searching = true;
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
            _searching = false;
          });
      } catch (e) {
        if (mounted)
          setState(() {
            _searching = false;
            _searchError = friendlyError(e);
          });
      }
    });
  }

  void _retrySearch() => _onChanged(_searchCtrl.text);

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
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
      final locations = await geo
          .locationFromAddress('$query, Dakar, Sénégal')
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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        gradient: AppColors.gradientSplash,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Text(
              widget.title,
              style: ClientText.title.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 14),

            // Recherche manuelle avec autocomplete
            TextField(
              controller: _searchCtrl,
              style: ClientText.body.copyWith(color: Colors.white),
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _submitManual,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: ClientText.label.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                prefixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.search,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 18,
                      ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
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
              Text(
                'Mes adresses',
                style: ClientText.micro.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 8),
              ...widget.proAddresses.map((a) {
                final isSelected = a['id'] == widget.selectedId;
                final icon =
                    _iconMap[a['icon'] as String? ?? 'other'] ??
                    Icons.place_outlined;
                return GestureDetector(
                  onTap: () => widget.onSelect(a),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: isSelected ? 0.24 : 0.14,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: isSelected ? 0.6 : 0.25,
                        ),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a['label'] as String? ?? '',
                                style: ClientText.bodyStrong.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                a['address'] as String? ?? '',
                                style: ClientText.label.copyWith(
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],

            // Destinations récentes — uniquement côté destination.
            if (widget.recentAddresses != null &&
                widget.recentAddresses!.isNotEmpty) ...[
              Text(
                'Destinations récentes',
                style: ClientText.micro.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 8),
              ...widget.recentAddresses!.map((d) {
                final address = d['address'] as String? ?? '';
                final name = d['receiverName'] as String?;
                return GestureDetector(
                  onTap: () => widget.onSelectRecent?.call(d),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                address,
                                style: ClientText.bodyStrong.copyWith(
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (name != null && name.isNotEmpty)
                                Text(
                                  name,
                                  style: ClientText.label.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],

            // Actions alternatives
            _SheetAction(
              icon: Icons.my_location,
              label: 'Ma position actuelle',
              loading: widget.loadingGps,
              onTap: widget.onGps,
            ),
            const SizedBox(height: 8),
            _SheetAction(
              icon: Icons.map_outlined,
              label: 'Pointer sur la carte',
              onTap: widget.onMap,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _SheetAction({
    required this.icon,
    required this.label,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          : Row(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: ClientText.bodyStrong.copyWith(color: Colors.white),
                ),
              ],
            ),
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
  const _DraftResumeSheet({
    required this.savedAt,
    required this.onResume,
    required this.onDiscard,
  });

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
        gradient: AppColors.gradientSplash,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, color: Colors.white, size: 32),
          const SizedBox(height: 12),
          Text(
            'Reprendre votre brouillon ?',
            style: ClientText.title.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            _label,
            textAlign: TextAlign.center,
            style: ClientText.label.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDiscard,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Nouvelle livraison',
                    style: ClientText.bodyStrong.copyWith(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onResume,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Reprendre',
                    style: ClientText.button.copyWith(color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      Text(text, style: ClientText.label.copyWith(color: Colors.white));
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
  const _ProTextField({
    required this.controller,
    required this.hint,
    this.prefix,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
    this.suffixIcon,
    this.textInputAction,
    this.onSubmitted,
  });

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
    style: ClientText.body.copyWith(fontSize: 14, color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: ClientText.label.copyWith(
        color: Colors.white.withValues(alpha: 0.7),
      ),
      prefixText: prefix,
      prefixStyle: ClientText.label.copyWith(fontSize: 14, color: Colors.white),
      suffixIcon: suffixIcon,
      counterText: '',
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Colors.white, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

class _PackageTypeRow extends StatelessWidget {
  final String type, label, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _PackageTypeRow({
    required this.type,
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: selected ? 0.24 : 0.14),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Colors.white.withValues(alpha: selected ? 0.6 : 0.25),
        width: selected ? 1.5 : 1,
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: selected ? 0.28 : 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: ClientText.subtitle.copyWith(color: Colors.white),
                    ),
                    Text(
                      subtitle,
                      style: ClientText.label.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _RouteRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: ClientText.body.copyWith(color: Colors.white),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _NavBtn extends StatelessWidget {
  final String label;
  final bool outline;
  final bool loading;
  final VoidCallback? onTap;
  const _NavBtn({
    required this.label,
    this.outline = false,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !loading;
    return SizedBox(
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: outline
              ? Colors.white.withValues(alpha: 0.14)
              : (disabled
                    ? Colors.white.withValues(alpha: 0.14)
                    : AppColors.primary),
          borderRadius: BorderRadius.circular(14),
          border: outline
              ? Border.all(color: Colors.white.withValues(alpha: 0.3))
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      label,
                      style: ClientText.button.copyWith(
                        color: outline
                            ? Colors.white
                            : (disabled
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : Colors.white),
                      ),
                    ),
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
  // Point de vente sélectionné pour le ramassage — null si adresse tapée
  // librement ou aucune sélectionnée. Ne filtre que si non-null : un
  // catalogue sans produit scopé à un site continue de tout montrer.
  final String? proAddressId;
  const _ProductPickerSheet({required this.repo, this.proAddressId});
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
    _search.addListener(
      () => setState(() => _query = _search.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _products = null;
      _loadFailed = false;
    });
    try {
      final products = await widget.repo.getProducts();
      if (mounted) setState(() => _products = products);
    } catch (_) {
      if (mounted)
        setState(() {
          _products = [];
          _loadFailed = true;
        });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _products ?? [];
    // Un produit scopé à un autre point de vente que celui choisi pour ce
    // ramassage n'a pas de stock disponible ici — pas la peine de l'afficher.
    // Non-scopé (proAddressId null) = disponible partout, jamais filtré.
    if (widget.proAddressId != null) {
      list = list
          .where(
            (p) =>
                p['proAddressId'] == null ||
                p['proAddressId'] == widget.proAddressId,
          )
          .toList();
    }
    if (_query.isEmpty) return list;
    return list
        .where(
          (p) => (p['name'] as String? ?? '').toLowerCase().contains(_query),
        )
        .toList();
  }

  // Au-delà de 3 produits visibles, la liste se limite à une hauteur fixe
  // (~3 lignes) et devient scrollable plutôt que d'étirer la feuille —
  // évite qu'un catalogue fourni n'occupe une portion excessive de l'écran.
  static const _kMaxVisibleItems = 3;
  static const _kItemHeight = 56.0;
  static const _kItemGap = 8.0;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.75,
    ),
    decoration: BoxDecoration(
      gradient: AppColors.gradientSplash,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      16 + MediaQuery.of(context).viewPadding.bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Choisir dans mon catalogue',
                style: ClientText.title.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/dem-pro/products'),
              child: Text(
                'Gérer',
                style: ClientText.label.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_products != null && _products!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: TextField(
              controller: _search,
              style: ClientText.body.copyWith(
                color: Colors.white,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Rechercher…',
                hintStyle: ClientText.body.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 18,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        Flexible(
          child: _products == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              : _loadFailed
              ? _buildMessage(
                  Icons.wifi_off_rounded,
                  'Impossible de charger le catalogue.',
                )
              : _filtered.isEmpty
              ? _buildMessage(
                  Icons.inventory_2_outlined,
                  _products!.isEmpty
                      ? 'Aucun produit enregistré pour l\'instant.\nAjoutez-en un depuis "Gérer".'
                      : 'Aucun résultat.',
                )
              : _filtered.length > _kMaxVisibleItems
              ? SizedBox(
                  height:
                      _kMaxVisibleItems * _kItemHeight +
                      (_kMaxVisibleItems - 1) * _kItemGap,
                  child: _buildProductList(),
                )
              : _buildProductList(),
        ),
      ],
    ),
  );

  Widget _buildProductList() => ListView.separated(
    shrinkWrap: true,
    itemCount: _filtered.length,
    separatorBuilder: (_, __) => const SizedBox(height: _kItemGap),
    itemBuilder: (_, i) {
      final p = _filtered[i];
      final price = p['defaultPrice'] as num?;
      return GestureDetector(
        onTap: () => Navigator.pop(context, p),
        child: Container(
          height: _kItemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  p['name'] as String? ?? '',
                  style: ClientText.bodyStrong.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (price != null) ...[
                const SizedBox(width: 8),
                Text(
                  formatFcfa(price),
                  style: ClientText.label.copyWith(color: AppColors.success),
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.7),
                size: 18,
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildMessage(IconData icon, String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 32),
        const SizedBox(height: 10),
        Text(
          msg,
          style: ClientText.body.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
