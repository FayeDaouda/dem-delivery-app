import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/utils/dem_toast.dart';
import '../../deliveries/data/orders_repository.dart';
import '../../home_driver/navigation/navigation_service.dart';
import '../data/dem_pro_repository.dart';
import '../theme/dem_pro_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────

const _dakar = LatLng(14.6937, -17.4441);

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
  const DemProOrderCreateScreen({super.key, this.scheduled = false});
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
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _searchDebounce;
  final _publicDio = Dio();

  // ── Étape 2 — Colis ─────────────────────────────────────────────────────
  String _packageType = 'small';
  final  _instructionsCtrl = TextEditingController();
  bool   _isFragile        = false;
  late bool _isScheduled = widget.scheduled;
  DateTime? _scheduledAt;

  // ── Articles ───────────────────────────────────────────────────────────
  final List<_Article> _articles = [_Article()];

  // ── Paiement ───────────────────────────────────────────────────────────
  String _paymentMode = 'merchant'; // 'merchant' | 'cod'

  // ── Étape 3 — Confirmation ──────────────────────────────────────────────
  Map<String, dynamic>? _estimate;
  bool _loadingEstimate = false;
  bool _submitting      = false;
  bool _geocoding       = false;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _loadProAddresses();
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _searchDebounce?.cancel();
    _recipientNameCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _landmarkCtrl.dispose();
    _addressSearchCtrl.dispose();
    _instructionsCtrl.dispose();
    for (final a in _articles) { a.dispose(); }
    super.dispose();
  }

  // ── Map style ────────────────────────────────────────────────────────────

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style_waze.json');
    if (mounted) setState(() => _mapStyle = style);
  }

  void _centerMap(LatLng pos) => _mapCtrl?.animateCamera(
    CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 15, tilt: 20)),
  );

  void _centerMapVisible(LatLng pos) {
    final screenH = MediaQuery.of(context).size.height;
    final panelH = _panelHeight + MediaQuery.of(context).viewPadding.bottom;
    final offsetLat = panelH / screenH * 0.006;
    final adjusted = LatLng(pos.latitude + offsetLat, pos.longitude);
    _mapCtrl?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: adjusted, zoom: 15, tilt: 20)),
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
    setState(() {
      _selectedProAddr = addr;
      _pickupAddress   = addr['address'] as String? ?? '';
      if (lat != null && lng != null) {
        _pickupLat = lat; _pickupLng = lng;
        _centerMapVisible(LatLng(lat, lng));
      }
    });
  }

  // ── GPS ──────────────────────────────────────────────────────────────────

  Future<void> _fetchGps() async {
    setState(() { _loadingGps = true; _selectedProAddr = null; });
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      _pickupLat = ll.latitude; _pickupLng = ll.longitude;
      _centerMap(ll);
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
    if (mounted) setState(() { _isMapPlacement = false; _geocoding = false; });
  }

  void _onAddressChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _searchingAddress = true);
      try {
        final res = await _publicDio.get(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json',
          queryParameters: {
            'input': query,
            'location': '14.6937,-17.4441',
            'radius': '60000',
            'components': 'country:sn',
            'language': 'fr',
            'key': AppConfig.mapsApiKey,
          },
        );
        if (mounted && res.statusCode == 200) {
          final preds = res.data['status'] == 'OK'
              ? List<Map<String, dynamic>>.from(res.data['predictions'])
              : <Map<String, dynamic>>[];
          setState(() { _suggestions = preds; _searchingAddress = false; });
        }
      } catch (_) {
        if (mounted) setState(() => _searchingAddress = false);
      }
    });
  }

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
      _centerMapVisible(LatLng(loc.latitude, loc.longitude));
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
    try {
      final res = await _publicDio.get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'fields': 'geometry,name,formatted_address',
          'language': 'fr',
          'key': AppConfig.mapsApiKey,
        },
      );
      if (res.statusCode == 200 && res.data['status'] == 'OK') {
        final loc = res.data['result']['geometry']['location'];
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
        _centerMapVisible(LatLng(lat, lng));
      }
    } catch (_) {
      if (mounted) showDemToast(context, 'Impossible de charger l\'adresse', isError: true);
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

  Future<void> _fetchEstimate() async {
    if (_pickupLat == null || _deliveryLat == null) return;
    setState(() { _loadingEstimate = true; _estimate = null; });
    final est = await _ordersRepo.getEstimate(
      pickupLat: _pickupLat!,    pickupLng: _pickupLng!,
      deliveryLat: _deliveryLat!, deliveryLng: _deliveryLng!,
      orderType: 'DELIVERY',
    );
    if (mounted) setState(() { _estimate = est; _loadingEstimate = false; });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final parts = <String>[];
      final pkg = _packageTypes.firstWhere((p) => p.$1 == _packageType);
      parts.add(pkg.$2);
      if (_isFragile) parts.add('⚠️ Fragile');
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
      });

      if (_selectedProAddr != null) {
        _proRepo.incrementAddressUsage(_selectedProAddr!['id'] as String);
      }

      if (mounted) context.pushReplacement('/dem-pro/orders/confirmation', extra: order);
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Validation ───────────────────────────────────────────────────────────

  bool get _canAdvance => switch (_step) {
    0 => _deliveryLat != null && _recipientPhoneCtrl.text.trim().length == 9,
    1 => true,
    _ => false,
  };

  String get _stepError => switch (_step) {
    0 => _deliveryLat == null
        ? 'Définissez la destination sur la carte'
        : 'Le numéro doit contenir exactement 9 chiffres',
    _ => '',
  };

  void _next() {
    if (!_canAdvance) { showDemToast(context, _stepError, isError: true); return; }
    if (_step == 1) _fetchEstimate();
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
    return {Polyline(
      polylineId: const PolylineId('route'),
      points: [LatLng(_pickupLat!, _pickupLng!), LatLng(_deliveryLat!, _deliveryLng!)],
      color: DemProColors.accent,
      width: 3,
      patterns: [PatternItem.dash(16), PatternItem.gap(8)],
    )};
  }

  double get _panelHeight {
    if (_isMapPlacement) return 130;
    final h = MediaQuery.of(context).size.height;
    return switch (_step) {
      1 => h * 0.58,
      2 => h * 0.58,
      _ => h * 0.56,
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DemProColors.bg,
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

        // Panel bas
        Positioned(bottom: 0, left: 0, right: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            height: _panelHeight + MediaQuery.of(context).viewPadding.bottom,
            decoration: BoxDecoration(
              color: DemProColors.bg2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: _isMapPlacement ? _buildPlacementPanel() : _buildPanel(),
          )),
      ]),
    );
  }

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
              style: const TextStyle(color: DemProColors.text, fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(_stepMeta[_step].$3, style: const TextStyle(color: DemProColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
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
          style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w600),
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
                    : const Text('Confirmer la position', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ),
          )),
      ]),
    ),
  );

  // ── Panel principal ───────────────────────────────────────────────────────

  Widget _buildPanel() => Column(children: [
    Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Container(width: 36, height: 4, decoration: BoxDecoration(color: DemProColors.bg4, borderRadius: BorderRadius.circular(2))),
    ),

    // ── Bandeau départ (toujours visible) ─────────────────────────────────
    _DepartureBanner(
      label: _selectedProAddr?['label'] as String?,
      address: _pickupAddress,
      loading: _loadingGps,
      onTap: () => _showChangeDeparture(),
    ),

    // ── Séparateur ────────────────────────────────────────────────────────
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(children: [
        Icon(_stepMeta[_step].$1, color: DemProColors.accent, size: 18),
        const SizedBox(width: 8),
        Text(_stepMeta[_step].$2, style: const TextStyle(color: DemProColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
      ]),
    ),

    // ── Contenu scrollable ────────────────────────────────────────────────
    Expanded(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: switch (_step) {
        0 => _buildStep0(),
        1 => _buildStep1(),
        _ => _buildStep2(),
      },
    )),

    // ── Boutons ───────────────────────────────────────────────────────────
    _buildNavButtons(),
  ]);

  // ── Étape 0 — Destination ─────────────────────────────────────────────────

  Widget _buildStep0() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

    // Champ recherche + bouton carte
    Row(children: [
      Expanded(
        child: TextField(
          controller: _addressSearchCtrl,
          style: const TextStyle(color: DemProColors.text, fontSize: 13),
          textInputAction: TextInputAction.search,
          onChanged: _onAddressChanged,
          onSubmitted: _forwardGeocode,
          decoration: InputDecoration(
            hintText: 'Saisir une adresse…',
            hintStyle: const TextStyle(color: DemProColors.muted, fontSize: 12),
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
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: DemProColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.map_outlined, color: DemProColors.accent, size: 22),
        ),
      ),
    ]),

    // Suggestions Google Places
    if (_suggestions.isNotEmpty)
      Container(
        margin: const EdgeInsets.only(top: 4),
        constraints: const BoxConstraints(maxHeight: 200),
        decoration: BoxDecoration(
          color: DemProColors.bg3,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DemProColors.bg4),
        ),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: DemProColors.bg4.withValues(alpha: 0.5)),
          itemBuilder: (_, i) {
            final p = _suggestions[i];
            final fmt = p['structured_formatting'] as Map<String, dynamic>?;
            final main = fmt?['main_text'] as String? ?? p['description'] as String? ?? '';
            final secondary = fmt?['secondary_text'] as String? ?? '';
            return InkWell(
              onTap: () => _selectSuggestion(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.place_outlined, color: DemProColors.muted, size: 16),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(main, style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (secondary.isNotEmpty)
                      Text(secondary, style: const TextStyle(color: DemProColors.muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                ]),
              ),
            );
          },
        ),
      ),
    const SizedBox(height: 14),

    const Divider(color: DemProColors.bg3, height: 1),
    const SizedBox(height: 14),

    _FieldLabel('Nom du client (optionnel)'),
    const SizedBox(height: 6),
    _ProTextField(controller: _recipientNameCtrl, hint: 'Prénom Nom'),
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
      onChanged: (_) => setState(() {}),
    ),
  ]);

  // ── Étape 1 — Colis ──────────────────────────────────────────────────────

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
              child: Text('${i + 1}', style: const TextStyle(color: DemProColors.accent, fontSize: 11, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(child: _ProTextField(controller: a.nameCtrl, hint: 'Nom du produit')),
            if (_articles.length > 1) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() { _articles[i].dispose(); _articles.removeAt(i); }),
                child: const Icon(Icons.remove_circle_outline, color: DemProColors.danger, size: 20),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _ProTextField(controller: a.qtyCtrl, hint: 'Qté', keyboardType: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: _ProTextField(controller: a.priceCtrl, hint: 'Prix (FCFA)', keyboardType: TextInputType.number)),
          ]),
        ]),
      );
    }),
    if (_articles.length < 10)
      GestureDetector(
        onTap: () => setState(() => _articles.add(_Article())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3)),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add, color: DemProColors.accent, size: 16),
            SizedBox(width: 6),
            Text('Ajouter un article', style: TextStyle(color: DemProColors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    const SizedBox(height: 16),
    const Divider(color: DemProColors.bg3, height: 1),
    const SizedBox(height: 14),

    // ── Type de colis ─────────────────────────────────────────────────────
    const _FieldLabel('Type de colis'),
    const SizedBox(height: 10),
    ..._packageTypes.map((t) => _PackageTypeRow(
      type: t.$1, label: t.$2, icon: t.$3, subtitle: t.$4,
      selected: _packageType == t.$1,
      onTap: () => setState(() => _packageType = t.$1),
    )),
    const SizedBox(height: 14),
    Container(
      decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.bg4)),
      child: SwitchListTile(
        value: _isFragile,
        onChanged: (v) => setState(() => _isFragile = v),
        activeTrackColor: DemProColors.warning,
        activeThumbColor: Colors.white,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: DemProColors.bg4,
        title: const Row(children: [
          Icon(Icons.warning_amber_outlined, color: DemProColors.warning, size: 18),
          SizedBox(width: 8),
          Text('Fragile', style: TextStyle(color: DemProColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        subtitle: const Text('Le livreur sera notifié de faire attention', style: TextStyle(color: DemProColors.muted, fontSize: 11.5)),
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
        onTap: () => setState(() => _paymentMode = 'merchant'),
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
              style: TextStyle(
                color: _paymentMode == 'merchant' ? DemProColors.accent : DemProColors.muted,
                fontSize: 13, fontWeight: FontWeight.w700,
              )),
            const SizedBox(height: 2),
            Text('Paiement en ligne',
              style: TextStyle(
                color: _paymentMode == 'merchant' ? DemProColors.accent.withValues(alpha: 0.7) : DemProColors.muted,
                fontSize: 10,
              )),
          ]),
        ),
      )),
      const SizedBox(width: 10),
      Expanded(child: GestureDetector(
        onTap: () => setState(() => _paymentMode = 'cod'),
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
              style: TextStyle(
                color: _paymentMode == 'cod' ? DemProColors.accent : DemProColors.muted,
                fontSize: 13, fontWeight: FontWeight.w700,
              )),
            const SizedBox(height: 2),
            Text('À la livraison',
              style: TextStyle(
                color: _paymentMode == 'cod' ? DemProColors.accent.withValues(alpha: 0.7) : DemProColors.muted,
                fontSize: 10,
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
    _ProTextField(controller: _instructionsCtrl, hint: 'ex: Appeler à l\'arrivée…', maxLines: 3),

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
          Text('Programmer la livraison', style: TextStyle(color: DemProColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        subtitle: const Text('Choisir une date et heure précise', style: TextStyle(color: DemProColors.muted, fontSize: 11.5)),
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
                    Text(_fmtDate(_scheduledAt!), style: const TextStyle(color: DemProColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(_fmtTime(_scheduledAt!), style: const TextStyle(color: DemProColors.muted, fontSize: 12)),
                  ])
                : const Text('Appuyez pour choisir la date', style: TextStyle(color: DemProColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
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
                style: const TextStyle(color: DemProColors.muted, fontSize: 12),
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
            style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
          if (_isFragile) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: DemProColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: const Text('Fragile', style: TextStyle(color: DemProColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
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
              Text('Articles', style: TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            ..._articles.where((a) => a.nameCtrl.text.trim().isNotEmpty).map((a) {
              final qty = int.tryParse(a.qtyCtrl.text.trim()) ?? 1;
              final price = int.tryParse(a.priceCtrl.text.trim());
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Text('•  ', style: TextStyle(color: DemProColors.muted, fontSize: 12)),
                  Expanded(child: Text(
                    '${a.nameCtrl.text.trim()} × $qty',
                    style: const TextStyle(color: DemProColors.text, fontSize: 12),
                  )),
                  if (price != null)
                    Text('$price FCFA', style: const TextStyle(color: DemProColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
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
            style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w600),
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
              const Text('Livraison programmée', style: TextStyle(color: DemProColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
              Text('${_fmtDate(_scheduledAt!)} à ${_fmtTime(_scheduledAt!)}',
                style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
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
            Text('${_fmtFcfa(total)} FCFA',
              style: const TextStyle(color: DemProColors.accent, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            if (dist != null || dur != null) ...[
              const SizedBox(height: 4),
              Text([if (dist != null) '$dist km', if (dur != null) '~$dur min'].join(' · '),
                style: const TextStyle(color: DemProColors.muted, fontSize: 12)),
            ],
          ]),
        )
      else
        GestureDetector(
          onTap: _fetchEstimate,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.warning.withValues(alpha: 0.4))),
            child: const Row(children: [
              Icon(Icons.refresh, color: DemProColors.warning, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Impossible de calculer le prix. Appuyez pour réessayer.', style: TextStyle(color: DemProColors.warning, fontSize: 12))),
            ]),
          ),
        ),
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
        onSelect:      (addr) { Navigator.pop(context); _applyProAddress(addr); },
        onGps:         () { Navigator.pop(context); _fetchGps(); },
        onMap:         () { Navigator.pop(context); _enterMapPlacement(forPickup: true); },
      ),
    );
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
            ? const Text('Localisation en cours…', style: TextStyle(color: DemProColors.muted, fontSize: 12))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (label != null)
                  Text(label!, style: const TextStyle(color: DemProColors.text, fontSize: 12, fontWeight: FontWeight.w700)),
                Text(
                  address.isNotEmpty ? address : 'Aucun départ sélectionné',
                  style: const TextStyle(color: DemProColors.muted, fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ])),
        const SizedBox(width: 8),
        const Text('Changer', style: TextStyle(color: DemProColors.accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
        const Icon(Icons.chevron_right, color: DemProColors.accent, size: 16),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet — changer le départ
// ─────────────────────────────────────────────────────────────────────────────

class _ChangeDepartureSheet extends StatelessWidget {
  final List<Map<String, dynamic>> proAddresses;
  final String? selectedId;
  final bool    loadingGps;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onGps;
  final VoidCallback onMap;
  const _ChangeDepartureSheet({
    required this.proAddresses, required this.selectedId,
    required this.loadingGps, required this.onSelect,
    required this.onGps, required this.onMap,
  });

  static const _iconMap = {
    'store':     Icons.storefront_outlined,
    'warehouse': Icons.warehouse_outlined,
    'office':    Icons.business_outlined,
    'home':      Icons.home_outlined,
    'other':     Icons.place_outlined,
  };

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: DemProColors.bg2,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(width: 36, height: 4, decoration: BoxDecoration(color: DemProColors.bg4, borderRadius: BorderRadius.circular(2))),
      )),
      const Text('Point de départ', style: TextStyle(color: DemProColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),

      // Adresses Pro
      if (proAddresses.isNotEmpty) ...[
        const Text('Mes adresses', style: TextStyle(color: DemProColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...proAddresses.map((a) {
          final isSelected = a['id'] == selectedId;
          final icon = _iconMap[a['icon'] as String? ?? 'other'] ?? Icons.place_outlined;
          return GestureDetector(
            onTap: () => onSelect(a),
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
                  Text(a['label'] as String? ?? '', style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(a['address'] as String? ?? '', style: const TextStyle(color: DemProColors.muted, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                if (isSelected) const Icon(Icons.check_circle, color: DemProColors.accent, size: 18),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
      ],

      // Actions alternatives
      _SheetAction(icon: Icons.my_location, label: 'Ma position actuelle', loading: loadingGps, onTap: onGps),
      const SizedBox(height: 8),
      _SheetAction(icon: Icons.map_outlined, label: 'Pointer sur la carte', onTap: onMap),
    ]),
  );
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
              Text(label, style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers internes
// ─────────────────────────────────────────────────────────────────────────────

String _fmtFcfa(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: DemProColors.muted, fontSize: 12, fontWeight: FontWeight.w600));
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
  const _ProTextField({required this.controller, required this.hint, this.prefix, this.keyboardType, this.maxLines = 1, this.maxLength, this.inputFormatters, this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    maxLines: maxLines,
    maxLength: maxLength,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    style: const TextStyle(color: DemProColors.text, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: DemProColors.muted, fontSize: 13),
      prefixText: prefix,
      prefixStyle: const TextStyle(color: DemProColors.muted, fontSize: 14),
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
              Text(label, style: TextStyle(color: selected ? DemProColors.accent : DemProColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: DemProColors.muted, fontSize: 12)),
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
    Expanded(child: Text(label, style: const TextStyle(color: DemProColors.text, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
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
          color: outline ? Colors.transparent : (disabled ? DemProColors.bg3 : DemProColors.accent),
          borderRadius: BorderRadius.circular(14),
          border: outline ? Border.all(color: DemProColors.bg4) : null,
        ),
        child: Material(color: Colors.transparent,
          child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap,
            child: Center(child: loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(label, style: TextStyle(color: outline ? DemProColors.muted : (disabled ? DemProColors.muted : Colors.white), fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
      ),
    );
  }
}
