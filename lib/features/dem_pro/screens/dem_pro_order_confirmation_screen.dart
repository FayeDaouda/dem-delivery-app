import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/map_theme_provider.dart';
import '../../deliveries/providers/orders_provider.dart';
import '../../home_driver/navigation/map_theme.dart';
import '../theme/dem_pro_colors.dart';

class DemProOrderConfirmationScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  const DemProOrderConfirmationScreen({super.key, required this.order});

  @override
  ConsumerState<DemProOrderConfirmationScreen> createState() =>
      _DemProOrderConfirmationScreenState();
}

class _DemProOrderConfirmationScreenState
    extends ConsumerState<DemProOrderConfirmationScreen>
    with SingleTickerProviderStateMixin {
  // ── Map ───────────────────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  List<LatLng> _routePoints = [];

  // ── Socket + polling ──────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _acceptedSub;
  Timer? _pollTimer;

  // ── Attente ───────────────────────────────────────────────────────────────
  int _waitSec = 0;
  Timer? _waitTimer;
  bool _timedOut = false;
  bool _cancelling = false;

  // ── Radar ─────────────────────────────────────────────────────────────────
  late final AnimationController _radarCtrl;
  late final Animation<double> _radarAnim;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchRoute();
    _connectSocket();
    _startPolling();

    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _radarAnim = CurvedAnimation(parent: _radarCtrl, curve: Curves.easeOut);

    _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _waitSec++;
        if (_waitSec >= 300 && !_timedOut) _timedOut = true;
      });
    });
  }

  @override
  void dispose() {
    _acceptedSub?.cancel();
    _pollTimer?.cancel();
    _waitTimer?.cancel();
    _mapCtrl?.dispose();
    _radarCtrl.dispose();
    super.dispose();
  }

  // ── Socket ────────────────────────────────────────────────────────────────
  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;
    SocketService.instance.connect(token);
    final orderId = widget.order['id'] as String?;
    _acceptedSub = SocketService.instance.onOrderAccepted.listen((data) {
      if (!mounted) return;
      if (orderId != null && data['orderId'] != orderId) return;
      final driverId = data['driverId'] as String?;
      if (driverId == null) return;
      _pollTimer?.cancel();
      _goTracking(
        orderId: data['orderId'] as String,
        driverId: driverId,
        etaPickupMin: data['etaPickupMin'] as int?,
        order: {...widget.order, 'status': 'ACCEPTED', 'driverId': driverId},
      );
    });
  }

  // ── Polling fallback ──────────────────────────────────────────────────────
  void _startPolling() {
    final orderId = widget.order['id'] as String?;
    if (orderId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      try {
        final order = await ref.read(ordersRepositoryProvider).getOrderById(orderId);
        final status = (order['status'] as String? ?? '').toUpperCase();
        if (!mounted) return;
        if (status == 'ACCEPTED') {
          _pollTimer?.cancel();
          final driverId = (order['driver'] as Map?)?['id'] as String?
              ?? order['driverId'] as String?;
          if (driverId == null) return;
          _goTracking(
            orderId: orderId,
            driverId: driverId,
            order: {...order, 'status': 'ACCEPTED'},
          );
        } else if (status == 'CANCELLED') {
          _pollTimer?.cancel();
          if (mounted) context.go('/dem-pro/home');
        }
      } catch (_) {}
    });
  }

  void _goTracking({
    required String orderId,
    required String driverId,
    int? etaPickupMin,
    required Map<String, dynamic> order,
  }) {
    context.pushReplacement('/dem-pro/orders/tracking', extra: {
      'orderId': orderId,
      'driverId': driverId,
      if (etaPickupMin != null) 'etaPickupMin': etaPickupMin,
      'initialOrder': order,
    });
  }

  // ── Map ───────────────────────────────────────────────────────────────────
  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _fetchRoute() async {
    final pLat = widget.order['pickupLatitude']   as double?;
    final pLng = widget.order['pickupLongitude']  as double?;
    final dLat = widget.order['deliveryLatitude'] as double?;
    final dLng = widget.order['deliveryLongitude'] as double?;
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
        final decoded = _decodePolyline(s['polyline']['points'] as String);
        pts.addAll(decoded);
      }
      if (mounted) setState(() => _routePoints = pts);
      _fitBounds(
        LatLng(pLat, pLng),
        LatLng(dLat, dLng),
      );
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

  List<LatLng> _decodePolyline(String encoded) {
    final pts = <LatLng>[];
    int idx = 0;
    int lat = 0, lng = 0;
    while (idx < encoded.length) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(idx++) - 63; result |= (b & 0x1F) << shift; shift += 5; } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(idx++) - 63; result |= (b & 0x1F) << shift; shift += 5; } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;
      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
  }

  // ── Annulation ────────────────────────────────────────────────────────────
  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0C1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Annuler la livraison ?',
            style: TextStyle(color: Color(0xFFE8F4F8), fontWeight: FontWeight.w700)),
        content: const Text(
          'La commande sera annulée et aucun montant ne sera débité.',
          style: TextStyle(color: Color(0xFF6B8BAA)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer d\'attendre',
                style: TextStyle(color: Color(0xFF00AECB))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler', style: TextStyle(color: Color(0xFFFF5C5C))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final orderId = widget.order['id'] as String?;
      if (orderId != null) {
        await ref.read(ordersRepositoryProvider).cancelOrder(orderId);
      }
    } catch (_) {}
    if (mounted) context.go('/dem-pro/home');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String get _waitLabel {
    if (_waitSec < 60) return '$_waitSec s';
    final m = _waitSec ~/ 60;
    final s = _waitSec % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String _short(String? addr) {
    if (addr == null || addr.isEmpty) return '—';
    return addr.split(',').first.trim();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final pLat = widget.order['pickupLatitude']   as double? ?? 14.6928;
    final pLng = widget.order['pickupLongitude']  as double? ?? -17.4467;
    final dLat = widget.order['deliveryLatitude'] as double? ?? 14.6928;
    final dLng = widget.order['deliveryLongitude'] as double? ?? -17.4467;
    final pickup   = _short(widget.order['pickupAddress']   as String?);
    final delivery = _short(widget.order['deliveryAddress'] as String?);
    final price    = (widget.order['price'] as num?) ?? 0;

    return Scaffold(
      backgroundColor: DemProColors.bg,
      body: Stack(
        children: [
          // ── Carte ────────────────────────────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng((pLat + dLat) / 2, (pLng + dLng) / 2),
                zoom: 13,
              ),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              style: _mapStyle,
              onMapCreated: (c) {
                _mapCtrl = c;
                _fitBounds(LatLng(pLat, pLng), LatLng(dLat, dLng));
              },
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
              markers: {
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: DemProColors.bg2.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer_outlined, color: DemProColors.accent, size: 13),
                  const SizedBox(width: 5),
                  Text(_waitLabel,
                      style: const TextStyle(color: DemProColors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),

          // ── Panel bas ─────────────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  20, 24, 20, MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                color: DemProColors.bg2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
              ),
              child: _timedOut
                  ? _buildTimedOut()
                  : _buildWaiting(pickup, delivery, price),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaiting(String pickup, String delivery, num price) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // ── Radar ──────────────────────────────────────────────────────────
      SizedBox(
        width: 80, height: 80,
        child: AnimatedBuilder(
          animation: _radarAnim,
          builder: (_, __) => CustomPaint(
            painter: _RadarPainter(_radarAnim.value),
          ),
        ),
      ),
      const SizedBox(height: 16),

      const Text(
        'Recherche d\'un livreur…',
        style: TextStyle(
          color: Color(0xFFE8F4F8),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Nous cherchons le livreur le plus proche',
        style: TextStyle(color: Color(0xFF6B8BAA), fontSize: 13),
      ),
      const SizedBox(height: 20),

      // ── Adresses ───────────────────────────────────────────────────────
      _RouteRow(pickup: pickup, delivery: delivery),
      const SizedBox(height: 16),

      // ── Prix ───────────────────────────────────────────────────────────
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.payments_outlined, color: Color(0xFF6B8BAA), size: 14),
        const SizedBox(width: 6),
        Text(
          '${price.toInt()} FCFA',
          style: const TextStyle(
              color: Color(0xFFE8F4F8), fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ]),
      const SizedBox(height: 20),

      // ── Bouton annuler ─────────────────────────────────────────────────
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: _cancelling ? null : _cancel,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFF5C5C),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x44FF5C5C)),
            ),
          ),
          child: _cancelling
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFF5C5C)))
              : const Text('Annuler la commande',
                  style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }

  Widget _buildTimedOut() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.hourglass_empty_rounded, color: Color(0xFFFFB830), size: 48),
      const SizedBox(height: 12),
      const Text(
        'Aucun livreur disponible',
        style: TextStyle(
            color: Color(0xFFE8F4F8), fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      const Text(
        'La demande reste active. Continuer d\'attendre ou annuler.',
        style: TextStyle(color: Color(0xFF6B8BAA), fontSize: 13),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF5C5C),
              side: const BorderSide(color: Color(0x44FF5C5C)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () => setState(() { _timedOut = false; _waitSec = 0; }),
            style: ElevatedButton.styleFrom(
              backgroundColor: DemProColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continuer', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    ]);
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

class _RouteRow extends StatelessWidget {
  final String pickup;
  final String delivery;
  const _RouteRow({required this.pickup, required this.delivery});

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

// ── Radar painter ─────────────────────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR   = size.width / 2;

    for (int i = 3; i >= 1; i--) {
      final r     = maxR * (progress + i / 3).clamp(0.0, 1.0);
      final alpha = (1.0 - progress).clamp(0.0, 1.0) * (i / 3) * 0.4;
      canvas.drawCircle(
        center, r,
        Paint()
          ..color = const Color(0xFF00AECB).withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    canvas.drawCircle(
      center, 14,
      Paint()..color = const Color(0xFF00AECB).withValues(alpha: 0.2),
    );
    canvas.drawCircle(
      center, 14,
      Paint()
        ..color = DemProColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(center, 5, Paint()..color = DemProColors.accent);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
