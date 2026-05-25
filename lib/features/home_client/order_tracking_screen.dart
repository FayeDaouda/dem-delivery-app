import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/support_report_sheet.dart';
import '../../core/theme/map_theme_provider.dart';
import '../deliveries/providers/orders_provider.dart';
import '../home_driver/navigation/map_theme.dart';
import 'providers/order_state.dart';
import 'providers/order_state_provider.dart';

const _kSupportPhone    = '+221784448524';
const _kSupportWhatsApp = '221784448524';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String driverId;
  final int? etaPickupMin;
  final Map<String, dynamic>? initialOrder; // données pré-chargées → zéro latence

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.driverId,
    this.etaPickupMin,
    this.initialOrder,
  });

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen>
    with WidgetsBindingObserver {
  // ── État vue (map, rendu, UX) — reste local ──────────────────────────────
  bool _rated = false;

  GoogleMapController? _mapController;
  String? _mapStyle;
  List<LatLng> _routePoints = [];
  List<LatLng> _displayRoute = [];
  int _lastTrimIdx = 0;
  bool _isRerouting = false;

  BitmapDescriptor? _driverMarkerIcon;
  double _driverHeading = 0;
  LatLng? _prevDriverLocation;

  Timer? _routeRefreshTimer;

  bool _autoFollow = true;
  bool _nearbyAlerted = false;
  bool _arrivedOverlayVisible = false;

  // ── État métier → clientOrderStateProvider ────────────────────────────────
  // _order, _status, _loading, _driverLocation, _liveEtaMin,
  // _driverOffline, _driverUnreachable, _searchingNewDriver,
  // _otherActiveOrders — tous lus via ref.watch(clientOrderStateProvider)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMapStyle();
    _connectSocket();
    _buildDriverMarkerIcon().then((icon) {
      if (mounted) setState(() => _driverMarkerIcon = icon);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routeRefreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// Au retour au premier plan : reconnecte la socket si perdue
  /// et redemande la position du driver immédiatement.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!SocketService.instance.isConnected) {
      AuthStorage.getToken().then((token) {
        if (token == null || !mounted) return;
        SocketService.instance.connect(token);
        // Redemande la dernière position connue du driver après reconnexion
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) SocketService.instance.requestDriverLocation(widget.orderId);
        });
      });
    } else {
      // Socket déjà connectée : juste demander la position du driver
      SocketService.instance.requestDriverLocation(widget.orderId);
    }
    // Recalcul de la route si nécessaire
    final phase = _s.phase;
    if (phase == 'ACCEPTED' || phase == 'PICKED_UP') {
      _fetchRoute();
    }
  }

  Future<void> _loadMapStyle() async {
    final bool isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  // ── Icône driver 3D : flèche de navigation orientable ────────────────────
  static Future<BitmapDescriptor> _buildDriverMarkerIcon() async {
    const double size = 120;
    const double cx = size / 2;
    const double cy = size / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Halo externe pulsé
    canvas.drawCircle(const Offset(cx, cy), 56,
        Paint()..color = const Color(0x18FF6B00));
    canvas.drawCircle(const Offset(cx, cy), 42,
        Paint()..color = const Color(0x30FF6B00));

    // Ombre portée de la flèche
    final shadowPaint = Paint()
      ..color = const Color(0x70C85000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 7);
    final shadowPath = Path()
      ..moveTo(cx, cy - 26 + 5)
      ..lineTo(cx + 16, cy + 14 + 5)
      ..lineTo(cx, cy + 7 + 5)
      ..lineTo(cx - 16, cy + 14 + 5)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // Cercle de base blanc (effet 3D)
    canvas.drawCircle(const Offset(cx, cy + 4), 22,
        Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(cx, cy + 4), 20,
        Paint()..color = const Color(0xFFFF6B00));

    // Flèche pointant vers le haut (nord = 0°)
    // La rotation est appliquée via Marker.rotation au niveau de la carte
    final arrowPath = Path()
      ..moveTo(cx, cy - 26)        // pointe
      ..lineTo(cx + 16, cy + 13)   // coin droit
      ..lineTo(cx, cy + 7)         // encoche centrale
      ..lineTo(cx - 16, cy + 13)   // coin gauche
      ..close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(cx, cy - 26),
          const Offset(cx, cy + 13),
          [const Color(0xFFFFB347), const Color(0xFFE65100)],
        ),
    );
    // Contour blanc brillant
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        width: 54, height: 54);
  }

  // ── Cap du livreur (bearing entre deux positions consécutives) ────────────
  static double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude  * math.pi / 180;
    final lat2 = to.latitude    * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
              math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  // ── Rétrécissement de la route ────────────────────────────────────────────
  static int _closestPointIdx(List<LatLng> route, LatLng pos, int startIdx) {
    final end = (startIdx + 60).clamp(0, route.length);
    int idx = startIdx;
    double minDist = double.infinity;
    for (int i = startIdx; i < end; i++) {
      final dLat = route[i].latitude - pos.latitude;
      final dLng = route[i].longitude - pos.longitude;
      final dist = dLat * dLat + dLng * dLng;
      if (dist < minDist) { minDist = dist; idx = i; }
    }
    return idx;
  }

  void _updateDisplayRoute(LatLng driverLoc) {
    if (_routePoints.isEmpty) {
      return;
    }
    final idx = _closestPointIdx(_routePoints, driverLoc, _lastTrimIdx);
    if (idx == _lastTrimIdx && _displayRoute.isNotEmpty) return;
    _lastTrimIdx = idx;
    if (mounted) setState(() => _displayRoute = _routePoints.sublist(idx));
  }

  Future<void> _fetchRoute() async {
    if (_isRerouting) return;
    final s = ref.read(clientOrderStateProvider(widget.orderId));
    final order = s.orderData;
    if (order == null) return;
    _isRerouting = true;

    final pickupLat = (order['pickupLatitude']   as num?)?.toDouble();
    final pickupLng = (order['pickupLongitude']  as num?)?.toDouble();
    final delivLat  = (order['deliveryLatitude'] as num?)?.toDouble();
    final delivLng  = (order['deliveryLongitude'] as num?)?.toDouble();
    if (pickupLat == null || pickupLng == null || delivLat == null || delivLng == null) {
      _isRerouting = false;
      return;
    }

    final driverLoc = s.driverLocation;
    final double oLat, oLng, dLat, dLng;
    if (s.phase == 'ACCEPTED' && driverLoc != null) {
      oLat = driverLoc.latitude;  oLng = driverLoc.longitude;
      dLat = pickupLat;           dLng = pickupLng;
    } else if (s.phase == 'PICKED_UP') {
      oLat = driverLoc?.latitude  ?? pickupLat;
      oLng = driverLoc?.longitude ?? pickupLng;
      dLat = delivLat;            dLng = delivLng;
    } else {
      oLat = pickupLat; oLng = pickupLng;
      dLat = delivLat;  dLng = delivLng;
    }

    try {
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
      final res = await dio.get(
        'https://router.project-osrm.org/route/v1/driving/$oLng,$oLat;$dLng,$dLat?overview=full&geometries=geojson',
      );
      if (res.statusCode == 200 &&
          (res.data['routes'] as List?)?.isNotEmpty == true) {
        final coords = res.data['routes'][0]['geometry']['coordinates'] as List;
        final points = coords
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (mounted) {
          setState(() {
            _routePoints = points;
            _displayRoute = points;
            _lastTrimIdx = 0;
            _isRerouting = false;
          });
          if (driverLoc != null) _updateDisplayRoute(driverLoc);
        } else {
          _isRerouting = false;
        }
      } else {
        _isRerouting = false;
      }
    } catch (_) {
      _isRerouting = false;
    }
  }

  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;
    SocketService.instance.connect(token);
    // Demande la dernière position connue (utile si le driver est stationnaire)
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) SocketService.instance.requestDriverLocation(widget.orderId);
    });
    // Tous les listeners socket sont maintenant dans clientOrderStateProvider
  }

  void _showRatingDialog() {
    if (!mounted || _rated) return;
    int selectedRating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.gradientSplash,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ],
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                      color: Color(0xFF00C853), shape: BoxShape.circle),
                  child:
                      const Icon(Icons.check, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                const Text('Livraison effectuée !',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                    '${(_s.orderData?['price'] as num?)?.toInt() ?? 0} FCFA',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 20),
                const Text('Notez votre livreur',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return GestureDetector(
                      onTap: () =>
                          setDialogState(() => selectedRating = star),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          star <= selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: star <= selectedRating
                              ? const Color(0xFFFFD700)
                              : Colors.white38,
                          size: 36,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: commentController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Un commentaire ? (optionnel)',
                    hintStyle: const TextStyle(
                        color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      setState(() => _rated = true);
                      Navigator.of(ctx).pop();
                      final comment =
                          commentController.text.trim().isEmpty
                              ? null
                              : commentController.text.trim();
                      try {
                        await ref
                            .read(ordersRepositoryProvider)
                            .rateDriver(
                              orderId: widget.orderId,
                              driverId: widget.driverId,
                              score: selectedRating,
                              comment: comment,
                            );
                      } catch (_) {}
                      if (mounted) context.go('/client/home');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Envoyer & Retour',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() => _rated = true);
                    Navigator.of(ctx).pop();
                    if (mounted) context.go('/client/home');
                  },
                  child: const Text('Passer',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _callDriver() async {
    final phone = (_s.orderData?['driver'] as Map<String, dynamic>?)?['phone']
        as String?;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  ClientOrderState get _s => ref.read(clientOrderStateProvider(widget.orderId));
  bool get _isDelivery => (_s.orderData?['orderType'] as String?) == 'DELIVERY';

  String? get _etaText {
    final min = _s.etaMin ?? widget.etaPickupMin;
    if (min == null) return null;
    if (min <= 1) return 'Le livreur approche !';
    if (min <= 3) return 'Arrive dans ~$min min';
    return '~$min min';
  }

  String get _statusLabel => switch (_s.phase) {
        'ACCEPTED' => _isDelivery
            ? 'Livreur en route pour récupérer votre colis'
            : 'Chauffeur en route vers vous',
        'PICKED_UP' => _isDelivery
            ? 'Colis pris en charge — en route'
            : 'En route vers la destination',
        'DELIVERED' => _isDelivery ? 'Colis livré ✓' : 'Arrivée effectuée ✓',
        _ => 'Commande en cours',
      };

  IconData get _statusIcon => switch (_s.phase) {
        'ACCEPTED' => _isDelivery ? Icons.inventory_2_outlined : Icons.directions_bike,
        'PICKED_UP' => Icons.two_wheeler,
        'DELIVERED' => Icons.check_circle,
        _ => Icons.access_time,
      };

  Color get _statusColor => switch (_s.phase) {
        'ACCEPTED' => Colors.orange,
        'PICKED_UP' => AppColors.primary,
        'DELIVERED' => const Color(0xFF00C853),
        _ => AppColors.textSecondary,
      };

  void _fitBounds(double pickupLat, double pickupLng, double deliveryLat,
      double deliveryLng) {
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(
          pickupLat < deliveryLat ? pickupLat : deliveryLat,
          pickupLng < deliveryLng ? pickupLng : deliveryLng,
        ),
        northeast: LatLng(
          pickupLat > deliveryLat ? pickupLat : deliveryLat,
          pickupLng > deliveryLng ? pickupLng : deliveryLng,
        ),
      ),
      80,
    ));
  }

  Widget _buildArrivalBanner() {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00C853), Color(0xFF00E676)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Le livreur est arrivé !',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            GestureDetector(
              onTap: _callDriver,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Appeler', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _arrivedOverlayVisible = false),
              child: const Icon(Icons.close, color: Colors.white70, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverStatusBadge() {
    final driverStatus = _s.driverStatus;
    final since = _s.driverOfflineSince;
    // Cas critique : livreur introuvable depuis 10 min, colis en transit, admin alerté
    if (driverStatus == DriverStatus.unreachable) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFF3D00)),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Livreur introuvable · Notre équipe a été alertée',
                    style: TextStyle(color: Color(0xFFFF3D00), fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showReportSheet,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3D00).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFF3D00).withValues(alpha: 0.45)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.support_agent, color: Color(0xFFFF3D00), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Contacter le support',
                          style: TextStyle(color: Color(0xFFFF3D00), fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.chevron_right, color: const Color(0xFFFF3D00).withValues(alpha: 0.7), size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Re-dispatch automatique : l'ancien livreur a disparu avant la récupération
    if (driverStatus == DriverStatus.searching) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFFFB300)),
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Recherche d\'un nouveau livreur en cours…',
                style: TextStyle(color: Color(0xFFFFB300), fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    if (driverStatus == DriverStatus.offline) {
      final diff = since != null ? DateTime.now().difference(since) : null;
      final mins  = diff?.inMinutes ?? 0;
      final timeLabel = (diff == null || mins < 1) ? 'À l\'instant' : 'Il y a $mins min';
      // ACCEPTED + offline : re-dispatch automatique après 5 min
      final isAccepted = _s.phase == 'ACCEPTED';
      final minsUntilRedispatch = isAccepted ? (5 - mins).clamp(0, 5) : null;

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Statut hors-ligne
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 12, color: Color(0xFFFFB300)),
                const SizedBox(width: 6),
                Text(
                  'Le livreur est hors ligne · $timeLabel',
                  style: const TextStyle(color: Color(0xFFFFB300), fontSize: 11),
                ),
              ],
            ),
            // Info re-dispatch automatique (uniquement phase ACCEPTED)
            if (minsUntilRedispatch != null) ...[
              const SizedBox(height: 4),
              Text(
                minsUntilRedispatch > 0
                    ? 'Un nouveau livreur sera cherché automatiquement dans ~$minsUntilRedispatch min'
                    : 'Recherche d\'un nouveau livreur en cours…',
                style: TextStyle(color: const Color(0xFFFFB300).withValues(alpha: 0.70), fontSize: 10),
              ),
            ],
          ],
        ),
      );
    }
    if (_s.driverLocation == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38),
            ),
            SizedBox(width: 8),
            Text('Localisation du livreur en cours…',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _showReportSheet() {
    final orderId = widget.orderId;
    final since   = _s.driverOfflineSince;
    final mins    = since != null ? DateTime.now().difference(since).inMinutes : 0;
    final msg     = Uri.encodeComponent(
      'Bonjour, j\'ai un problème avec ma livraison #$orderId. '
      'Le livreur est hors ligne depuis $mins min.',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          gradient: AppColors.gradientSplash,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36, height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Icône warning
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB300), size: 30),
                ),
                const SizedBox(height: 14),

                const Text('Signaler un problème',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Le livreur est hors ligne depuis $mins min.\nNotre équipe est disponible pour vous aider.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 28),

                // Appeler le support
                _SupportAction(
                  icon: Icons.phone_rounded,
                  color: const Color(0xFF00C853),
                  label: 'Appeler le support',
                  subtitle: _kSupportPhone,
                  onTap: () async {
                    Navigator.pop(context);
                    final uri = Uri.parse('tel:$_kSupportPhone');
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                ),
                const SizedBox(height: 12),

                // WhatsApp
                _SupportAction(
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF25D366),
                  label: 'WhatsApp support',
                  subtitle: 'Message direct avec le texte pré-rempli',
                  onTap: () async {
                    Navigator.pop(context);
                    final uri = Uri.parse('https://wa.me/$_kSupportWhatsApp?text=$msg');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                const SizedBox(height: 20),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Fermer', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _updateSmartCamera(LatLng driverLoc) {
    if (_mapController == null) return;
    final s = _s;
    final order = s.orderData;
    LatLng? destination;
    if (s.phase == 'ACCEPTED') {
      final pLat = (order?['pickupLatitude']  as num?)?.toDouble();
      final pLng = (order?['pickupLongitude'] as num?)?.toDouble();
      if (pLat != null && pLng != null) destination = LatLng(pLat, pLng);
    } else if (s.phase == 'PICKED_UP' || s.phase == 'IN_TRANSIT') {
      final dLat = (order?['deliveryLatitude']  as num?)?.toDouble();
      final dLng = (order?['deliveryLongitude'] as num?)?.toDouble();
      if (dLat != null && dLng != null) destination = LatLng(dLat, dLng);
    }
    if (destination != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            driverLoc.latitude  < destination.latitude  ? driverLoc.latitude  : destination.latitude,
            driverLoc.longitude < destination.longitude ? driverLoc.longitude : destination.longitude,
          ),
          northeast: LatLng(
            driverLoc.latitude  > destination.latitude  ? driverLoc.latitude  : destination.latitude,
            driverLoc.longitude > destination.longitude ? driverLoc.longitude : destination.longitude,
          ),
        ),
        90,
      ));
    } else {
      _mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: driverLoc, zoom: 17, tilt: 55),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Source unique de vérité pour l'état métier ──────────────────────────
    final orderState = ref.watch(clientOrderStateProvider(widget.orderId));

    // ── Side effects (carte, haptic, dialog) réagissant aux changements ─────
    ref.listen<ClientOrderState>(clientOrderStateProvider(widget.orderId),
        (prev, next) {
      final newLoc = next.driverLocation;

      // Changement de position driver
      if (newLoc != null && newLoc != prev?.driverLocation) {
        // Bearing
        if (_prevDriverLocation != null) {
          final bearing = _calculateBearing(_prevDriverLocation!, newLoc);
          setState(() => _driverHeading = bearing);
        }
        _prevDriverLocation = newLoc;

        // Rétrécissement de la route
        _updateDisplayRoute(newLoc);

        // Recalcul si déviation > 70 m
        if (_routePoints.isNotEmpty &&
            (next.phase == 'ACCEPTED' || next.phase == 'PICKED_UP')) {
          double minDist = double.infinity;
          final end = (_lastTrimIdx + 60).clamp(0, _routePoints.length);
          for (int i = _lastTrimIdx; i < end; i++) {
            final d = Geolocator.distanceBetween(newLoc.latitude, newLoc.longitude,
                _routePoints[i].latitude, _routePoints[i].longitude);
            if (d < minDist) minDist = d;
          }
          if (minDist > 70) _fetchRoute();
        }

        // Caméra intelligente
        if (_autoFollow) _updateSmartCamera(newLoc);
      }

      // Haptic : proximité driver ≤ 1 min
      if (next.etaMin != prev?.etaMin) {
        if (next.etaMin != null && next.etaMin! <= 1 && !_nearbyAlerted) {
          _nearbyAlerted = true;
          HapticFeedback.mediumImpact();
        }
        if (next.etaMin != null && next.etaMin == 0 && !_arrivedOverlayVisible) {
          setState(() => _arrivedOverlayVisible = true);
          HapticFeedback.heavyImpact();
        }
      }

      // Changement de phase
      if (next.phase != prev?.phase) {
        _fetchRoute();
        if (next.phase == 'DELIVERED' && !_rated) {
          Future.delayed(const Duration(milliseconds: 300), _showRatingDialog);
        }
        // Annulation admin : retour automatique à l'accueil après 5s
        // GoRouter capturé avant le gap async pour éviter l'accès au BuildContext après await
        if (next.phase == 'CANCELLED') {
          final router = GoRouter.of(context);
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) router.go('/client/home');
          });
        }
      }

      // Re-dispatch → efface la route (le nouveau driver n'est pas encore localisé)
      if (next.driverStatus == DriverStatus.searching &&
          prev?.driverStatus != DriverStatus.searching) {
        setState(() {
          _routePoints = [];
          _displayRoute = [];
          _lastTrimIdx = 0;
        });
      }
    });

    // ── Extraction des données pour le build ─────────────────────────────────
    final order = orderState.orderData;
    final pickupLat = (order?['pickupLatitude'] as num?)?.toDouble();
    final pickupLng = (order?['pickupLongitude'] as num?)?.toDouble();
    final deliveryLat = (order?['deliveryLatitude'] as num?)?.toDouble();
    final deliveryLng = (order?['deliveryLongitude'] as num?)?.toDouble();
    final initialTarget = pickupLat != null && pickupLng != null
        ? LatLng(pickupLat, pickupLng)
        : const LatLng(14.6937, -17.4441);

    final driverMap = order?['driver'] as Map<String, dynamic>?;
    final driverName = driverMap?['name'] as String? ?? 'Livreur';
    final hasDriverPhone = (driverMap?['phone'] as String?)?.isNotEmpty == true;
    final driverRating = (driverMap?['averageRating'] as num?)?.toDouble();
    final pickupAddress = order?['pickupAddress'] as String? ?? '';
    final deliveryAddress = order?['deliveryAddress'] as String? ?? '';
    final price = (order?['price'] as num?)?.toInt() ?? 0;

    // Fallback : position DB si socket pas encore reçu
    final socketLoc = orderState.driverLocation;
    final driverLat = socketLoc?.latitude
        ?? (driverMap?['latitude'] as num?)?.toDouble()
        ?? (order?['driverLatitude'] as num?)?.toDouble();
    final driverLng = socketLoc?.longitude
        ?? (driverMap?['longitude'] as num?)?.toDouble()
        ?? (order?['driverLongitude'] as num?)?.toDouble();
    final effectiveDriverLoc = (driverLat != null && driverLng != null)
        ? LatLng(driverLat, driverLng)
        : null;

    final markers = <Marker>{
      if (pickupLat != null && pickupLng != null && orderState.phase == 'ACCEPTED')
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(pickupLat, pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Point de collecte'),
        ),
      // Destination : toujours visible
      if (deliveryLat != null && deliveryLng != null)
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(deliveryLat, deliveryLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      // Livreur : flèche 3D orientée dans sa direction de déplacement
      if (effectiveDriverLoc != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: effectiveDriverLoc,
          icon: _driverMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          rotation: _driverHeading,
          anchor: const Offset(0.5, 0.5),
          flat: true,
        ),
    };

    final polylines = _displayRoute.isNotEmpty
        ? {
            Polyline(
              polylineId: const PolylineId('route'),
              points: _displayRoute,
              color: AppColors.primary,
              width: 4,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          }
        : <Polyline>{};

    if (orderState.isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0CB8DE), Color(0xFF04317C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
              child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    // ── Commande annulée par l'admin ─────────────────────────────────────────
    if (orderState.phase == 'CANCELLED') {
      final notifier = ref.read(clientOrderStateProvider(widget.orderId).notifier);
      final reason   = notifier.cancelReason ?? 'Votre commande a été annulée par l\'administration DEM.';
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0CB8DE), Color(0xFF04317C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.40), width: 2),
                    ),
                    child: const Icon(Icons.cancel_outlined, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Commande annulée',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    reason,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.80), fontSize: 14, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.go('/client/home'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0077B6),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('Retour à l\'accueil',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: initialTarget, zoom: 17, tilt: 55),
              style: _mapStyle,
              markers: markers,
              polylines: polylines,
              zoomControlsEnabled: false,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
              onCameraMove: (_) {
                if (_autoFollow) setState(() => _autoFollow = false);
              },
              onMapCreated: (c) {
                _mapController = c;
                if (pickupLat != null && deliveryLat != null) {
                  Future.delayed(const Duration(milliseconds: 400), () {
                    _fitBounds(pickupLat, pickupLng!, deliveryLat,
                        deliveryLng!);
                  });
                }
              },
            ),
          ),

          // Bouton retour + bandeau multi-commandes
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // Bouton retour
                    GestureDetector(
                      onTap: () {
                        ref.read(trackingMinimizedProvider.notifier).state = true;
                        context.canPop() ? context.pop() : context.go('/client/home');
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.arrow_back, size: 20, color: Colors.black87),
                      ),
                    ),
                    // Chips des autres commandes actives
                    if (orderState.otherActiveOrders.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: orderState.otherActiveOrders.map((o) {
                              final idx = orderState.otherActiveOrders.indexOf(o) + 2;
                              final dId = (o['driver'] as Map?)?['id'] as String?
                                  ?? o['driverId'] as String?;
                              final oId = o['id'] as String?;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () {
                                    if (oId == null || dId == null) return;
                                    context.pushReplacement('/orders/tracking', extra: {
                                      'orderId': oId,
                                      'driverId': dId,
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0CB8DE),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6)],
                                    ),
                                    child: Text(
                                      'Commande $idx',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Bouton "Recentrer" quand l'user a bougé la carte manuellement
          if (!_autoFollow)
            Positioned(
              bottom: 220,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  setState(() => _autoFollow = true);
                  if (_s.driverLocation != null) _updateSmartCamera(_s.driverLocation!);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.my_location, size: 16, color: Color(0xFF0CB8DE)),
                      SizedBox(width: 6),
                      Text('Recentrer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0CB8DE))),
                    ],
                  ),
                ),
              ),
            ),

          // Overlay "arrivée imminente" — slide in depuis le haut
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: _arrivedOverlayVisible ? Offset.zero : const Offset(0, -2),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _arrivedOverlayVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60, left: 16, right: 16, bottom: 8),
                    child: _buildArrivalBanner(),
                  ),
                ),
              ),
            ),
          ),

          // Bottom panel
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.gradientSplash,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, -4))
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 3,
                          decoration: BoxDecoration(
                              color:
                                  Colors.white.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Statut : DELIVERED → carte animée, sinon chip + timeline
                      if (orderState.phase == 'DELIVERED')
                        TweenAnimationBuilder<double>(
                          key: const ValueKey('delivered_card'),
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.elasticOut,
                          builder: (ctx, v, child) => Transform.scale(
                            scale: v.clamp(0.0, 1.2),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00C853).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFF00C853).withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF00C853), size: 46),
                                  SizedBox(height: 6),
                                  Text('Livraison effectuée !',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                ],
                              ),
                            ),
                          ),
                        )
                      else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_statusIcon, color: _statusColor, size: 16),
                              const SizedBox(width: 8),
                              Flexible(child: Text(_statusLabel,
                                  style: TextStyle(
                                      color: _statusColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Indicateur état connexion driver
                      if (orderState.phase != 'DELIVERED')
                        _buildDriverStatusBadge(),

                      // Driver info row
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                                color: Colors.white
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.person,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(driverName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    if (driverRating != null) ...[
                                      const Icon(Icons.star_rounded,
                                          color: Color(0xFFFFD700), size: 14),
                                      const SizedBox(width: 3),
                                      Text(driverRating.toStringAsFixed(1),
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                      if (_etaText != null)
                                        const Text(' · ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                    ],
                                    if (_etaText != null)
                                      Text(_etaText!,
                                          style: TextStyle(
                                              color: (orderState.etaMin != null && orderState.etaMin! <= 3)
                                                  ? const Color(0xFF69F0AE)
                                                  : Colors.white70,
                                              fontSize: 12,
                                              fontWeight: (orderState.etaMin != null && orderState.etaMin! <= 3)
                                                  ? FontWeight.w700 : FontWeight.normal)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (hasDriverPhone)
                            GestureDetector(
                              onTap: _callDriver,
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                    color: Color(0xFF00C853),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.phone,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Route addresses
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _RouteRow(
                                icon: Icons.circle,
                                color: const Color(0xFF69F0AE),
                                text: pickupAddress),
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Container(
                                  width: 2,
                                  height: 12,
                                  color: Colors.white
                                      .withValues(alpha: 0.25)),
                            ),
                            _RouteRow(
                                icon: Icons.location_on,
                                color: AppColors.error,
                                text: deliveryAddress),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Price
                      Row(children: [
                        const Icon(Icons.payments_outlined,
                            size: 16, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text('$price FCFA',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        // Bouton signaler un problème (visible pendant la course)
                        if (!['DELIVERED', 'CANCELLED'].contains(orderState.phase))
                          GestureDetector(
                            onTap: () => SupportReportSheet.show(
                              context,
                              orderId: widget.orderId,
                              role: 'CLIENT',
                              repo: ref.read(ordersRepositoryProvider),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.flag_outlined,
                                    size: 13, color: Colors.white.withValues(alpha: 0.70)),
                                const SizedBox(width: 5),
                                Text('Signaler',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.80),
                                      fontSize: 12, fontWeight: FontWeight.w600,
                                    )),
                              ]),
                            ),
                          ),
                      ]),

                      if (orderState.phase == 'DELIVERED' && !_rated) ...[
                        const SizedBox(height: 14),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00C853).withValues(alpha: 0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _showRatingDialog,
                              icon: const Icon(Icons.star_rounded, size: 20),
                              label: const Text('Noter le livreur',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C853),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RouteRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text,
            style:
                const TextStyle(color: Colors.white, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

class _SupportAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _SupportAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color.withValues(alpha: 0.6), size: 14),
          ],
        ),
      ),
    );
  }
}
