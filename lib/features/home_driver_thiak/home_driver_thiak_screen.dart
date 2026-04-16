import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../features/deliveries/data/orders_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../features/deliveries/providers/orders_provider.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../home_driver/navigation/directions_service.dart';
import '../home_driver/navigation/map_theme.dart';
import '../home_driver/navigation/navigation_service.dart';

const _dakar = LatLng(14.6937, -17.4441);

class HomeDriverThiakScreen extends ConsumerStatefulWidget {
  const HomeDriverThiakScreen({super.key});

  @override
  ConsumerState<HomeDriverThiakScreen> createState() =>
      _HomeDriverThiakScreenState();
}

class _HomeDriverThiakScreenState
    extends ConsumerState<HomeDriverThiakScreen> {
  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _driverIcon;

  // ── GPS ──────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _driverPosition;
  bool _autoFollow = true;

  // ── Route vers pickup (pendant notification) ──────────────────────────────
  List<LatLng> _pendingRoutePoints = [];

  // ── Heatmap zones chaudes ─────────────────────────────────────────────────
  Set<Circle> _heatmapCircles = {};
  Timer? _heatmapTimer;

  // ── WebSocket ─────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _newOrderSub;
  StreamSubscription<String>?              _expiredOrderSub;
  StreamSubscription<void>?                _reconnectSub;

  // ── Polling fallback (toutes les 30s si socket déconnecté) ───────────────
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _buildDriverIcon().then((icon) {
      if (mounted) setState(() => _driverIcon = icon);
    });
    _startGPS();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).fetchProfile(goOnlineIfOffline: true);
      _connectSocket();
      _startPolling();
      _loadHeatmap();
      _heatmapTimer = Timer.periodic(const Duration(minutes: 5), (_) => _loadHeatmap());
    });
  }

  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;

    SocketService.instance.connect(token);

    _newOrderSub = SocketService.instance.onNewOrder.listen((order) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).injectSocketOrder(order);
    });

    _expiredOrderSub = SocketService.instance.onOrderExpired.listen((orderId) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).removeOrder(orderId);
    });

    _reconnectSub = SocketService.instance.onReconnect.listen((_) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).refresh();
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Polling réduit à 30s — simple filet de sécurité si socket déconnecté
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final isAvailable = ref.read(profileProvider).isAvailable;
      final hasOrder    = (ref.read(availableOrdersProvider).value ?? []).isNotEmpty;
      if (isAvailable && !hasOrder && !SocketService.instance.isConnected) {
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });
  }

  Future<void> _loadHeatmap() async {
    final points = await OrdersRepository().getHeatmap();
    if (!mounted || points.isEmpty) return;

    final maxCount = points.map((p) => (p['count'] as num).toInt()).reduce((a, b) => a > b ? a : b);

    setState(() {
      _heatmapCircles = points.asMap().entries.map((entry) {
        final i     = entry.key;
        final p     = entry.value;
        final count = (p['count'] as num).toInt();
        final ratio = maxCount > 0 ? count / maxCount : 0.0;

        // Dégradé jaune → orange → rouge selon intensité
        final color = ratio < 0.4
            ? const Color(0xFFFFEB3B)   // jaune
            : ratio < 0.7
                ? const Color(0xFFFF9800) // orange
                : const Color(0xFFF44336); // rouge

        return Circle(
          circleId: CircleId('heatmap_$i'),
          center: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
          radius: 800,
          fillColor: color.withValues(alpha: 0.25 + ratio * 0.35),
          strokeWidth: 0,
        );
      }).toSet();
    });
  }

  static Future<BitmapDescriptor> _buildDriverIcon() async {
    const double size = 128;
    const double cx = size / 2;
    const double cy = size / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // ── Halo pulsant externe ──
    canvas.drawCircle(
      const Offset(cx, cy),
      48,
      Paint()..color = const Color(0x2533BCD4),
    );
    canvas.drawCircle(
      const Offset(cx, cy),
      36,
      Paint()..color = const Color(0x4033BCD4),
    );

    // ── Ombre portée (décalée vers le bas) ──
    final shadowPaint = Paint()
      ..color = const Color(0x6000B4C8)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    final shadowPath = Path()
      ..moveTo(cx, cy - 22 + 4)
      ..lineTo(cx + 16, cy + 14 + 4)
      ..lineTo(cx, cy + 8 + 4)
      ..lineTo(cx - 16, cy + 14 + 4)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // ── Cercle de base blanc (donne l'effet 3D) ──
    canvas.drawCircle(
      const Offset(cx, cy + 4),
      20,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      const Offset(cx, cy + 4),
      18,
      Paint()..color = const Color(0xFF1AB8CC),
    );

    // ── Flèche de navigation 3D ──
    // Face avant (claire) — pointe vers le haut
    final arrowFront = Path()
      ..moveTo(cx, cy - 22)        // pointe
      ..lineTo(cx + 15, cy + 12)   // bas-droit
      ..lineTo(cx, cy + 6)         // encoche bas-centre
      ..lineTo(cx - 15, cy + 12)   // bas-gauche
      ..close();

    // Gradient pour effet 3D
    final gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(cx, cy - 22),
        const Offset(cx, cy + 12),
        [const Color(0xFF5EEEFF), const Color(0xFF00A8C0)],
      );
    canvas.drawPath(arrowFront, gradientPaint);

    // Bordure blanche fine
    canvas.drawPath(
      arrowFront,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: 56,
      height: 56,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _heatmapTimer?.cancel();
    _newOrderSub?.cancel();
    _expiredOrderSub?.cancel();
    _reconnectSub?.cancel();
    _locationSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString(MapTheme.styleAsset);
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _startGPS() async {
    final initial = await NavigationService.requestAndGetPosition();
    if (initial != null && mounted) {
      setState(() => _driverPosition = initial);
      _centerOn(initial);
    }
    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _driverPosition = position);
    if (_autoFollow) _centerOn(position);
  }

  void _centerOn(Position position) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 15.5,
          bearing: 0,
          tilt: 0,
        ),
      ),
    );
  }

  void _recenter() {
    if (_driverPosition == null) return;
    setState(() => _autoFollow = true);
    _centerOn(_driverPosition!);
  }

  Set<Marker> get _driverMarkers {
    if (_driverPosition == null) return {};
    return {
      Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
        icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        flat: true,
        rotation: _driverPosition!.heading,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
      ),
    };
  }

  // ── Countdown ─────────────────────────────────────────────────────────────
  int _countdown = 30;
  Timer? _countdownTimer;

  Color get _countdownColor {
    if (_countdown > 20) return AppColors.primary;
    if (_countdown > 10) return Colors.amber;
    return Colors.red;
  }

  void _startCountdown({bool isDevOrder = false, String? orderId}) {
    _countdownTimer?.cancel();
    setState(() => _countdown = 30);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _clearPendingRoute();
        if (isDevOrder) {
          ref.read(availableOrdersProvider.notifier).clearDevOrder();
        } else if (orderId != null) {
          // Signaler le refus au backend pour dispatch immédiat au suivant
          ref.read(ordersRepositoryProvider).declineOrder(orderId).catchError((_) {});
          ref.read(availableOrdersProvider.notifier).refresh();
        }
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    if (mounted) setState(() => _countdown = 30);
  }

  // ── Route vers pickup ─────────────────────────────────────────────────────
  Future<void> _loadPendingRoute(Map<String, dynamic> order) async {
    if (_driverPosition == null) return;
    final pickup = LatLng(
      (order['pickupLatitude'] as num).toDouble(),
      (order['pickupLongitude'] as num).toDouble(),
    );
    final origin = LatLng(_driverPosition!.latitude, _driverPosition!.longitude);
    final result = await DirectionsService.getRoute(
      origin: origin,
      destination: pickup,
      apiKey: AppConfig.mapsApiKey,
    );
    if (mounted) setState(() => _pendingRoutePoints = result.points);
  }

  void _clearPendingRoute() {
    if (mounted) setState(() => _pendingRoutePoints = []);
  }

  Set<Polyline> get _pendingPolylines {
    if (_pendingRoutePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('pending'),
        points: _pendingRoutePoints,
        color: AppColors.primary,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  Future<void> _toggleAvailability(bool val) async {
    try {
      await ref.read(profileProvider.notifier).toggleAvailability();
      final isAvailable = ref.read(profileProvider).isAvailable;
      if (isAvailable) ref.read(availableOrdersProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    _cancelCountdown();
    _clearPendingRoute();
    // Mode dev : pas d'appel API
    if (orderId.startsWith('dev-')) {
      final orders = ref.read(availableOrdersProvider).value ?? [];
      final order = orders.firstWhere((o) => o['id'] == orderId);
      ref.read(availableOrdersProvider.notifier).clearDevOrder();
      if (mounted) context.push('/driver/order/active', extra: order);
      return;
    }
    try {
      // Sauvegarde la notification originale (contient client.phone depuis le backend)
      // avant qu'elle soit effacée après acceptation
      final notifOrder = (ref.read(availableOrdersProvider).value ?? [])
          .firstWhere((o) => o['id'] == orderId, orElse: () => {});
      final acceptedOrder = await ref.read(ordersRepositoryProvider).acceptOrder(orderId);
      // Fusionne : notifOrder (infos client) + acceptedOrder (statut ACCEPTED)
      final merged = {...notifOrder, ...acceptedOrder};
      if (mounted) context.push('/driver/order/active', extra: merged);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final isAvailable = profile.isAvailable;
    final ordersAsync = ref.watch(availableOrdersProvider);
    final orders = ordersAsync.value ?? [];

    // Auto-online → charge les commandes
    ref.listen<ProfileState>(profileProvider, (prev, next) {
      if (!(prev?.isAvailable ?? false) && next.isAvailable) {
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });

    // Nouvelle course → countdown + route vers pickup
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
      availableOrdersProvider,
      (prev, next) {
        final prevList = prev?.value ?? [];
        final nextList = next.value ?? [];
        if (nextList.isNotEmpty && prevList.isEmpty) {
          final first = nextList.first;
          final isDevOrder = first['id']?.toString().startsWith('dev-') ?? false;
          _startCountdown(
            isDevOrder: isDevOrder,
            orderId: isDevOrder ? null : first['id']?.toString(),
          );
          _loadPendingRoute(first);
        } else if (nextList.isEmpty) {
          _cancelCountdown();
          _clearPendingRoute();
        }
      },
    );

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(target: _dakar, zoom: 14),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_driverPosition != null) _centerOn(_driverPosition!);
              },
              onCameraMove: (_) {
                if (_autoFollow) setState(() => _autoFollow = false);
              },
              style: _mapStyle,
              markers: _driverMarkers,
              circles: _heatmapCircles,
              polylines: _pendingPolylines,
              trafficEnabled: false,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Header ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: profile.isLoading ? null : () => _toggleAvailability(!isAvailable),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isAvailable ? AppColors.primary : Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 8,
                                  color: isAvailable ? Colors.white : AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Text(isAvailable ? 'En ligne' : 'Hors ligne',
                                  style: TextStyle(
                                      color: isAvailable ? Colors.white : AppColors.textSecondary,
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Switch.adaptive(
                                value: isAvailable,
                                onChanged: _toggleAvailability,
                                activeThumbColor: Colors.white,
                                activeTrackColor: Colors.white.withValues(alpha: 0.4),
                                inactiveThumbColor: AppColors.textSecondary,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.push('/driver/profile'),
                        child: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.45),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.person_outline, color: Colors.white, size: 22),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Bouton re-centrer ──
          if (!_autoFollow)
            Positioned(
              left: 16,
              bottom: 220,
              child: GestureDetector(
                onTap: _recenter,
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                  child: const Icon(Icons.my_location, color: AppColors.primary, size: 22),
                ),
              ),
            ),

          // ── Bottom sheet — 2 états ──
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: orders.isNotEmpty && (isAvailable || (orders.first['id']?.toString().startsWith('dev-') ?? false))
                  ? _ThiakOrderSheet(
                      key: const ValueKey('order'),
                      order: orders.first,
                      countdown: _countdown,
                      countdownColor: _countdownColor,
                      onAccept: () => _acceptOrder(orders.first['id']),
                      onDecline: () {
                        _cancelCountdown();
                        _clearPendingRoute();
                        final orderId = orders.first['id']?.toString();
                        if (orderId != null && !(orderId.startsWith('dev-'))) {
                          ref.read(ordersRepositoryProvider).declineOrder(orderId).catchError((_) {});
                        } else {
                          ref.read(availableOrdersProvider.notifier).clearDevOrder();
                        }
                        ref.read(availableOrdersProvider.notifier).refresh();
                      },
                    )
                  : _ThiakNormalSheet(
                      key: const ValueKey('normal'),
                      profile: profile,
                      isAvailable: isAvailable,
                      onDevTap: () => ref.read(availableOrdersProvider.notifier).injectDevOrder(orderType: 'RIDE'),
                    ),
            ),
          ),


        ],
      ),
    );
  }
}

// ── Sheet normal Thiak Thiak ──────────────────────────────────────────────────
class _ThiakNormalSheet extends StatelessWidget {
  final dynamic profile;
  final bool isAvailable;
  final VoidCallback? onDevTap;

  const _ThiakNormalSheet({super.key, required this.profile, required this.isAvailable, this.onDevTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewPadding.bottom + 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 32, offset: const Offset(0, -4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                profile.name.isNotEmpty ? 'Bonjour, ${profile.name} 👋' : 'Bonjour 👋',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isAvailable ? 'En attente de courses...' : 'Activez pour recevoir des courses',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  if (onDevTap != null)
                    GestureDetector(
                      onTap: onDevTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('DEV', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
              if (isAvailable) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    _StatChip(icon: Icons.route, label: '0 courses', color: Colors.white),
                    const SizedBox(width: 12),
                    _StatChip(icon: Icons.star_outline, label: '—', color: Colors.white),
                    const SizedBox(width: 12),
                    _StatChip(icon: Icons.monetization_on_outlined, label: '0 FCFA', color: Colors.white),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sheet nouvelle course Thiak Thiak ────────────────────────────────────────
class _ThiakOrderSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final int countdown;
  final Color countdownColor;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _ThiakOrderSheet({
    super.key,
    required this.order,
    required this.countdown,
    required this.countdownColor,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final pickup = order['pickupAddress'] ?? '';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewPadding.bottom + 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [
                AppColors.primary.withValues(alpha: 0.92),
                const Color(0xFF1A6B7A).withValues(alpha: 0.96),
              ],
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(0, -4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              )),
              // Titre + countdown
              Row(
                children: [
                  const Icon(Icons.directions_car_outlined, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  const Text('Nouveau passager',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  SizedBox(
                    width: 48, height: 48,
                    child: Stack(alignment: Alignment.center, children: [
                      CircularProgressIndicator(
                        value: countdown / 30,
                        strokeWidth: 3.5,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        color: countdownColor,
                      ),
                      Text('$countdown',
                          style: TextStyle(color: countdownColor, fontSize: 14, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Adresse pickup uniquement (destination révélée après)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  const Icon(Icons.circle, color: Color(0xFF4CAF50), size: 12),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Prise en charge',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
                      Text(pickup,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  )),
                ]),
              ),
              const SizedBox(height: 8),
              // Destination masquée
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Row(children: [
                  Icon(Icons.lock_outline, color: Colors.white.withValues(alpha: 0.4), size: 14),
                  const SizedBox(width: 10),
                  Text('Destination révélée après prise en charge',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12,
                          fontStyle: FontStyle.italic)),
                ]),
              ),
              const SizedBox(height: 14),
              // Prix
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$price FCFA', textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 14),
              // Boutons
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: onDecline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('Refuser', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: GestureDetector(
                  onTap: onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text('Accepter', textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.primary, fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
