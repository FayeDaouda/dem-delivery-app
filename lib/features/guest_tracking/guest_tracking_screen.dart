import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../home_driver/navigation/directions_service.dart';

const _accent = Color(0xFF00AECB);
const _bg = Color(0xFF0A1628);
const _bg2 = Color(0xFF0F1E36);
const _bg3 = Color(0xFF111E35);
const _textColor = Color(0xFFE8F4F8);
const _muted = Color(0xFF6B8BAA);
const _success = Color(0xFF00E08C);
const _danger = Color(0xFFFF5C5C);
const _warning = Color(0xFFFFB830);

const _steps = ['PENDING', 'ACCEPTED', 'PICKED_UP', 'DELIVERED'];

class GuestTrackingScreen extends StatefulWidget {
  final String orderId;
  const GuestTrackingScreen({super.key, required this.orderId});
  @override
  State<GuestTrackingScreen> createState() => _GuestTrackingScreenState();
}

class _GuestTrackingScreenState extends State<GuestTrackingScreen> {
  final _dio = Dio(BaseOptions(
    baseUrl: 'https://api.dem.sn',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  Timer? _pollTimer;

  Map<String, dynamic>? _order;
  LatLng? _driverPos;
  List<LatLng> _routePoints = [];
  bool _loading = true;
  bool _expired = false;
  String? _error;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchOrder();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchOrder());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString('assets/map_style_waze.json');
      if (mounted) setState(() => _mapStyle = style);
    } catch (_) {}
  }

  Future<void> _fetchOrder() async {
    try {
      final res = await _dio.get('/orders/guest/${widget.orderId}');
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      final driver = data['driver'] as Map<String, dynamic>?;
      final lat = (driver?['latitude'] as num?)?.toDouble();
      final lng = (driver?['longitude'] as num?)?.toDouble();

      final isFirst = _order == null;
      setState(() {
        _order = data;
        _loading = false;
        _expired = data['isExpired'] == true;
        _lastUpdate = DateTime.now();
        if (lat != null && lng != null && lat != 0 && lng != 0) {
          _driverPos = LatLng(lat, lng);
        }
      });

      if (_driverPos != null && !isFirst) {
        _mapCtrl?.animateCamera(CameraUpdate.newLatLng(_driverPos!));
      }

      if (isFirst) _fetchRoute();
      if (_expired) _pollTimer?.cancel();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 404) {
        setState(() { _error = 'Commande introuvable.'; _loading = false; });
        _pollTimer?.cancel();
      } else {
        if (_order == null) setState(() { _error = 'Erreur de connexion.'; _loading = false; });
      }
    }
  }

  Future<void> _fetchRoute() async {
    final o = _order;
    if (o == null) return;
    final pLat = (o['pickupLatitude'] as num?)?.toDouble();
    final pLng = (o['pickupLongitude'] as num?)?.toDouble();
    final dLat = (o['deliveryLatitude'] as num?)?.toDouble();
    final dLng = (o['deliveryLongitude'] as num?)?.toDouble();
    if (pLat == null || pLng == null || dLat == null || dLng == null) return;

    try {
      final result = await DirectionsService.getRoute(
        origin: LatLng(pLat, pLng),
        destination: LatLng(dLat, dLng),
        apiKey: AppConfig.mapsApiKey,
      );
      if (mounted) {
        setState(() => _routePoints = result.points);
        _fitBounds(LatLng(pLat, pLng), LatLng(dLat, dLng));
      }
    } catch (_) {}
  }

  void _fitBounds(LatLng a, LatLng b) {
    _mapCtrl?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(min(a.latitude, b.latitude), min(a.longitude, b.longitude)),
        northeast: LatLng(max(a.latitude, b.latitude), max(a.longitude, b.longitude)),
      ),
      80,
    ));
  }

  int get _currentStepIndex {
    final s = (_order?['status'] as String? ?? '').toUpperCase();
    if (s == 'CANCELLED') return -1;
    final idx = _steps.indexOf(s);
    return idx >= 0 ? idx : 0;
  }

  (String, Color, IconData) get _statusInfo {
    final s = (_order?['status'] as String? ?? '').toUpperCase();
    return switch (s) {
      'PENDING'    => ('En recherche de livreur', _warning, Icons.search),
      'ACCEPTED'   => ('Livreur en route vers le colis', _accent, Icons.two_wheeler),
      'PICKED_UP'  => ('Colis récupéré — en route', _warning, Icons.local_shipping),
      'IN_TRANSIT' => ('En cours de livraison', _accent, Icons.local_shipping),
      'DELIVERED'  => ('Livraison effectuée', _success, Icons.check_circle),
      'CANCELLED'  => ('Commande annulée', _danger, Icons.cancel),
      _            => ('En attente', _muted, Icons.hourglass_empty),
    };
  }

  String? get _etaInfo {
    if (_driverPos == null || _order == null) return null;
    final o = _order!;
    final s = (o['status'] as String? ?? '').toUpperCase();
    final targetLat = s == 'PICKED_UP'
        ? (o['deliveryLatitude'] as num?)?.toDouble()
        : (o['pickupLatitude'] as num?)?.toDouble();
    final targetLng = s == 'PICKED_UP'
        ? (o['deliveryLongitude'] as num?)?.toDouble()
        : (o['pickupLongitude'] as num?)?.toDouble();
    if (targetLat == null || targetLng == null) return null;
    final km = _haversineKm(_driverPos!.latitude, _driverPos!.longitude, targetLat, targetLng);
    final mins = (km / 25 * 60).round();
    if (km < 1) return '${(km * 1000).round()} m — ~$mins min';
    return '${km.toStringAsFixed(1)} km — ~$mins min';
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    const deg = 3.141592653589793 / 180;
    final dLat = (lat2 - lat1) * deg;
    final dLng = (lng2 - lng1) * deg;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * deg) * cos(lat2 * deg) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String _short(String? addr) =>
      (addr == null || addr.isEmpty) ? '—' : addr.split(',').first.trim();

  String get _updatedAgo {
    if (_lastUpdate == null) return '';
    final diff = DateTime.now().difference(_lastUpdate!);
    if (diff.inSeconds < 10) return 'à l\'instant';
    if (diff.inSeconds < 60) return 'il y a ${diff.inSeconds}s';
    return 'il y a ${diff.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: _accent),
          SizedBox(height: 16),
          Text('Chargement du suivi…', style: TextStyle(color: _muted, fontSize: 13)),
        ])),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, color: _danger, size: 36),
            ),
            const SizedBox(height: 20),
            Text(_error!, style: const TextStyle(color: _textColor, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Vérifiez le lien et réessayez.', style: TextStyle(color: _muted, fontSize: 13)),
            const SizedBox(height: 24),
            _CTA(label: 'Télécharger DEM', onTap: _openStore),
          ]),
        )),
      );
    }

    final o = _order!;
    final pLat = (o['pickupLatitude'] as num?)?.toDouble() ?? 14.6928;
    final pLng = (o['pickupLongitude'] as num?)?.toDouble() ?? -17.4467;
    final dLat = (o['deliveryLatitude'] as num?)?.toDouble() ?? 14.6928;
    final dLng = (o['deliveryLongitude'] as num?)?.toDouble() ?? -17.4467;
    final pickup = _short(o['pickupAddress'] as String?);
    final delivery = _short(o['deliveryAddress'] as String?);
    final driver = o['driver'] as Map<String, dynamic>?;
    final driverName = driver?['name'] as String? ?? 'Livreur';
    final driverAvatar = driver?['avatar'] as String?;
    final vehiclePlate = driver?['vehiclePlate'] as String?;
    final (statusLabel, statusColor, statusIcon) = _statusInfo;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pLat, pLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Départ', snippet: pickup),
      ),
      Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(dLat, dLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Destination', snippet: delivery),
      ),
      if (_driverPos != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPos!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: InfoWindow(title: driverName),
        ),
    };

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        // Carte
        Positioned.fill(child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _driverPos ?? LatLng((pLat + dLat) / 2, (pLng + dLng) / 2),
            zoom: 14,
          ),
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          style: _mapStyle,
          markers: markers,
          polylines: _routePoints.isNotEmpty ? {
            Polyline(
              polylineId: const PolylineId('route'),
              points: _routePoints,
              color: _accent,
              width: 4,
            ),
          } : {},
          onMapCreated: (c) {
            _mapCtrl = c;
            _fitBounds(LatLng(pLat, pLng), LatLng(dLat, dLng));
          },
        )),

        // Header
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12, right: 12,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _bg2.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accent.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.two_wheeler, color: _accent, size: 18),
                const SizedBox(width: 8),
                const Text('DEM', style: TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(width: 4),
                const Text('Suivi', style: TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
            ),
            const Spacer(),
            if (_lastUpdate != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _bg2.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: _expired ? _muted : _success, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(_updatedAgo, style: const TextStyle(color: _muted, fontSize: 10)),
                ]),
              ),
          ]),
        ),

        // Panel bas
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: _bg2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Pill
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),

              // Timeline stepper
              if (_currentStepIndex >= 0) ...[
                _StepperRow(currentIndex: _currentStepIndex),
                const SizedBox(height: 14),
              ],

              // Statut + ETA
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                ),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(statusIcon, color: statusColor, size: 16),
                    const SizedBox(width: 8),
                    Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                  if (_etaInfo != null) ...[
                    const SizedBox(height: 4),
                    Text(_etaInfo!, style: TextStyle(color: statusColor.withValues(alpha: 0.7), fontSize: 11)),
                  ],
                ]),
              ),
              const SizedBox(height: 12),

              // Driver
              if (driver != null && !_expired)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _accent.withValues(alpha: 0.12),
                      backgroundImage: driverAvatar != null ? NetworkImage(driverAvatar) : null,
                      child: driverAvatar == null
                          ? Text(driverName.isNotEmpty ? driverName[0].toUpperCase() : '?',
                              style: const TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: 16))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(driverName, style: const TextStyle(color: _textColor, fontSize: 13, fontWeight: FontWeight.w700)),
                      if (vehiclePlate != null)
                        Text(vehiclePlate, style: const TextStyle(color: _muted, fontSize: 11)),
                    ])),
                  ]),
                ),

              // Adresses
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: _bg3, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.radio_button_on, color: _success, size: 12),
                    const SizedBox(width: 10),
                    Expanded(child: Text(pickup, style: const TextStyle(color: _textColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(left: 5, top: 2, bottom: 2),
                    child: Align(alignment: Alignment.centerLeft, child: Container(width: 1.5, height: 8, color: const Color(0xFF1E3050))),
                  ),
                  Row(children: [
                    const Icon(Icons.location_on, color: _danger, size: 12),
                    const SizedBox(width: 10),
                    Expanded(child: Text(delivery, style: const TextStyle(color: _textColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ]),
              ),

              // Expiré ou CTA
              const SizedBox(height: 12),
              if (_expired)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: _muted.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                  child: const Text('Ce suivi n\'est plus actif', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
                )
              else
                _CTA(label: 'Télécharger DEM', onTap: _openStore),
            ]),
          ),
        ),
      ]),
    );
  }

  void _openStore() {
    final uri = Uri.parse(Theme.of(context).platform == TargetPlatform.iOS
        ? 'https://apps.apple.com/us/app/dem-livraison/id6764724342?l=fr-FR'
        : 'https://play.google.com/store/apps/details?id=sn.dem.demapp');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ── Timeline stepper ─────────────────────────────────────────────────────────

class _StepperRow extends StatelessWidget {
  final int currentIndex;
  const _StepperRow({required this.currentIndex});

  static const _labels = ['Recherche', 'Accepté', 'Récupéré', 'Livré'];
  static const _icons = [Icons.search, Icons.check, Icons.inventory_2, Icons.flag];

  @override
  Widget build(BuildContext context) {
    return Row(children: List.generate(4, (i) {
      final done = i <= currentIndex;
      final active = i == currentIndex;
      return Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (i > 0) Expanded(child: Container(height: 2, color: done ? _accent : const Color(0xFF1E3050))),
          Container(
            width: active ? 28 : 22,
            height: active ? 28 : 22,
            decoration: BoxDecoration(
              color: done ? _accent.withValues(alpha: active ? 0.2 : 0.1) : const Color(0xFF1E3050),
              shape: BoxShape.circle,
              border: Border.all(color: done ? _accent : const Color(0xFF1E3050), width: active ? 2 : 1),
            ),
            child: Icon(_icons[i], size: active ? 14 : 10, color: done ? _accent : _muted),
          ),
          if (i < 3) Expanded(child: Container(height: 2, color: i < currentIndex ? _accent : const Color(0xFF1E3050))),
        ]),
        const SizedBox(height: 4),
        Text(_labels[i], style: TextStyle(color: done ? _accent : _muted, fontSize: 9, fontWeight: done ? FontWeight.w700 : FontWeight.w500)),
      ]));
    }));
  }
}

// ── CTA Button ───────────────────────────────────────────────────────────────

class _CTA extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CTA({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.download_outlined, color: _accent, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}
