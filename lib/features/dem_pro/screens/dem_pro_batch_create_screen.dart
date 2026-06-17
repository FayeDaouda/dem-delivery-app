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
import '../../home_driver/navigation/navigation_service.dart';
import '../data/dem_pro_repository.dart';
import '../theme/dem_pro_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────

const _dakar = LatLng(14.6937, -17.4441);

const _pkgTypes = [
  ('documents', 'Documents',   Icons.description_outlined),
  ('small',     'Petit colis', Icons.inventory_2_outlined),
  ('large',     'Grand colis', Icons.view_in_ar_outlined),
];

// ─────────────────────────────────────────────────────────────────────────────

class _Stop {
  double? lat, lng;
  String  address  = '';
  String  phone    = '';
  String  name     = '';
  String  landmark = '';
  String  pkg      = 'small';
  bool    fragile  = false;
  double? price;

  bool get hasLocation => lat != null && lng != null;
}

// ─────────────────────────────────────────────────────────────────────────────

class DemProBatchCreateScreen extends StatefulWidget {
  const DemProBatchCreateScreen({super.key});
  @override
  State<DemProBatchCreateScreen> createState() => _State();
}

class _State extends State<DemProBatchCreateScreen> {
  final _proRepo   = DemProRepository(ApiClient.dio);
  final _publicDio = Dio();

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  LatLng _cameraPos    = _dakar;
  bool _placingMap     = false;
  int  _placingIndex   = -1;
  bool _geocoding      = false;

  // ── Départ ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _proAddresses = [];
  Map<String, dynamic>? _selectedAddr;
  double? _pickupLat, _pickupLng;
  String  _pickupAddress = '';
  bool    _loadingGps    = false;

  // ── Arrêts ───────────────────────────────────────────────────────────────
  final List<_Stop> _stops = [_Stop(), _Stop()];

  // ── Programmation ────────────────────────────────────────────────────────
  bool      _isScheduled = false;
  DateTime? _scheduledAt;

  // ── Notes globales ───────────────────────────────────────────────────────
  final _notesCtrl = TextEditingController();

  // ── Soumission ───────────────────────────────────────────────────────────
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _loadProAddresses();
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Map ───────────────────────────────────────────────────────────────────

  Future<void> _loadMapStyle() async {
    final s = await rootBundle.loadString('assets/map_style_waze.json');
    if (mounted) setState(() => _mapStyle = s);
  }

  void _centerMap(LatLng pos) => _mapCtrl?.animateCamera(
    CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 14, tilt: 20)),
  );

  // ── Adresses Pro ─────────────────────────────────────────────────────────

  Future<void> _loadProAddresses() async {
    try {
      final list = await _proRepo.getAddresses();
      if (!mounted) return;
      setState(() => _proAddresses = list);
      final def = list.firstWhere((a) => a['isDefault'] == true,
          orElse: () => list.isEmpty ? {} : list.first);
      if (def.isNotEmpty) { _applyProAddress(def); }
      else { _fetchGps(); }
    } catch (_) { _fetchGps(); }
  }

  void _applyProAddress(Map<String, dynamic> addr) {
    final lat = (addr['lat'] as num?)?.toDouble();
    final lng = (addr['lng'] as num?)?.toDouble();
    setState(() {
      _selectedAddr   = addr;
      _pickupAddress  = addr['address'] as String? ?? '';
      if (lat != null && lng != null) {
        _pickupLat = lat; _pickupLng = lng;
        _centerMap(LatLng(lat, lng));
      }
    });
  }

  Future<void> _fetchGps() async {
    setState(() { _loadingGps = true; _selectedAddr = null; });
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (!mounted) return;
      _pickupLat = pos.latitude; _pickupLng = pos.longitude;
      _centerMap(LatLng(pos.latitude, pos.longitude));
      await _reverseGeocode(LatLng(pos.latitude, pos.longitude), stopIndex: -1);
    } catch (_) {
      if (mounted) showDemToast(context, 'GPS indisponible', isError: true);
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  // ── Placement carte ───────────────────────────────────────────────────────

  void _enterMapPlacement(int stopIndex) {
    setState(() { _placingMap = true; _placingIndex = stopIndex; });
    if (stopIndex == -1 && _pickupLat != null) {
      _centerMap(LatLng(_pickupLat!, _pickupLng!));
    } else if (stopIndex >= 0 && _stops[stopIndex].hasLocation) {
      _centerMap(LatLng(_stops[stopIndex].lat!, _stops[stopIndex].lng!));
    }
  }

  Future<void> _confirmPlacement() async {
    setState(() => _geocoding = true);
    final pos = _cameraPos;
    if (_placingIndex == -1) {
      _pickupLat = pos.latitude; _pickupLng = pos.longitude;
      _selectedAddr = null;
      await _reverseGeocode(pos, stopIndex: -1);
    } else {
      _stops[_placingIndex].lat = pos.latitude;
      _stops[_placingIndex].lng = pos.longitude;
      await _reverseGeocode(pos, stopIndex: _placingIndex);
    }
    if (mounted) setState(() { _placingMap = false; _geocoding = false; });
  }

  Future<void> _reverseGeocode(LatLng pos, {required int stopIndex}) async {
    try {
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude)
          .timeout(const Duration(seconds: 5));
      if (marks.isEmpty || !mounted) return;
      final p = marks.first;
      final street = p.street ?? p.name ?? '';
      final local  = p.subLocality ?? p.locality ?? '';
      final addr   = street.isNotEmpty ? '$street, $local' : local;
      final result = addr.isNotEmpty ? addr
          : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      setState(() {
        if (stopIndex == -1) { _pickupAddress = result; }
        else { _stops[stopIndex].address = result; }
      });
    } catch (_) {}
  }

  // ── Sélection d'une suggestion Google Places pour un arrêt ───────────────

  Future<void> _selectStopSuggestion(int index, Map<String, dynamic> place) async {
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
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
          _stops[index].lat = lat;
          _stops[index].lng = lng;
          _stops[index].address = name;
        });
        _centerMap(LatLng(lat, lng));
      }
    } catch (_) {
      if (mounted) showDemToast(context, 'Impossible de charger l\'adresse', isError: true);
    }
  }

  // ── Programmation ─────────────────────────────────────────────────────────

  Future<void> _pickScheduleDate() async {
    final now     = DateTime.now();
    final minDate = now.add(const Duration(minutes: 10));
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? minDate,
      firstDate: minDate,
      lastDate: now.add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: DemProColors.accent, onPrimary: Colors.white, surface: DemProColors.bg2, onSurface: DemProColors.text),
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
          colorScheme: const ColorScheme.dark(primary: DemProColors.accent, onPrimary: Colors.white, surface: DemProColors.bg2, onSurface: DemProColors.text),
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

  // ── Validation & submit ───────────────────────────────────────────────────

  bool get _canSubmit =>
      _pickupLat != null &&
      _stops.every((s) => s.hasLocation && s.phone.trim().length >= 8);

  Future<void> _submit() async {
    if (!_canSubmit) {
      showDemToast(context,
          _pickupLat == null
              ? 'Définissez le point de départ'
              : 'Chaque arrêt doit avoir une localisation et un numéro de téléphone',
          isError: true);
      return;
    }
    if (_isScheduled && _scheduledAt == null) {
      showDemToast(context, 'Choisissez une date et heure pour la tournée', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final stops = _stops.map((s) {
        final parts = <String>[];
        final pkg = _pkgTypes.firstWhere((p) => p.$1 == s.pkg);
        parts.add(pkg.$2);
        if (s.fragile) parts.add('⚠️ Fragile');
        return {
          'deliveryAddress':   s.address.isNotEmpty ? s.address : '${s.lat!.toStringAsFixed(4)}, ${s.lng!.toStringAsFixed(4)}',
          'deliveryLatitude':  s.lat,
          'deliveryLongitude': s.lng,
          if (s.name.trim().isNotEmpty)     'receiverName':  s.name.trim(),
          if (s.phone.trim().isNotEmpty)    'receiverPhone': '+221${s.phone.trim()}',
          if (s.landmark.trim().isNotEmpty) 'landmark':      s.landmark.trim(),
          'description': parts.join(' · '),
        };
      }).toList();

      final batch = await _proRepo.createBatch({
        'pickupAddress':   _pickupAddress.isNotEmpty ? _pickupAddress : '${_pickupLat!.toStringAsFixed(4)}, ${_pickupLng!.toStringAsFixed(4)}',
        'pickupLatitude':  _pickupLat,
        'pickupLongitude': _pickupLng,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        if (_scheduledAt != null) 'scheduledAt': _scheduledAt!.toUtc().toIso8601String(),
        'stops': stops,
      });

      if (mounted) {
        showDemToast(context, _scheduledAt != null ? 'Tournée programmée !' : 'Tournée lancée !');
        context.pushReplacement('/dem-pro/batch/confirmation', extra: batch);
      }
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Markers ───────────────────────────────────────────────────────────────

  Set<Marker> get _markers {
    final m = <Marker>{};
    if (_pickupLat != null && !_placingMap) {
      m.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(_pickupLat!, _pickupLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(title: 'Départ'),
      ));
    }
    for (int i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      if (s.hasLocation && !_placingMap) {
        m.add(Marker(
          markerId: MarkerId('stop_$i'),
          position: LatLng(s.lat!, s.lng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Arrêt ${i + 1}'),
        ));
      }
    }
    return m;
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
          markers: _markers,
          onCameraMove: (pos) => _cameraPos = pos.target,
        )),

        // Pin central placement
        if (_placingMap)
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              _placingIndex == -1 ? Icons.inventory_2_rounded : Icons.location_on,
              color: _placingIndex == -1 ? DemProColors.warning : DemProColors.success,
              size: 40,
              shadows: const [Shadow(color: Colors.black26, blurRadius: 8)],
            ),
            const SizedBox(height: 2),
            CircleAvatar(radius: 3, backgroundColor: _placingIndex == -1 ? DemProColors.warning : DemProColors.success),
          ])),

        // Header
        if (!_placingMap)
          Positioned(top: 0, left: 0, right: 0,
            child: SafeArea(child: _buildHeader())),

        // Panel bas
        Positioned(bottom: 0, left: 0, right: 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: _placingMap
                ? 130 + MediaQuery.of(context).viewPadding.bottom
                : MediaQuery.of(context).size.height * 0.62 + MediaQuery.of(context).viewPadding.bottom,
            decoration: BoxDecoration(
              color: DemProColors.bg2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: _placingMap ? _buildPlacementPanel() : _buildPanel(),
          )),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
    child: Row(children: [
      IconButton(
        onPressed: () => context.pop(),
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
        child: Row(children: [
          const Icon(Icons.route, color: DemProColors.accent, size: 18),
          const SizedBox(width: 8),
          const Text('Nouvelle tournée', style: TextStyle(color: DemProColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: DemProColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text('${_stops.length} arrêts', style: const TextStyle(color: DemProColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
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
          _placingIndex == -1 ? 'Positionnez le point de départ' : 'Arrêt ${_placingIndex + 1} — Positionnez la destination',
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

    // Bandeau départ
    _DepartureBannerBatch(
      label:   _selectedAddr?['label'] as String?,
      address: _pickupAddress,
      loading: _loadingGps,
      onTap:   () => _showChangeDeparture(),
    ),

    const SizedBox(height: 8),

    // Liste arrêts
    Expanded(child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        ...List.generate(_stops.length, (i) => _StopCard(
          index:       i,
          stop:        _stops[i],
          canRemove:   _stops.length > 2,
          onMapTap:    () => _enterMapPlacement(i),
          onRemove:    () => setState(() => _stops.removeAt(i)),
          onChanged:   () => setState(() {}),
          publicDio:   _publicDio,
          onSuggestionSelected: _selectStopSuggestion,
        )),

        if (_stops.length < 5)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _stops.add(_Stop())),
              icon: const Icon(Icons.add, color: DemProColors.accent, size: 18),
              label: const Text('Ajouter un arrêt', style: TextStyle(color: DemProColors.accent, fontSize: 13, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: DemProColors.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

        // Notes globales
        const SizedBox(height: 4),
        const Text('Instructions pour le livreur (optionnel)', style: TextStyle(color: DemProColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          style: const TextStyle(color: DemProColors.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'ex: Sonner à chaque arrêt, ne pas laisser en gardiennage…',
            hintStyle: const TextStyle(color: DemProColors.muted, fontSize: 12),
            filled: true, fillColor: DemProColors.bg3,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),

        // Programmation
        const SizedBox(height: 16),
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
              Text('Programmer la tournée', style: TextStyle(color: DemProColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
            subtitle: const Text('Choisir une date et heure', style: TextStyle(color: DemProColors.muted, fontSize: 11.5)),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          ),
        ),
        if (_isScheduled && _scheduledAt != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickScheduleDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: DemProColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DemProColors.accent.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today, color: DemProColors.accent, size: 16),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_fmtDate(_scheduledAt!), style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(_fmtTime(_scheduledAt!), style: const TextStyle(color: DemProColors.muted, fontSize: 12)),
                ]),
                const Spacer(),
                const Icon(Icons.edit_outlined, color: DemProColors.muted, size: 14),
              ]),
            ),
          ),
        ],
      ],
    )),

    // Bouton lancer
    SafeArea(top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(height: 52, width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _canSubmit ? DemProColors.accent : DemProColors.bg3,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: (_canSubmit && !_submitting) ? _submit : null,
                child: Center(child: _submitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _isScheduled ? 'Programmer la tournée' : 'Lancer la tournée (${_stops.length} arrêts)',
                        style: TextStyle(
                          color: _canSubmit ? Colors.white : DemProColors.muted,
                          fontWeight: FontWeight.w700, fontSize: 15,
                        ),
                      ),
                ),
              ),
            ),
          )),
      )),
  ]);

  // ── Sheet changer départ ──────────────────────────────────────────────────

  void _showChangeDeparture() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BatchDepartureSheet(
        proAddresses: _proAddresses,
        selectedId:   _selectedAddr?['id'] as String?,
        loadingGps:   _loadingGps,
        onSelect: (addr) { Navigator.pop(context); _applyProAddress(addr); },
        onGps:    () { Navigator.pop(context); _fetchGps(); },
        onMap:    () { Navigator.pop(context); _enterMapPlacement(-1); },
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    const m = ['jan','fév','mar','avr','mai','jun','jul','aoû','sep','oct','nov','déc'];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }
  static String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte d'un arrêt
// ─────────────────────────────────────────────────────────────────────────────

class _StopCard extends StatefulWidget {
  final int   index;
  final _Stop stop;
  final bool  canRemove;
  final VoidCallback onMapTap;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final Dio publicDio;
  final void Function(int index, Map<String, dynamic> place) onSuggestionSelected;
  const _StopCard({required this.index, required this.stop, required this.canRemove, required this.onMapTap, required this.onRemove, required this.onChanged, required this.publicDio, required this.onSuggestionSelected});
  @override
  State<_StopCard> createState() => _StopCardState();
}

class _StopCardState extends State<_StopCard> {
  late final TextEditingController _phoneCtrl    = TextEditingController(text: widget.stop.phone);
  late final TextEditingController _nameCtrl     = TextEditingController(text: widget.stop.name);
  late final TextEditingController _landmarkCtrl = TextEditingController(text: widget.stop.landmark);
  final _addrCtrl = TextEditingController();
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _phoneCtrl.dispose(); _nameCtrl.dispose(); _landmarkCtrl.dispose(); _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _forwardGeocode(String query) async {
    if (query.trim().length < 3) return;
    FocusScope.of(context).unfocus();
    setState(() { _suggestions = []; _searching = true; });
    try {
      final locations = await geo.locationFromAddress('$query, Dakar, Sénégal')
          .timeout(const Duration(seconds: 6));
      if (locations.isEmpty || !mounted) return;
      final loc = locations.first;
      final s = widget.stop;
      s.lat = loc.latitude;
      s.lng = loc.longitude;
      s.address = query.trim();
      _addrCtrl.text = query.trim();
      widget.onChanged();
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _onAddrChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _searching = true);
      try {
        final res = await widget.publicDio.get(
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
          setState(() { _suggestions = preds; _searching = false; });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stop;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: DemProColors.bg3,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: s.hasLocation ? DemProColors.accent.withValues(alpha: 0.25) : DemProColors.bg4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header arrêt
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Row(children: [
            CircleAvatar(radius: 13, backgroundColor: DemProColors.accent.withValues(alpha: 0.15),
              child: Text('${widget.index + 1}', style: const TextStyle(color: DemProColors.accent, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Arrêt ${widget.index + 1}', style: const TextStyle(color: DemProColors.text, fontSize: 14, fontWeight: FontWeight.w700))),
            if (widget.canRemove)
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.remove_circle_outline, color: DemProColors.danger, size: 20),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
          ]),
        ),

        // Champ recherche + bouton carte
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _addrCtrl,
                style: const TextStyle(color: DemProColors.text, fontSize: 12),
                onChanged: _onAddrChanged,
                onSubmitted: (q) => _forwardGeocode(q),
                decoration: InputDecoration(
                  hintText: 'Saisir une adresse…',
                  hintStyle: const TextStyle(color: DemProColors.muted, fontSize: 11),
                  prefixIcon: _searching
                      ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: DemProColors.accent, strokeWidth: 2)))
                      : Icon(
                          s.hasLocation ? Icons.check_circle : Icons.search,
                          color: s.hasLocation ? DemProColors.success : DemProColors.muted,
                          size: 16,
                        ),
                  suffixIcon: _addrCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: DemProColors.muted, size: 14),
                          onPressed: () { _addrCtrl.clear(); setState(() => _suggestions = []); },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                      : null,
                  filled: true, fillColor: DemProColors.bg4,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DemProColors.bg4)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: s.hasLocation ? DemProColors.success.withValues(alpha: 0.5) : DemProColors.bg4),
                  ),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: widget.onMapTap,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: DemProColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.map_outlined, color: DemProColors.accent, size: 18),
              ),
            ),
          ]),
        ),

        // Suggestions
        if (_suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: BoxDecoration(
                color: DemProColors.bg4,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DemProColors.accent.withValues(alpha: 0.2)),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: DemProColors.bg3.withValues(alpha: 0.5)),
                itemBuilder: (_, i) {
                  final p = _suggestions[i];
                  final fmt = p['structured_formatting'] as Map<String, dynamic>?;
                  final main = fmt?['main_text'] as String? ?? p['description'] as String? ?? '';
                  final secondary = fmt?['secondary_text'] as String? ?? '';
                  return InkWell(
                    onTap: () {
                      _addrCtrl.text = main;
                      setState(() => _suggestions = []);
                      FocusScope.of(context).unfocus();
                      widget.onSuggestionSelected(widget.index, p);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(children: [
                        const Icon(Icons.place_outlined, color: DemProColors.muted, size: 14),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(main, style: const TextStyle(color: DemProColors.text, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (secondary.isNotEmpty)
                            Text(secondary, style: const TextStyle(color: DemProColors.muted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: 8),

        // Téléphone destinataire
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _MiniField(ctrl: _phoneCtrl, hint: 'Tél destinataire *', prefix: '+221',
            keyboardType: TextInputType.phone,
            onChanged: (v) { s.phone = v; widget.onChanged(); }),
        ),
        const SizedBox(height: 6),

        // Nom destinataire
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _MiniField(ctrl: _nameCtrl, hint: 'Nom destinataire (optionnel)',
            onChanged: (v) { s.name = v; widget.onChanged(); }),
        ),
        const SizedBox(height: 6),

        // Repère
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _MiniField(ctrl: _landmarkCtrl, hint: 'Repère (optionnel)',
            onChanged: (v) { s.landmark = v; widget.onChanged(); }),
        ),
        const SizedBox(height: 8),

        // Type de colis
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(children: _pkgTypes.map((t) {
            final sel = s.pkg == t.$1;
            return Expanded(child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () { setState(() { s.pkg = t.$1; }); widget.onChanged(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? DemProColors.accent.withValues(alpha: 0.12) : DemProColors.bg4,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: sel ? DemProColors.accent : DemProColors.bg4, width: sel ? 1.5 : 1),
                  ),
                  child: Column(children: [
                    Icon(t.$3, color: sel ? DemProColors.accent : DemProColors.muted, size: 16),
                    const SizedBox(height: 3),
                    Text(t.$2.split(' ').first, style: TextStyle(color: sel ? DemProColors.accent : DemProColors.muted, fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ));
          }).toList()),
        ),

        // Fragile
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(children: [
            Checkbox(
              value: s.fragile,
              onChanged: (v) { setState(() { s.fragile = v ?? false; }); widget.onChanged(); },
              activeColor: DemProColors.warning,
              side: const BorderSide(color: DemProColors.muted),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            const Text('Fragile', style: TextStyle(color: DemProColors.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class _MiniField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final String? prefix;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  const _MiniField({required this.ctrl, required this.hint, this.prefix, this.keyboardType, this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
    onChanged: onChanged,
    style: const TextStyle(color: DemProColors.text, fontSize: 13),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: DemProColors.muted, fontSize: 12),
      prefixText: prefix,
      prefixStyle: const TextStyle(color: DemProColors.muted, fontSize: 13),
      filled: true, fillColor: DemProColors.bg4,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DemProColors.bg4)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DemProColors.bg4)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bandeau départ (léger, pour batch)
// ─────────────────────────────────────────────────────────────────────────────

class _DepartureBannerBatch extends StatelessWidget {
  final String? label, address;
  final bool loading;
  final VoidCallback onTap;
  const _DepartureBannerBatch({required this.label, required this.address, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(12), border: Border.all(color: DemProColors.bg4)),
      child: Row(children: [
        const Icon(Icons.location_on, color: DemProColors.accent, size: 16),
        const SizedBox(width: 8),
        Expanded(child: loading
            ? const Text('Localisation…', style: TextStyle(color: DemProColors.muted, fontSize: 12))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (label != null) Text(label!, style: const TextStyle(color: DemProColors.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
                Text(address != null && address!.isNotEmpty ? address! : 'Aucun départ',
                  style: const TextStyle(color: DemProColors.muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
        const SizedBox(width: 8),
        const Text('Changer', style: TextStyle(color: DemProColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
        const Icon(Icons.chevron_right, color: DemProColors.accent, size: 14),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet changement de départ (réutilise la même logique)
// ─────────────────────────────────────────────────────────────────────────────

class _BatchDepartureSheet extends StatelessWidget {
  final List<Map<String, dynamic>> proAddresses;
  final String? selectedId;
  final bool    loadingGps;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onGps, onMap;
  const _BatchDepartureSheet({required this.proAddresses, required this.selectedId, required this.loadingGps, required this.onSelect, required this.onGps, required this.onMap});

  static const _iconMap = {'store': Icons.storefront_outlined, 'warehouse': Icons.warehouse_outlined, 'office': Icons.business_outlined, 'home': Icons.home_outlined, 'other': Icons.place_outlined};

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: DemProColors.bg2, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(width: 36, height: 4, decoration: BoxDecoration(color: DemProColors.bg4, borderRadius: BorderRadius.circular(2))),
      )),
      const Text('Point de départ', style: TextStyle(color: DemProColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 14),
      if (proAddresses.isNotEmpty) ...[
        const Text('Mes adresses', style: TextStyle(color: DemProColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...proAddresses.map((a) {
          final sel  = a['id'] == selectedId;
          final icon = _iconMap[a['icon'] as String? ?? 'other'] ?? Icons.place_outlined;
          return GestureDetector(
            onTap: () => onSelect(a),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: sel ? DemProColors.accent.withValues(alpha: 0.10) : DemProColors.bg3,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? DemProColors.accent : DemProColors.bg4, width: sel ? 1.5 : 1),
              ),
              child: Row(children: [
                Icon(icon, color: DemProColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['label'] as String? ?? '', style: const TextStyle(color: DemProColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(a['address'] as String? ?? '', style: const TextStyle(color: DemProColors.muted, fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                if (sel) const Icon(Icons.check_circle, color: DemProColors.accent, size: 18),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
      _SheetActionBtn(icon: Icons.my_location, label: 'Ma position actuelle', loading: loadingGps, onTap: onGps),
      const SizedBox(height: 8),
      _SheetActionBtn(icon: Icons.map_outlined, label: 'Pointer sur la carte', onTap: onMap),
    ]),
  );
}

class _SheetActionBtn extends StatelessWidget {
  final IconData icon; final String label; final bool loading; final VoidCallback onTap;
  const _SheetActionBtn({required this.icon, required this.label, this.loading = false, required this.onTap});
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
