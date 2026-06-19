import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/map_theme_provider.dart';
import '../../deliveries/providers/orders_provider.dart';
import '../../home_driver/navigation/map_theme.dart';
import '../theme/dem_pro_colors.dart';

class DemProOrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String driverId;
  final int? etaPickupMin;
  final Map<String, dynamic>? initialOrder;

  const DemProOrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.driverId,
    this.etaPickupMin,
    this.initialOrder,
  });

  @override
  ConsumerState<DemProOrderTrackingScreen> createState() =>
      _DemProOrderTrackingScreenState();
}

class _DemProOrderTrackingScreenState
    extends ConsumerState<DemProOrderTrackingScreen> {
  // ── Map ───────────────────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  BitmapDescriptor? _driverIcon;
  LatLng? _driverPos;

  // ── Ordre ─────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _order;
  String _status = 'ACCEPTED';
  bool _done = false;

  // ── Route ─────────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];

  // ── Sockets ───────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _locationSub;
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  // ── Polling ───────────────────────────────────────────────────────────────
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _status = (widget.initialOrder?['status'] as String? ?? 'ACCEPTED').toUpperCase();
    _loadMapStyle();
    _buildDriverIcon();
    _fetchRoute();
    _connectSocket();
    _startPolling();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _statusSub?.cancel();
    _pollTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Setup ─────────────────────────────────────────────────────────────────
  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _buildDriverIcon() async {
    _driverIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(40, 40)),
      'assets/images/moto_marker.png',
    );
  }

  // ── Socket ────────────────────────────────────────────────────────────────
  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;
    SocketService.instance.connect(token);

    _locationSub = SocketService.instance.onDriverLocation.listen((data) {
      if (!mounted) return;
      final driverId = data['driverId'] as String?;
      if (driverId != widget.driverId) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      setState(() => _driverPos = LatLng(lat, lng));
      _mapCtrl?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
    });

    _statusSub = SocketService.instance.onOrderStatusUpdated.listen((data) {
      if (!mounted) return;
      if (data['orderId'] != widget.orderId) return;
      final s = (data['status'] as String? ?? '').toUpperCase();
      setState(() => _status = s);
      if (s == 'DELIVERED') {
        _pollTimer?.cancel();
        _showCompletionDialog();
      }
    });
  }

  // ── Polling ───────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || _done) return;
      try {
        final order = await ref
            .read(ordersRepositoryProvider)
            .getOrderById(widget.orderId);
        if (!mounted) return;
        final s = (order['status'] as String? ?? '').toUpperCase();
        setState(() {
          _order = order;
          _status = s;
        });
        if (s == 'DELIVERED' || s == 'CANCELLED') {
          _pollTimer?.cancel();
          if (s == 'DELIVERED') _showCompletionDialog();
          if (s == 'CANCELLED' && mounted) context.go('/dem-pro/home');
        }
      } catch (_) {}
    });
  }

  // ── Route ─────────────────────────────────────────────────────────────────
  Future<void> _fetchRoute() async {
    final o = _order ?? widget.initialOrder;
    if (o == null) return;
    final pLat = o['pickupLatitude']    as double?;
    final pLng = o['pickupLongitude']   as double?;
    final dLat = o['deliveryLatitude']  as double?;
    final dLng = o['deliveryLongitude'] as double?;
    if (pLat == null || pLng == null || dLat == null || dLng == null) return;
    try {
      final res = await Dio().get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin':      '$pLat,$pLng',
          'destination': '$dLat,$dLng',
          'key':         AppConfig.mapsApiKey,
        },
      );
      final steps = (res.data['routes'] as List?)?.first['legs']?.first['steps'] as List?;
      if (steps == null || !mounted) return;
      final pts = <LatLng>[];
      for (final s in steps) {
        pts.addAll(_decodePolyline(s['polyline']['points'] as String));
      }
      if (mounted) setState(() => _routePoints = pts);
    } catch (_) {}
  }

  List<LatLng> _decodePolyline(String encoded) {
    final pts = <LatLng>[];
    int idx = 0, lat = 0, lng = 0;
    while (idx < encoded.length) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(idx++) - 63; result |= (b & 0x1F) << shift; shift += 5; } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(idx++) - 63; result |= (b & 0x1F) << shift; shift += 5; } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
  }

  // ── Completion ────────────────────────────────────────────────────────────
  void _showCompletionDialog() {
    if (_done) return;
    _done = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: DemProColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: DemProColors.success, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Livraison effectuée !',
            style: TextStyle(
              color: Color(0xFFE8F4F8),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Commande #${widget.orderId.substring(0, 8).toUpperCase()} livrée avec succès.',
            style: const TextStyle(color: Color(0xFF6B8BAA), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/dem-pro/home');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DemProColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Retour au tableau de bord',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Contact livreur ───────────────────────────────────────────────────────
  void _callDriver() {
    final phone = (_order?['driver'] as Map?)?['phone'] as String?;
    if (phone == null) return;
    launchUrl(Uri.parse('tel:$phone'));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _short(String? addr) =>
      (addr == null || addr.isEmpty) ? '—' : addr.split(',').first.trim();

  (String, Color) get _statusInfo => switch (_status) {
    'ACCEPTED'  => ('Livreur en route vers le colis', DemProColors.accent),
    'PICKED_UP' => ('Colis récupéré · En route', DemProColors.warning),
    'DELIVERED' => ('Livraison effectuée', DemProColors.success),
    'CANCELLED' => ('Commande annulée', DemProColors.danger),
    _           => ('En attente', const Color(0xFF6B8BAA)),
  };

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final o        = _order ?? widget.initialOrder ?? {};
    final pLat     = o['pickupLatitude']    as double? ?? 14.6928;
    final pLng     = o['pickupLongitude']   as double? ?? -17.4467;
    final dLat     = o['deliveryLatitude']  as double? ?? 14.6928;
    final dLng     = o['deliveryLongitude'] as double? ?? -17.4467;
    final pickup   = _short(o['pickupAddress']   as String?);
    final delivery = _short(o['deliveryAddress'] as String?);
    final price    = (o['price'] as num?) ?? 0;
    final driver   = o['driver'] as Map<String, dynamic>?;
    final dName    = driver?['name'] as String? ?? 'Livreur DEM';
    final dPhone   = driver?['phone'] as String?;
    final (statusLabel, statusColor) = _statusInfo;

    // Marqueurs
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pLat, pLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(dLat, dLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      if (_driverPos != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPos!,
          icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        ),
    };

    final initTarget = _driverPos ?? LatLng((pLat + dLat) / 2, (pLng + dLng) / 2);

    return Scaffold(
      backgroundColor: DemProColors.bg,
      body: Stack(
        children: [
          // ── Carte ────────────────────────────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: initTarget, zoom: 14),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              style: _mapStyle,
              markers: markers,
              polylines: _routePoints.isNotEmpty
                  ? {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: _routePoints,
                        color: DemProColors.accent,
                        width: 4,
                      ),
                    }
                  : {},
              onMapCreated: (c) {
                _mapCtrl = c;
                if (_driverPos == null) {
                  final sw = LatLng(min(pLat, dLat), min(pLng, dLng));
                  final ne = LatLng(max(pLat, dLat), max(pLng, dLng));
                  c.animateCamera(
                    CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 80),
                  );
                }
              },
            ),
          ),

          // ── Dégradé haut ─────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0, height: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [DemProColors.bg.withValues(alpha: 0.9), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── App bar ───────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12, right: 12,
            child: Row(children: [
              _MapBtn(
                icon: Icons.arrow_back,
                onTap: () => context.go('/dem-pro/home'),
              ),
              const Spacer(),
              _MapBtn(
                icon: Icons.my_location,
                onTap: () {
                  final pos = _driverPos ?? LatLng(pLat, pLng);
                  _mapCtrl?.animateCamera(CameraUpdate.newLatLng(pos));
                },
              ),
            ]),
          ),

          // ── Panel bas ─────────────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                color: DemProColors.bg2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Pill drag indicator
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // ── Statut ─────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    statusLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Livreur ────────────────────────────────────────────────
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: DemProColors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _initials(dName),
                        style: const TextStyle(
                          color: DemProColors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(dName,
                          style: const TextStyle(
                              color: Color(0xFFE8F4F8),
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const Text('Livreur DEM',
                          style: TextStyle(color: Color(0xFF6B8BAA), fontSize: 12)),
                    ]),
                  ),
                  if (dPhone != null)
                    _ActionChip(
                      icon: Icons.phone_outlined,
                      label: 'Appeler',
                      onTap: _callDriver,
                    ),
                ]),
                const SizedBox(height: 16),

                // ── Adresses ───────────────────────────────────────────────
                _AddressCard(pickup: pickup, delivery: delivery),
                const SizedBox(height: 14),

                // ── Prix ───────────────────────────────────────────────────
                Row(children: [
                  const Icon(Icons.payments_outlined,
                      color: Color(0xFF6B8BAA), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${price.toInt()} FCFA',
                    style: const TextStyle(
                        color: Color(0xFFE8F4F8),
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '#${widget.orderId.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(color: Color(0xFF6B8BAA), fontSize: 12),
                  ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _MapBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF0C1628).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Icon(icon, color: const Color(0xFFE8F4F8), size: 20),
    ),
  );
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DemProColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DemProColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: DemProColors.accent, size: 14),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                color: DemProColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _AddressCard extends StatelessWidget {
  final String pickup;
  final String delivery;
  const _AddressCard({required this.pickup, required this.delivery});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF111E35),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.radio_button_on, color: Color(0xFF00E08C), size: 13),
        const SizedBox(width: 10),
        Expanded(
          child: Text(pickup,
              style: const TextStyle(color: Color(0xFFE8F4F8), fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 6, top: 3, bottom: 3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(width: 1.5, height: 10, color: const Color(0xFF1E3050)),
        ),
      ),
      Row(children: [
        const Icon(Icons.location_on, color: Color(0xFFFF5C5C), size: 13),
        const SizedBox(width: 10),
        Expanded(
          child: Text(delivery,
              style: const TextStyle(color: Color(0xFFE8F4F8), fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    ]),
  );
}
