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
import '../../../core/error/app_exception.dart';
import '../../../core/services/places_autocomplete_service.dart';
import '../../../core/storage/dem_pro_draft_storage.dart';
import '../../../core/theme/map_theme_provider.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../core/utils/senegal_phone.dart';
import '../../../shared/widgets/place_suggestions_list.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../home_driver/navigation/map_theme.dart';
import '../../home_driver/navigation/navigation_service.dart';
import '../data/dem_pro_repository.dart';
import '../../../core/theme/app_theme.dart';
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

const _pkgTypes = [
  ('documents', 'Documents', Icons.description_outlined),
  ('small', 'Petit colis', Icons.inventory_2_outlined),
  ('large', 'Grand colis', Icons.view_in_ar_outlined),
];

// ─────────────────────────────────────────────────────────────────────────────

class _Stop {
  double? lat, lng;
  String address = '';
  String phone = '';
  String name = '';
  String landmark = '';
  String pkg = 'small';
  bool fragile = false;
  double? price;

  bool get hasLocation => lat != null && lng != null;
}

// ─────────────────────────────────────────────────────────────────────────────

class DemProBatchCreateScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? reorderFrom;
  const DemProBatchCreateScreen({super.key, this.reorderFrom});
  @override
  ConsumerState<DemProBatchCreateScreen> createState() => _State();
}

class _State extends ConsumerState<DemProBatchCreateScreen> {
  final _proRepo = DemProRepository(ApiClient.dio);
  final _publicDio = Dio();

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  LatLng _cameraPos = _dakar;
  bool _placingMap = false;
  int _placingIndex = -1;
  bool _geocoding = false;

  // ── Départ ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _proAddresses = [];
  Map<String, dynamic>? _selectedAddr;
  double? _pickupLat, _pickupLng;
  String _pickupAddress = '';
  bool _loadingGps = false;

  // ── Arrêts ───────────────────────────────────────────────────────────────
  final List<_Stop> _stops = [_Stop(), _Stop()];

  // ── Destinations récentes (partagées entre les arrêts) ───────────────────
  List<Map<String, dynamic>> _recentDestinations = [];

  // ── Brouillon ────────────────────────────────────────────────────────────
  Timer? _draftSaveDebounce;

  // ── Programmation ────────────────────────────────────────────────────────
  bool _isScheduled = false;
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
    _loadRecentDestinations();
    if (widget.reorderFrom != null) {
      _applyReorder(widget.reorderFrom!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeShowDraftPrompt(),
      );
    }
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _notesCtrl.dispose();
    _draftSaveDebounce?.cancel();
    super.dispose();
  }

  // ── Destinations récentes ────────────────────────────────────────────────

  Future<void> _loadRecentDestinations() async {
    try {
      final list = await _proRepo.getRecentDestinations();
      if (mounted) setState(() => _recentDestinations = list);
    } catch (_) {}
  }

  // ── Recommander (reorder) ────────────────────────────────────────────────

  void _applyReorder(Map<String, dynamic> batch) {
    final orders =
        (batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (orders.isEmpty) return;
    orders.sort(
      (a, b) => ((a['sequenceIndex'] as num?) ?? 0).compareTo(
        (b['sequenceIndex'] as num?) ?? 0,
      ),
    );
    _stops
      ..clear()
      ..addAll(
        orders.map((o) {
          final s = _Stop();
          s.lat = (o['deliveryLatitude'] as num?)?.toDouble();
          s.lng = (o['deliveryLongitude'] as num?)?.toDouble();
          s.address = o['deliveryAddress'] as String? ?? '';
          s.name = o['receiverName'] as String? ?? '';
          s.phone = (o['receiverPhone'] as String? ?? '').replaceFirst(
            '+221',
            '',
          );
          return s;
        }),
      );
  }

  // ── Brouillon ─────────────────────────────────────────────────────────────

  Map<String, dynamic> _draftSnapshot() => {
    'stops': _stops
        .map(
          (s) => {
            'lat': s.lat,
            'lng': s.lng,
            'address': s.address,
            'phone': s.phone,
            'name': s.name,
            'landmark': s.landmark,
            'pkg': s.pkg,
            'fragile': s.fragile,
          },
        )
        .toList(),
    'notes': _notesCtrl.text,
    'scheduledAt': _scheduledAt?.toIso8601String(),
    'savedAt': DateTime.now().toIso8601String(),
  };

  void _scheduleDraftSave() {
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (_stops.every((s) => !s.hasLocation)) return;
      DemProDraftStorage.saveBatchDraft(_draftSnapshot());
    });
  }

  void _applyDraft(Map<String, dynamic> draft) {
    final stops = (draft['stops'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    setState(() {
      _notesCtrl.text = draft['notes'] as String? ?? '';
      final scheduledAt = draft['scheduledAt'] as String?;
      if (scheduledAt != null) {
        _isScheduled = true;
        _scheduledAt = DateTime.tryParse(scheduledAt);
      }
      if (stops.isNotEmpty) {
        _stops
          ..clear()
          ..addAll(
            stops.map((it) {
              final s = _Stop();
              s.lat = (it['lat'] as num?)?.toDouble();
              s.lng = (it['lng'] as num?)?.toDouble();
              s.address = it['address'] as String? ?? '';
              s.phone = it['phone'] as String? ?? '';
              s.name = it['name'] as String? ?? '';
              s.landmark = it['landmark'] as String? ?? '';
              s.pkg = it['pkg'] as String? ?? 'small';
              s.fragile = it['fragile'] as bool? ?? false;
              return s;
            }),
          );
      }
    });
  }

  Future<void> _maybeShowDraftPrompt() async {
    final draft = await DemProDraftStorage.getBatchDraft();
    if (draft == null || !mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _BatchDraftResumeSheet(
        savedAt: draft['savedAt'] as String?,
        onResume: () {
          Navigator.pop(context);
          _applyDraft(draft);
        },
        onDiscard: () {
          Navigator.pop(context);
          DemProDraftStorage.clearBatchDraft();
        },
      ),
    );
  }

  // ── Map ───────────────────────────────────────────────────────────────────

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final s = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = s);
  }

  void _centerMap(LatLng pos) => _mapCtrl?.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(target: pos, zoom: 14, tilt: 20),
    ),
  );

  /// Hauteur actuelle du panneau du bas (voir l'`AnimatedContainer` du `build`).
  double get _panelHeight {
    final h = MediaQuery.of(context).size.height;
    return _placingMap ? 130 : h * _sheetMax;
  }

  /// Centre la carte sur [pos] de sorte que le point soit visible dans la
  /// zone haute (au-dessus du panneau), et non caché derrière — décale la
  /// cible caméra vers le sud d'une distance égale à la moitié de la hauteur
  /// du panneau (convertie en degrés via la résolution Mercator au zoom
  /// utilisé), ce qui fait apparaître [pos] au milieu de la zone visible.
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

  /// Ajuste le zoom pour que tous les [points] (départ + arrêts) soient
  /// visibles au-dessus du panneau du bas — même technique que sur l'écran
  /// de commande simple (extension artificielle de la borne sud).
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

  /// Recadre la carte sur l'ensemble des points définis (départ + arrêts).
  void _recenterMap() {
    final points = <LatLng>[
      if (_pickupLat != null) LatLng(_pickupLat!, _pickupLng!),
      for (final s in _stops)
        if (s.hasLocation) LatLng(s.lat!, s.lng!),
    ];
    _fitBoundsVisible(points);
  }

  // ── Adresses Pro ─────────────────────────────────────────────────────────

  Future<void> _loadProAddresses() async {
    try {
      final list = await _proRepo.getAddresses();
      if (!mounted) return;
      setState(() => _proAddresses = list);
      final def = list.firstWhere(
        (a) => a['isDefault'] == true,
        orElse: () => list.isEmpty ? {} : list.first,
      );
      if (def.isNotEmpty) {
        _applyProAddress(def);
      } else {
        _fetchGps();
      }
    } catch (_) {
      _fetchGps();
    }
  }

  void _applyProAddress(Map<String, dynamic> addr) {
    final lat = (addr['lat'] as num?)?.toDouble();
    final lng = (addr['lng'] as num?)?.toDouble();
    setState(() {
      _selectedAddr = addr;
      _pickupAddress = addr['address'] as String? ?? '';
      if (lat != null && lng != null) {
        _pickupLat = lat;
        _pickupLng = lng;
      }
    });
    if (lat != null && lng != null) _recenterMap();
    _scheduleDraftSave();
  }

  Future<void> _fetchGps() async {
    setState(() {
      _loadingGps = true;
      _selectedAddr = null;
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
      _pickupLat = pos.latitude;
      _pickupLng = pos.longitude;
      _recenterMap();
      await _reverseGeocode(LatLng(pos.latitude, pos.longitude), stopIndex: -1);
      _scheduleDraftSave();
    } catch (_) {
      if (mounted) showDemToast(context, 'GPS indisponible', isError: true);
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  // ── Placement carte ───────────────────────────────────────────────────────

  void _enterMapPlacement(int stopIndex) {
    setState(() {
      _placingMap = true;
      _placingIndex = stopIndex;
    });
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
      _pickupLat = pos.latitude;
      _pickupLng = pos.longitude;
      _selectedAddr = null;
      await _reverseGeocode(pos, stopIndex: -1);
    } else {
      _stops[_placingIndex].lat = pos.latitude;
      _stops[_placingIndex].lng = pos.longitude;
      await _reverseGeocode(pos, stopIndex: _placingIndex);
    }
    if (mounted) {
      setState(() {
        _placingMap = false;
        _geocoding = false;
      });
      _recenterMap();
      _scheduleDraftSave();
    }
  }

  Future<void> _reverseGeocode(LatLng pos, {required int stopIndex}) async {
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
        if (stopIndex == -1) {
          _pickupAddress = result;
        } else {
          _stops[stopIndex].address = result;
        }
      });
    } catch (_) {}
  }

  // ── Sélection d'une suggestion Google Places pour un arrêt ───────────────

  late final _placesService = PlacesAutocompleteService(_publicDio);

  Future<void> _selectStopSuggestion(
    int index,
    Map<String, dynamic> place,
    String sessionToken,
  ) async {
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
    try {
      final result = await _placesService.details(
        placeId: placeId,
        sessionToken: sessionToken,
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
          _stops[index].lat = lat;
          _stops[index].lng = lng;
          _stops[index].address = name;
        });
        _recenterMap();
        _scheduleDraftSave();
      }
    } catch (_) {
      if (mounted)
        showDemToast(
          context,
          'Impossible de charger l\'adresse',
          isError: true,
        );
    }
  }

  // ── Destination récente appliquée à un arrêt ──────────────────────────────

  void _applyRecentDestinationToStop(int index, Map<String, dynamic> dest) {
    final lat = (dest['lat'] as num?)?.toDouble();
    final lng = (dest['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    setState(() {
      _stops[index].lat = lat;
      _stops[index].lng = lng;
      _stops[index].address = dest['address'] as String? ?? '';
      final name = dest['receiverName'] as String?;
      final phone = dest['receiverPhone'] as String?;
      if (name != null && name.isNotEmpty) _stops[index].name = name;
      if (phone != null && phone.isNotEmpty)
        _stops[index].phone = phone.replaceFirst('+221', '');
    });
    _recenterMap();
    _scheduleDraftSave();
  }

  // ── Programmation ─────────────────────────────────────────────────────────

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
            onSurface: AppColors.textPrimary,
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
            onSurface: AppColors.textPrimary,
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
    _scheduleDraftSave();
  }

  // ── Validation & submit ───────────────────────────────────────────────────

  bool get _canSubmit =>
      _pickupLat != null &&
      _stops.every(
        (s) => s.hasLocation && isValidSenegalMobile(s.phone.trim()),
      );

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_canSubmit) {
      showDemToast(
        context,
        _pickupLat == null
            ? 'Définissez le point de départ'
            : 'Chaque arrêt doit avoir une localisation et un numéro mobile valide (7X XXX XX XX)',
        isError: true,
      );
      return;
    }
    if (_isScheduled && _scheduledAt == null) {
      showDemToast(
        context,
        'Choisissez une date et heure pour la tournée',
        isError: true,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final stops = _stops.map((s) {
        final parts = <String>[];
        final pkg = _pkgTypes.firstWhere((p) => p.$1 == s.pkg);
        parts.add(pkg.$2);
        if (s.fragile) parts.add('Fragile');
        return {
          'deliveryAddress': s.address.isNotEmpty
              ? s.address
              : '${s.lat!.toStringAsFixed(4)}, ${s.lng!.toStringAsFixed(4)}',
          'deliveryLatitude': s.lat,
          'deliveryLongitude': s.lng,
          if (s.name.trim().isNotEmpty) 'receiverName': s.name.trim(),
          if (s.phone.trim().isNotEmpty)
            'receiverPhone': '+221${s.phone.trim()}',
          if (s.landmark.trim().isNotEmpty) 'landmark': s.landmark.trim(),
          'description': parts.join(' · '),
        };
      }).toList();

      final batch = await _proRepo.createBatch({
        'pickupAddress': _pickupAddress.isNotEmpty
            ? _pickupAddress
            : '${_pickupLat!.toStringAsFixed(4)}, ${_pickupLng!.toStringAsFixed(4)}',
        'pickupLatitude': _pickupLat,
        'pickupLongitude': _pickupLng,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        if (_scheduledAt != null)
          'scheduledAt': _scheduledAt!.toUtc().toIso8601String(),
        'stops': stops,
      });

      DemProDraftStorage.clearBatchDraft();
      if (mounted) {
        showDemToast(
          context,
          _scheduledAt != null ? 'Tournée programmée !' : 'Tournée lancée !',
        );
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
    }
    for (int i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      if (s.hasLocation && !_placingMap) {
        m.add(
          Marker(
            markerId: MarkerId('stop_$i'),
            position: LatLng(s.lat!, s.lng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(title: 'Arrêt ${i + 1}'),
          ),
        );
      }
    }
    return m;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_placingMap,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _placingMap = false);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Carte
            Positioned.fill(
              child: GoogleMap(
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
              ),
            ),

            // Pin central placement
            if (_placingMap)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _placingIndex == -1
                          ? Icons.inventory_2_rounded
                          : Icons.location_on,
                      color: _placingIndex == -1
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
                      backgroundColor: _placingIndex == -1
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ],
                ),
              ),

            // Header
            if (!_placingMap)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(child: _buildHeader()),
              ),

            // Panel bas — placement (fixe, petit)
            if (_placingMap)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 130 + MediaQuery.of(context).viewPadding.bottom,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
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

            // Panel bas (infos + CTA) — remontent ensemble de façon fluide
            // au-dessus du clavier (même logique que le sheet "Changer le
            // départ") et reviennent à leur position normale à la fermeture
            // du clavier. Le CTA reste hors du panneau rétractable lui-même
            // pour ne jamais pousser la poignée hors de l'écran quand celui-ci
            // est réduit au minimum.
            if (!_placingMap)
              Positioned.fill(
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Stack(
                    children: [
                      DraggableScrollableSheet(
                        initialChildSize: _sheetMax,
                        minChildSize: _sheetMin,
                        maxChildSize: _sheetMax,
                        snap: true,
                        snapSizes: [_sheetMin, _sheetMax],
                        builder: (context, scrollCtrl) => Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
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
                          child: _buildPanel(scrollCtrl),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildLaunchButton(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double get _sheetMin => 0.12;
  double get _sheetMax => 0.62;

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
    child: Row(
      children: [
        IconButton(
          onPressed: () => context.pop(),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_back,
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
              color: AppColors.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.route_outlined,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Nouvelle tournée',
                  style: ClientText.subtitle.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_stops.length} arrêts',
                    style: ClientText.micro.copyWith(color: AppColors.primary),
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
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _placingIndex == -1
                ? 'Positionnez le point de départ'
                : 'Arrêt ${_placingIndex + 1} — Positionnez la destination',
            style: ClientText.bodyStrong.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primary,
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
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Confirmer la position',
                            style: ClientText.button.copyWith(
                              color: AppColors.textPrimary,
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

  // Le CTA (bouton Lancer) n'appartient pas à ce panneau — il flotte en
  // dehors (voir `build` / `_buildLaunchButton`) pour rester visible même
  // quand le panneau est réduit à sa taille minimale. La poignée et le
  // bandeau de départ font partie de la même liste scrollable que le reste
  // (nécessaire pour que le glissé de redimensionnement fonctionne partout,
  // pas seulement sur la liste des arrêts). Un tap dans une zone vide
  // referme le clavier.
  Widget _buildPanel(ScrollController scrollCtrl) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => FocusScope.of(context).unfocus(),
    child: ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),

        // Bandeau départ
        _DepartureBannerBatch(
          label: _selectedAddr?['label'] as String?,
          address: _pickupAddress,
          loading: _loadingGps,
          onTap: () => _showChangeDeparture(),
        ),

        const SizedBox(height: 8),

        ...List.generate(
          _stops.length,
          (i) => StaggeredEntrance(
            index: i,
            child: _StopCard(
              index: i,
              stop: _stops[i],
              canRemove: _stops.length > 2,
              onMapTap: () => _enterMapPlacement(i),
              onRemove: () => setState(() => _stops.removeAt(i)),
              onChanged: () {
                setState(() {});
                _scheduleDraftSave();
              },
              onLocationChanged: _recenterMap,
              publicDio: _publicDio,
              onSuggestionSelected: _selectStopSuggestion,
              recentDestinations: _recentDestinations,
              onApplyRecent: _applyRecentDestinationToStop,
            ),
          ),
        ),

        if (_stops.length < 5)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _stops.add(_Stop())),
              icon: const Icon(Icons.add, color: AppColors.primary, size: 18),
              label: Text(
                'Ajouter un arrêt',
                style: ClientText.bodyStrong.copyWith(color: AppColors.primary),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

        // Notes globales
        const SizedBox(height: 4),
        Text(
          'Instructions pour le livreur (optionnel)',
          style: ClientText.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          onChanged: (_) => _scheduleDraftSave(),
          style: ClientText.body.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText:
                'ex: Sonner à chaque arrêt, ne pas laisser en gardiennage…',
            hintStyle: ClientText.label.copyWith(color: AppColors.textPrimary),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryDark),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryDark),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),

        // Programmation
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isScheduled
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.primaryDark,
            ),
          ),
          child: SwitchListTile(
            value: _isScheduled,
            onChanged: (v) {
              setState(() {
                _isScheduled = v;
                if (!v) _scheduledAt = null;
              });
              if (v) _pickScheduleDate();
            },
            activeTrackColor: AppColors.primary,
            activeThumbColor: Colors.white,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppColors.primaryDark,
            title: Row(
              children: [
                const Icon(Icons.schedule, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Programmer la tournée',
                  style: ClientText.subtitle.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              'Choisir une date et heure',
              style: ClientText.label.copyWith(color: AppColors.textPrimary),
            ),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
          ),
        ),
        if (_isScheduled && _scheduledAt != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickScheduleDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fmtDate(_scheduledAt!),
                        style: ClientText.bodyStrong.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        _fmtTime(_scheduledAt!),
                        style: ClientText.label.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.edit_outlined,
                    color: AppColors.textSecondary,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _buildLaunchButton() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _canSubmit ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(14),
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
              onTap: (_canSubmit && !_submitting) ? _submit : null,
              child: Center(
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _isScheduled
                            ? 'Programmer la tournée'
                            : 'Lancer la tournée (${_stops.length} arrêts)',
                        style: ClientText.button.copyWith(
                          color: _canSubmit
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // ── Sheet changer départ ──────────────────────────────────────────────────

  void _showChangeDeparture() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BatchDepartureSheet(
        proAddresses: _proAddresses,
        selectedId: _selectedAddr?['id'] as String?,
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
          _enterMapPlacement(-1);
        },
        onManualAddress: (lat, lng, address) {
          Navigator.pop(context);
          _applyManualPickup(lat, lng, address);
        },
      ),
    );
  }

  void _applyManualPickup(double lat, double lng, String address) {
    setState(() {
      _selectedAddr = null;
      _pickupLat = lat;
      _pickupLng = lng;
      _pickupAddress = address;
    });
    _recenterMap();
    _scheduleDraftSave();
  }

  static String _fmtDate(DateTime dt) {
    const m = [
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
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }

  static String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte d'un arrêt
// ─────────────────────────────────────────────────────────────────────────────

class _StopCard extends StatefulWidget {
  final int index;
  final _Stop stop;
  final bool canRemove;
  final VoidCallback onMapTap;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onLocationChanged;
  final Dio publicDio;
  final void Function(
    int index,
    Map<String, dynamic> place,
    String sessionToken,
  )
  onSuggestionSelected;
  final List<Map<String, dynamic>> recentDestinations;
  final void Function(int index, Map<String, dynamic> dest) onApplyRecent;
  const _StopCard({
    required this.index,
    required this.stop,
    required this.canRemove,
    required this.onMapTap,
    required this.onRemove,
    required this.onChanged,
    required this.onLocationChanged,
    required this.publicDio,
    required this.onSuggestionSelected,
    required this.recentDestinations,
    required this.onApplyRecent,
  });
  @override
  State<_StopCard> createState() => _StopCardState();
}

class _StopCardState extends State<_StopCard> {
  late final TextEditingController _phoneCtrl = TextEditingController(
    text: widget.stop.phone,
  );
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.stop.name,
  );
  late final TextEditingController _landmarkCtrl = TextEditingController(
    text: widget.stop.landmark,
  );
  late final TextEditingController _addrCtrl = TextEditingController(
    text: widget.stop.address,
  );
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _searching = false;
  String? _searchError;
  String? _sessionToken;
  late final _placesService = PlacesAutocompleteService(widget.publicDio);

  @override
  void dispose() {
    _debounce?.cancel();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _landmarkCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  // Resynchronise les champs si le stop a été modifié depuis l'extérieur
  // (destination récente, pointage carte, brouillon restauré, recommander).
  @override
  void didUpdateWidget(covariant _StopCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final s = widget.stop;
    if (_addrCtrl.text != s.address) _addrCtrl.text = s.address;
    if (_nameCtrl.text != s.name) _nameCtrl.text = s.name;
    if (_phoneCtrl.text != s.phone) _phoneCtrl.text = s.phone;
    if (_landmarkCtrl.text != s.landmark) _landmarkCtrl.text = s.landmark;
  }

  Future<void> _forwardGeocode(String query) async {
    if (query.trim().length < 3) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = [];
      _searching = true;
    });
    try {
      final locations = await geo
          .locationFromAddress('$query, Dakar, Sénégal')
          .timeout(const Duration(seconds: 6));
      if (locations.isEmpty || !mounted) return;
      final loc = locations.first;
      final s = widget.stop;
      s.lat = loc.latitude;
      s.lng = loc.longitude;
      s.address = query.trim();
      _addrCtrl.text = query.trim();
      widget.onChanged();
      widget.onLocationChanged();
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _applyRecent(Map<String, dynamic> dest) {
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = [];
      _addrCtrl.text = dest['address'] as String? ?? '';
    });
    widget.onApplyRecent(widget.index, dest);
  }

  void _onAddrChanged(String query) {
    _debounce?.cancel();
    setState(
      () {},
    ); // reflète immédiatement l'état vide/non-vide (destinations récentes)
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

  void _retrySearch() => _onAddrChanged(_addrCtrl.text);

  @override
  Widget build(BuildContext context) {
    final s = widget.stop;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: s.hasLocation
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.primaryDark,
        ),
        boxShadow: [
          BoxShadow(
            color: (s.hasLocation ? AppColors.primary : Colors.black)
                .withValues(alpha: s.hasLocation ? 0.18 : 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header arrêt
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    '${widget.index + 1}',
                    style: ClientText.label.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Arrêt ${widget.index + 1}',
                    style: ClientText.subtitle.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),

          // Champ recherche + bouton carte
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addrCtrl,
                    style: ClientText.label.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    onChanged: _onAddrChanged,
                    onSubmitted: (q) => _forwardGeocode(q),
                    decoration: InputDecoration(
                      hintText: 'Saisir une adresse…',
                      hintStyle: ClientText.label.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      prefixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Icon(
                              s.hasLocation ? Icons.check_circle : Icons.search,
                              color: s.hasLocation
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                              size: 16,
                            ),
                      suffixIcon: _addrCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: AppColors.textSecondary,
                                size: 14,
                              ),
                              onPressed: () {
                                _addrCtrl.clear();
                                setState(() => _suggestions = []);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.primaryDark,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primaryDark,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: s.hasLocation
                              ? AppColors.success.withValues(alpha: 0.5)
                              : AppColors.primaryDark,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: widget.onMapTap,
                  child: Container(
                    width: 46,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.map_outlined,
                          color: AppColors.primary,
                          size: 15,
                        ),
                        Text(
                          'Carte',
                          style: ClientText.micro.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Destinations récentes (avant saisie)
          if (_addrCtrl.text.isEmpty &&
              _suggestions.isEmpty &&
              !s.hasLocation &&
              widget.recentDestinations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: AppColors.primaryDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.card),
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.history,
                            color: AppColors.textSecondary,
                            size: 12,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Récentes',
                            style: ClientText.micro.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...widget.recentDestinations.map(
                      (d) => InkWell(
                        onTap: () => _applyRecent(d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.place_outlined,
                                color: AppColors.primary,
                                size: 13,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  d['address'] as String? ?? '',
                                  style: ClientText.label.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Suggestions
          if (_suggestions.isNotEmpty || _searching || _searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: PlaceSuggestionsList(
                suggestions: _suggestions,
                loading: _searching,
                error: _searchError,
                onRetry: _retrySearch,
                maxHeight: 150,
                colors: _placeSuggestionsColors,
                onSelect: (p) {
                  final fmt =
                      p['structured_formatting'] as Map<String, dynamic>?;
                  final main =
                      fmt?['main_text'] as String? ??
                      p['description'] as String? ??
                      '';
                  _addrCtrl.text = main;
                  setState(() => _suggestions = []);
                  FocusScope.of(context).unfocus();
                  final token =
                      _sessionToken ??
                      PlacesAutocompleteService.newSessionToken();
                  widget.onSuggestionSelected(widget.index, p, token);
                  _sessionToken = null;
                },
              ),
            ),
          const SizedBox(height: 8),

          // Téléphone destinataire
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _MiniField(
              ctrl: _phoneCtrl,
              hint: 'Tél destinataire *',
              prefix: '+221',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onChanged: (v) {
                s.phone = v;
                widget.onChanged();
              },
              suffixIcon: _phoneCtrl.text.isEmpty
                  ? null
                  : Icon(
                      isValidSenegalMobile(_phoneCtrl.text.trim())
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: isValidSenegalMobile(_phoneCtrl.text.trim())
                          ? AppColors.success
                          : AppColors.error,
                      size: 16,
                    ),
            ),
          ),
          const SizedBox(height: 6),

          // Nom destinataire
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _MiniField(
              ctrl: _nameCtrl,
              hint: 'Nom destinataire (optionnel)',
              textInputAction: TextInputAction.next,
              onChanged: (v) {
                s.name = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(height: 6),

          // Repère
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _MiniField(
              ctrl: _landmarkCtrl,
              hint: 'Repère (optionnel)',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onChanged: (v) {
                s.landmark = v;
                widget.onChanged();
              },
            ),
          ),
          const SizedBox(height: 8),

          // Type de colis
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: _pkgTypes.map((t) {
                final sel = s.pkg == t.$1;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          s.pkg = t.$1;
                        });
                        widget.onChanged();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.primaryDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: sel
                                ? AppColors.primary
                                : AppColors.primaryDark,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              t.$3,
                              color: sel
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              size: 16,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              t.$2.split(' ').first,
                              style: ClientText.micro.copyWith(
                                color: sel
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Fragile
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                Checkbox(
                  value: s.fragile,
                  onChanged: (v) {
                    setState(() {
                      s.fragile = v ?? false;
                    });
                    widget.onChanged();
                  },
                  activeColor: AppColors.warning,
                  side: const BorderSide(color: AppColors.textSecondary),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 4),
                Text(
                  'Fragile',
                  style: ClientText.label.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final String? prefix;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  const _MiniField({
    required this.ctrl,
    required this.hint,
    this.prefix,
    this.keyboardType,
    this.onChanged,
    this.suffixIcon,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: keyboardType,
    onChanged: onChanged,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    style: ClientText.body.copyWith(color: AppColors.textPrimary),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: ClientText.label.copyWith(color: AppColors.textPrimary),
      prefixText: prefix,
      prefixStyle: ClientText.label.copyWith(fontSize: 13),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.primaryDark,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
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
  const _DepartureBannerBatch({
    required this.label,
    required this.address,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDark),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: loading
                ? Text(
                    'Localisation…',
                    style: ClientText.label.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (label != null)
                        Text(
                          label!,
                          style: ClientText.label.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        address != null && address!.isNotEmpty
                            ? address!
                            : 'Aucun départ',
                        style: ClientText.label.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            'Changer',
            style: ClientText.micro.copyWith(color: AppColors.primary),
          ),
          const Icon(Icons.chevron_right, color: AppColors.primary, size: 14),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet changement de départ (réutilise la même logique)
// ─────────────────────────────────────────────────────────────────────────────

class _BatchDepartureSheet extends StatefulWidget {
  final List<Map<String, dynamic>> proAddresses;
  final String? selectedId;
  final bool loadingGps;
  final Dio dio;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onGps, onMap;
  final void Function(double lat, double lng, String address) onManualAddress;
  const _BatchDepartureSheet({
    required this.proAddresses,
    required this.selectedId,
    required this.loadingGps,
    required this.dio,
    required this.onSelect,
    required this.onGps,
    required this.onMap,
    required this.onManualAddress,
  });

  @override
  State<_BatchDepartureSheet> createState() => _BatchDepartureSheetState();
}

class _BatchDepartureSheetState extends State<_BatchDepartureSheet> {
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
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Text(
              'Point de départ',
              style: ClientText.title.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _searchCtrl,
              style: ClientText.body.copyWith(color: AppColors.textPrimary),
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _submitManual,
              decoration: InputDecoration(
                hintText: 'Saisir l\'adresse d\'expédition…',
                hintStyle: ClientText.label.copyWith(
                  color: AppColors.textPrimary,
                ),
                prefixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.search,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primaryDark),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primaryDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
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

            if (widget.proAddresses.isNotEmpty) ...[
              Text(
                'Mes adresses',
                style: ClientText.micro.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              ...widget.proAddresses.map((a) {
                final sel = a['id'] == widget.selectedId;
                final icon =
                    _iconMap[a['icon'] as String? ?? 'other'] ??
                    Icons.place_outlined;
                return GestureDetector(
                  onTap: () => widget.onSelect(a),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.primary.withValues(alpha: 0.10)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel ? AppColors.primary : AppColors.primaryDark,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a['label'] as String? ?? '',
                                style: ClientText.bodyStrong.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                a['address'] as String? ?? '',
                                style: ClientText.label.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (sel)
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
            _SheetActionBtn(
              icon: Icons.my_location,
              label: 'Ma position actuelle',
              loading: widget.loadingGps,
              onTap: widget.onGps,
            ),
            const SizedBox(height: 8),
            _SheetActionBtn(
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

class _SheetActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _SheetActionBtn({
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
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryDark),
      ),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
            )
          : Row(
              children: [
                Icon(icon, color: AppColors.textSecondary, size: 18),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: ClientText.bodyStrong.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet — reprise de brouillon (tournée)
// ─────────────────────────────────────────────────────────────────────────────

class _BatchDraftResumeSheet extends StatelessWidget {
  final String? savedAt;
  final VoidCallback onResume;
  final VoidCallback onDiscard;
  const _BatchDraftResumeSheet({
    required this.savedAt,
    required this.onResume,
    required this.onDiscard,
  });

  String get _label {
    final dt = savedAt != null ? DateTime.tryParse(savedAt!)?.toLocal() : null;
    if (dt == null) return 'Vous avez une tournée en cours de saisie.';
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryDark),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route_outlined, color: AppColors.primary, size: 32),
          const SizedBox(height: 12),
          Text(
            'Reprendre votre brouillon ?',
            style: ClientText.title.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            _label,
            textAlign: TextAlign.center,
            style: ClientText.label.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDiscard,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryDark),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Nouvelle tournée',
                    style: ClientText.bodyStrong.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onResume,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Reprendre',
                    style: ClientText.button.copyWith(
                      color: AppColors.textPrimary,
                    ),
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
