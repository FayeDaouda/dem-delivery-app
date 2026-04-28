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
import '../../core/theme/app_theme.dart';
import '../../core/theme/map_theme_provider.dart';
import '../../features/deliveries/providers/orders_provider.dart';
import '../../features/profile/providers/profile_provider.dart';
import 'navigation/directions_service.dart';
import 'navigation/map_theme.dart';
import 'navigation/navigation_service.dart';
import '../../core/map/poi_data.dart';

const _dakar = LatLng(14.6937, -17.4441);

class HomeDriverScreen extends ConsumerStatefulWidget {
  const HomeDriverScreen({super.key});

  @override
  ConsumerState<HomeDriverScreen> createState() => _HomeDriverScreenState();
}

class _HomeDriverScreenState extends ConsumerState<HomeDriverScreen>
    with TickerProviderStateMixin {
  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _driverIcon;
  double _currentZoom = 15.5;
  Map<String, BitmapDescriptor> _poiIcons = {};

  // ── Pulse animation ───────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  ScreenCoordinate? _driverScreenPos;

  // ── GPS ──────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _driverPosition;
  bool _autoFollow = true;

  // ── WebSocket ─────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _newOrderSub;
  StreamSubscription<String>?              _expiredOrderSub;
  StreamSubscription<void>?                _reconnectSub;

  // ── Polling fallback (si socket déconnecté) ───────────────────────────────
  Timer? _pollTimer;

  // ── Heartbeat lastSeenAt ──────────────────────────────────────────────────
  Timer? _heartbeatTimer;

  // ── Route vers pickup (pendant notification) ──────────────────────────────
  List<LatLng> _pendingRoutePoints = [];
  int?    _pendingEtaSeconds;
  double? _pendingDistanceMeters;

  // ── Throttle émission position ────────────────────────────────────────────
  DateTime? _lastLocationEmit;

  // ── Countdown nouvelle course ─────────────────────────────────────────────
  int _countdown = 20;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulseScale = Tween<double>(begin: 0.4, end: 2.2).animate(_pulseCtrl);
    _pulseOpacity = Tween<double>(begin: 0.7, end: 0.0).animate(_pulseCtrl);

    _loadMapStyle();
    _buildDriverIcon().then((icon) {
      if (mounted) setState(() => _driverIcon = icon);
    });
    buildPoiIcons().then((icons) {
      if (mounted) setState(() => _poiIcons = icons);
    });
    _startGPS();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).fetchProfile(goOnlineIfOffline: true);
      _connectSocket();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _locationSub?.cancel();
    _mapController?.dispose();
    _countdownTimer?.cancel();
    _newOrderSub?.cancel();
    _expiredOrderSub?.cancel();
    _reconnectSub?.cancel();
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;

    SocketService.instance.connect(token);

    _newOrderSub = SocketService.instance.onNewOrder.listen((order) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).injectSocketOrder(order);
      _startCountdown();
    });

    _expiredOrderSub = SocketService.instance.onOrderExpired.listen((orderId) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).removeOrder(orderId);
      _cancelCountdown();
    });

    _reconnectSub = SocketService.instance.onReconnect.listen((_) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).refresh();
    });

    // Heartbeat toutes les 30s pour maintenir lastSeenAt à jour côté backend
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!SocketService.instance.isConnected) return;
      final pos = _driverPosition;
      SocketService.instance.ping(lat: pos?.latitude, lng: pos?.longitude);
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final isAvailable = ref.read(profileProvider).isAvailable;
      final hasOrder    = (ref.read(availableOrdersProvider).value ?? []).isNotEmpty;
      if (isAvailable && !hasOrder && !SocketService.instance.isConnected) {
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 20);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    if (mounted) setState(() => _countdown = 20);
  }

  // ── Map style ─────────────────────────────────────────────────────────────
  Future<void> _loadMapStyle() async {
    final bool isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleMapTheme() async {
    await ref.read(mapNightProvider.notifier).toggle();
    await _loadMapStyle();
  }

  // ── Marqueur triangle Waze ────────────────────────────────────────────────
  static Future<BitmapDescriptor> _buildDriverIcon() async {
    const double size = 96;
    const double cx = size / 2;
    const double cy = size / 2;
    const double haloR = 40;
    const double arrowR = 18;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Halo semi-transparent
    canvas.drawCircle(
      const Offset(cx, cy),
      haloR,
      Paint()..color = const Color(0x4033BCD4),
    );

    // Triangle pointant vers le haut
    final path = Path()
      ..moveTo(cx, cy - arrowR)
      ..lineTo(cx + arrowR * 0.8, cy + arrowR * 0.6)
      ..lineTo(cx - arrowR * 0.8, cy + arrowR * 0.6)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF33BCD4));

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: size / 2,
      height: size / 2,
    );
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> _startGPS() async {
    final initial = await NavigationService.requestAndGetPosition();
    if (initial != null && mounted) {
      setState(() => _driverPosition = initial);
      _centerOn(initial);
    }

    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  bool _firstPositionSent = false;

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _driverPosition = position);
    if (_autoFollow) _centerOn(position);
    _updateDriverScreenPos();
    _trySendFirstPosition(position);

    // Émission position au backend toutes les 10s pour le dispatch
    final now = DateTime.now();
    if (_lastLocationEmit == null || now.difference(_lastLocationEmit!).inSeconds >= 10) {
      _lastLocationEmit = now;
      SocketService.instance.ping(lat: position.latitude, lng: position.longitude);
    }
  }

  void _trySendFirstPosition(Position position) {
    if (_firstPositionSent) return;
    _firstPositionSent = true;
    // Envoi via REST (fiable) + socket ping
    ref.read(ordersRepositoryProvider).updateDriverLocation(
      position.latitude, position.longitude,
    ).catchError((_) {});
    if (SocketService.instance.isConnected) {
      SocketService.instance.ping(lat: position.latitude, lng: position.longitude);
    }
  }

  Future<void> _updateDriverScreenPos() async {
    if (_driverPosition == null || _mapController == null) return;
    final coord = await _mapController!.getScreenCoordinate(
      LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
    );
    if (mounted) setState(() => _driverScreenPos = coord);
  }

  void _centerOn(Position position) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 15.5, // vue rue détaillée style Waze
          bearing: 0, // nord fixe — pas de rotation sur l'écran d'accueil
          tilt: 0, // plat = labels quartiers + POI visibles
        ),
      ),
    );
  }

  void _recenter() {
    if (_driverPosition == null) return;
    setState(() => _autoFollow = true);
    _centerOn(_driverPosition!);
  }

  // ── Route vers pickup à la réception d'une offre ──────────────────────────
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
    if (!mounted) return;
    setState(() {
      _pendingRoutePoints    = result.points;
      _pendingEtaSeconds     = result.durationSeconds;
      _pendingDistanceMeters = result.distanceMeters;
    });
    _fitBoundsDriverToPickup(origin, pickup);
  }

  void _fitBoundsDriverToPickup(LatLng driver, LatLng pickup) {
    final bounds = LatLngBounds(
      southwest: LatLng(
        driver.latitude  < pickup.latitude  ? driver.latitude  : pickup.latitude,
        driver.longitude < pickup.longitude ? driver.longitude : pickup.longitude,
      ),
      northeast: LatLng(
        driver.latitude  > pickup.latitude  ? driver.latitude  : pickup.latitude,
        driver.longitude > pickup.longitude ? driver.longitude : pickup.longitude,
      ),
    );
    setState(() => _autoFollow = false);
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _clearPendingRoute() {
    if (!mounted) return;
    setState(() {
      _pendingRoutePoints    = [];
      _pendingEtaSeconds     = null;
      _pendingDistanceMeters = null;
    });
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

  // ── Marker driver triangle Waze ───────────────────────────────────────────
  Set<Marker> get _driverMarkers {
    final markers = <Marker>{};
    if (_driverPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
        icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        flat: true,
        rotation: _driverPosition!.heading,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
      ));
    }
    if (_currentZoom >= 13 && _poiIcons.isNotEmpty) {
      for (final poi in dakarPois) {
        final icon = _poiIcons[poi.id];
        if (icon == null) continue;
        markers.add(Marker(
          markerId: MarkerId('poi_${poi.id}'),
          position: poi.position,
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 1,
          infoWindow: InfoWindow(title: poi.name, snippet: poi.category.label),
        ));
      }
    }
    return markers;
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _toggleAvailability() async {
    try {
      await ref.read(profileProvider.notifier).toggleAvailability();
      final isAvailable = ref.read(profileProvider).isAvailable;
      if (isAvailable) ref.read(availableOrdersProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    // Mode DEV — commande simulée, pas d'appel API
    if (orderId.startsWith('dev-')) {
      final devOrder = ref.read(availableOrdersProvider).value?.firstWhere(
            (o) => o['id'] == orderId,
            orElse: () => {},
          ) ?? {};
      if (mounted) context.push('/driver/order/active', extra: devOrder);
      return;
    }
    try {
      // Sauvegarde la notification originale (contient client.phone depuis le backend)
      // avant qu'elle soit effacée par le provider après acceptation
      final notifOrder = (ref.read(availableOrdersProvider).value ?? [])
          .firstWhere((o) => o['id'] == orderId, orElse: () => {});
      final acceptedOrder = await ref
          .read(ordersRepositoryProvider)
          .acceptOrder(orderId);
      // Fusionne : notifOrder (infos client) + acceptedOrder (statut ACCEPTED)
      // acceptedOrder écrase les champs en double (status, etc.)
      final merged = {...notifOrder, ...acceptedOrder};
      if (mounted) context.push('/driver/order/active', extra: merged);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final isAvailable = profile.isAvailable;
    final ordersAsync = ref.watch(availableOrdersProvider);
    // En cas d'erreur API, on traite comme liste vide (pas d'affichage d'erreur)
    final orders = ordersAsync.value ?? [];

    // Mise en ligne auto → charge les commandes
    ref.listen<ProfileState>(profileProvider, (prev, next) {
      if (!(prev?.isAvailable ?? false) && next.isAvailable) {
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });

    // Détecte l'arrivée d'une nouvelle course → route + fit bounds + countdown
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
      availableOrdersProvider,
      (prev, next) {
        final prevList = prev?.value ?? [];
        final nextList = next.value ?? [];
        if (nextList.isNotEmpty && prevList.isEmpty && isAvailable) {
          _startCountdown();
          _loadPendingRoute(nextList.first);
        } else if (nextList.isEmpty) {
          _cancelCountdown();
          _clearPendingRoute();
        }
      },
    );

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte plein écran style Waze sombre ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _dakar,
                zoom: 14,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_driverPosition != null) _centerOn(_driverPosition!);
              },
              style: _mapStyle,
              onCameraMove: (pos) {
                if (_autoFollow) setState(() => _autoFollow = false);
                if ((pos.zoom - _currentZoom).abs() > 0.5) {
                  setState(() => _currentZoom = pos.zoom);
                }
              },
              onCameraIdle: _updateDriverScreenPos,
              markers: _driverMarkers,
              polylines: _pendingPolylines,
              trafficEnabled: false,
              buildingsEnabled: true,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Pulse animation sur le marqueur driver ──
          if (_driverScreenPos != null)
            Positioned(
              left: _driverScreenPos!.x.toDouble() - 30,
              top: _driverScreenPos!.y.toDouble() - 30,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, _) => Transform.scale(
                    scale: _pulseScale.value,
                    child: Opacity(
                      opacity: _pulseOpacity.value,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF33BCD4),
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Toggle disponibilité + profil (header) ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Toggle
                  GestureDetector(
                    onTap: profile.isLoading ? null : _toggleAvailability,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isAvailable
                            ? AppColors.primary
                            : Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: isAvailable
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isAvailable ? 'En ligne' : 'Hors ligne',
                            style: TextStyle(
                              color: isAvailable
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          profile.isLoading
                              ? const SizedBox(
                                  width: 28,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Switch.adaptive(
                                  value: isAvailable,
                                  onChanged: (_) => _toggleAvailability(),
                                  activeThumbColor: Colors.white,
                                  activeTrackColor: Colors.white.withValues(
                                    alpha: 0.4,
                                  ),
                                  inactiveThumbColor: AppColors.textSecondary,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Profil
                  GestureDetector(
                    onTap: () => context.push('/driver/profile'),
                    child: Container(
                      width: 42,
                      height: 42,
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
                      child: const Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bouton re-centrer (boussole) — overlay quand on dézoom ──
          if (!_autoFollow)
            Positioned(
              left: 16,
              bottom: 220,
              child: GestureDetector(
                onTap: _recenter,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
            ),

          // ── Bouton toggle jour/nuit ──────────────────────────────────────
          Positioned(
            left: 16,
            bottom: _autoFollow ? 220 : 284,
            child: GestureDetector(
              onTap: _toggleMapTheme,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.card, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12)],
                ),
                child: Icon(
                  ref.watch(mapNightProvider) ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                  color: ref.watch(mapNightProvider) ? const Color(0xFFFFB300) : AppColors.primary,
                  size: 22,
                ),
              ),
            ),
          ),

          // ── Bottom sheet — 3 états (toujours visible) ──
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(anim);
                return SlideTransition(
                  position: slide,
                  child: FadeTransition(opacity: anim, child: child),
                );
              },
              child: isAvailable && orders.isNotEmpty
                  // ── État 3 : nouvelle course ──
                  ? _OrderNotificationSheet(
                      key: const ValueKey('order'),
                      order: orders.first,
                      countdown: _countdown,
                      etaSeconds: _pendingEtaSeconds,
                      distanceMeters: _pendingDistanceMeters,
                      onAccept: () {
                        _cancelCountdown();
                        _clearPendingRoute();
                        _acceptOrder(orders.first['id']);
                      },
                      onDecline: () {
                        _cancelCountdown();
                        _clearPendingRoute();
                        ref.read(availableOrdersProvider.notifier).refresh();
                      },
                    )
                  // ── État 1 : accueil normal ──
                  : _NormalSheet(
                      key: const ValueKey('normal'),
                      profile: profile,
                      isAvailable: isAvailable,
                      ordersLoading: ordersAsync.isLoading,
                      onToggle: _toggleAvailability,
                      onDevTap: null,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glassmorphism sheet base ──────────────────────────────────────────────────
class _GlassSheet extends StatelessWidget {
  final Widget child;

  const _GlassSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.vertical(top: Radius.circular(28));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
              stops: [0.0, 0.5, 1.0],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 32,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── État 1 : accueil normal ───────────────────────────────────────────────────
class _NormalSheet extends StatelessWidget {
  final dynamic profile;
  final bool isAvailable;
  final bool ordersLoading;
  final VoidCallback onToggle;
  final VoidCallback? onDevTap;

  const _NormalSheet({
    super.key,
    required this.profile,
    required this.isAvailable,
    required this.ordersLoading,
    required this.onToggle,
    this.onDevTap,
  });

  @override
  Widget build(BuildContext context) {
    const textPrimary = Colors.white;
    final textSecondary = Colors.white.withValues(alpha: 0.70);

    return _GlassSheet(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewPadding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isNotEmpty
                            ? 'Bonjour, ${profile.name} 👋'
                            : 'Bonjour 👋',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAvailable
                            ? 'En attente de courses...'
                            : 'Activez pour recevoir des courses',
                        style: TextStyle(color: textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (ordersLoading)
                  SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                if (onDevTap != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onDevTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('DEV',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ],
            ),
            if (isAvailable) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  _StatPill(
                    icon: Icons.route_outlined,
                    label: '0 courses',
                    color: AppColors.primary,
                    onTap: () => _showStatModal(context, _StatType.courses),
                  ),
                  const SizedBox(width: 10),
                  _StatPill(
                    icon: Icons.monetization_on_outlined,
                    label: '0 FCFA',
                    color: AppColors.primaryDark,
                    onTap: () => _showStatModal(context, _StatType.gains),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── État 3 : notification nouvelle course ─────────────────────────────────────
class _OrderNotificationSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final int countdown;
  final int?    etaSeconds;
  final double? distanceMeters;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _OrderNotificationSheet({
    super.key,
    required this.order,
    required this.countdown,
    this.etaSeconds,
    this.distanceMeters,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final pickup = order['pickupAddress'] ?? '';
    final delivery = order['deliveryAddress'] ?? '';

    return _GlassSheet(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewPadding.bottom + 16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.primary, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header : titre + countdown
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 26),
                const SizedBox(width: 10),
                const Text(
                  'Nouvelle livraison',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                SizedBox(
                  width: 44, height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: countdown / 20,
                        strokeWidth: 3,
                        backgroundColor: AppColors.card,
                        color: countdown > 8 ? AppColors.primary : Colors.orange,
                      ),
                      Text(
                        '$countdown',
                        style: TextStyle(
                          color: countdown > 8 ? AppColors.primary : Colors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (etaSeconds != null || distanceMeters != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (etaSeconds != null) ...[
                    const Icon(Icons.access_time_outlined, color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      NavigationService.formatDuration(etaSeconds!),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (etaSeconds != null && distanceMeters != null)
                    const SizedBox(width: 16),
                  if (distanceMeters != null) ...[
                    const Icon(Icons.straighten_outlined, color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      NavigationService.formatDistance(distanceMeters!),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Adresses sur carte blanche pour lisibilité
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _AddressRow(
                    icon: Icons.circle,
                    color: Colors.black87,
                    label: 'Récupération',
                    address: pickup,
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
                    width: 1.5, height: 12,
                    color: Colors.black12,
                  ),
                  _AddressRow(
                    icon: Icons.location_on,
                    color: Colors.black87,
                    label: 'Livraison',
                    address: delivery,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Prix
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$price FCFA',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Boutons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onDecline,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        border: Border.all(color: Colors.red, width: 1.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Refuser',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red, fontSize: 15, fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: onAccept,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Accepter',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600,
                        ),
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
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String address;

  const _AddressRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black45,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                address,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Modal détail statistique ──────────────────────────────────────────────────
void _showStatModal(BuildContext context, _StatType type) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _StatDetailModal(type: type),
  );
}

enum _StatType { courses, rating, gains }

class _StatDetailModal extends StatelessWidget {
  final _StatType type;
  const _StatDetailModal({required this.type});

  @override
  Widget build(BuildContext context) {
    final config = _modalConfig(type);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 16, 24, MediaQuery.of(context).viewPadding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Icône + titre
          Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Icon(config['icon'] as IconData, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Text(
                config['title'] as String,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Lignes de stats
          ...((config['rows'] as List<Map<String, String>>).map(
            (row) => _StatRow(label: row['label']!, value: row['value']!, sub: row['sub']),
          )),
        ],
      ),
    );
  }

  Map<String, dynamic> _modalConfig(_StatType type) {
    switch (type) {
      case _StatType.courses:
        return {
          'icon': Icons.route_outlined,
          'title': 'Mes courses',
          'rows': [
            {'label': "Aujourd'hui",   'value': '0',  'sub': 'courses effectuées'},
            {'label': 'Cette semaine', 'value': '0',  'sub': 'courses effectuées'},
            {'label': 'Total',         'value': '0',  'sub': 'depuis le début'},
            {'label': 'Annulées',      'value': '0',  'sub': 'taux 0%'},
          ],
        };
      case _StatType.rating:
        return {
          'icon': Icons.star_outline_rounded,
          'title': 'Ma note',
          'rows': [
            {'label': 'Note moyenne', 'value': '—',  'sub': 'sur 5 étoiles'},
            {'label': 'Avis reçus',   'value': '0',  'sub': 'clients satisfaits'},
            {'label': 'Ponctualité',  'value': '—',  'sub': 'arrivée à temps'},
            {'label': 'Colis intact', 'value': '—',  'sub': 'taux de satisfaction'},
          ],
        };
      case _StatType.gains:
        return {
          'icon': Icons.monetization_on_outlined,
          'title': 'Mes gains',
          'rows': [
            {'label': "Aujourd'hui",   'value': '0 FCFA', 'sub': 'revenus du jour'},
            {'label': 'Cette semaine', 'value': '0 FCFA', 'sub': 'revenus 7 jours'},
            {'label': 'Ce mois',       'value': '0 FCFA', 'sub': 'revenus 30 jours'},
            {'label': 'Total cumulé',  'value': '0 FCFA', 'sub': 'depuis le début'},
          ],
        };
    }
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _StatRow({required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
