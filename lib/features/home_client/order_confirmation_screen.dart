import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import '../../core/error/app_exception.dart';
import '../../core/utils/dem_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/router/app_startup_notifier.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../deliveries/providers/orders_provider.dart';
import '../../core/theme/map_theme_provider.dart';
import '../home_driver/navigation/map_theme.dart';

/// Affiché après la création d'une commande.
/// Reçoit l'objet `order` retourné par le backend.
class OrderConfirmationScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  const OrderConfirmationScreen({super.key, required this.order});

  @override
  ConsumerState<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends ConsumerState<OrderConfirmationScreen>
    with SingleTickerProviderStateMixin {
  String? _mapStyle;
  List<LatLng> _routePoints = [];
  bool _cancelling = false;
  GoogleMapController? _mapController;

  StreamSubscription<Map<String, dynamic>>? _acceptedSub;

  // Timer d'attente
  int _waitSeconds = 0;
  Timer? _waitTimer;
  Timer? _pollTimer;
  bool _waitTimedOut = false;

  // Panel drag
  double _panelDragOffset = 0.0;
  bool _isDragging = false;
  static const double _kMaxContent = 295.0;
  static const double _kMinContent = 64.0; // buttons (50) + bottom pad (12) + 2px margin

  // Animation radar
  late final AnimationController _radarCtrl;
  late final Animation<double> _radarAnim;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchRoute();
    _connectSocket();

    // Radar pulsé
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _radarAnim = CurvedAnimation(parent: _radarCtrl, curve: Curves.easeOut);

    _startPolling();

    // Timer d'attente visible — déclenche le timeout à 5 min
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _waitSeconds++;
        if (_waitSeconds >= 300 && !_waitTimedOut) _waitTimedOut = true;
      });
    });
  }

  @override
  void dispose() {
    _acceptedSub?.cancel();
    _pollTimer?.cancel();
    _mapController?.dispose();
    _radarCtrl.dispose();
    _waitTimer?.cancel();
    super.dispose();
  }

  String get _waitLabel {
    if (_waitSeconds < 60) return '$_waitSeconds s';
    final m = _waitSeconds ~/ 60;
    final s = _waitSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

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
      context.pushReplacement('/orders/tracking', extra: {
        'orderId': data['orderId'] as String,
        'driverId': driverId,
        'etaPickupMin': data['etaPickupMin'] as int?,
        'initialOrder': {
          ...widget.order,
          'status': 'ACCEPTED',
          'driverId': driverId,
        },
      });
    });
  }

  // ── Polling REST fallback (si socket mort au moment de l'acceptation) ────────
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
          context.pushReplacement('/orders/tracking', extra: {
            'orderId': orderId,
            'driverId': driverId,
            'initialOrder': {...order, 'status': 'ACCEPTED'},
          });
        } else if (status == 'CANCELLED') {
          _pollTimer?.cancel();
          context.pop();
        }
      } catch (_) {
        // réseau indisponible — on réessaie au prochain tick
      }
    });
  }

  // ── Timeout 5 min — le client choisit de continuer d'attendre ───────────────
  void _continueWaiting() => setState(() { _waitTimedOut = false; _waitSeconds = 0; });

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleMapTheme() async {
    await ref.read(mapNightProvider.notifier).toggle();
    await _loadMapStyle();
  }

  Future<void> _fetchRoute() async {
    final order = widget.order;
    final pickupLat = order['pickupLatitude'] as num?;
    final pickupLng = order['pickupLongitude'] as num?;
    final deliveryLat = order['deliveryLatitude'] as num?;
    final deliveryLng = order['deliveryLongitude'] as num?;

    if (pickupLat == null || pickupLng == null || deliveryLat == null || deliveryLng == null) {
      return;
    }

    if (mounted) {
      setState(() => _routePoints = [
        LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
        LatLng(deliveryLat.toDouble(), deliveryLng.toDouble()),
      ]);
    }

    try {
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
      final res = await dio.get('https://router.project-osrm.org/route/v1/driving/$pickupLng,$pickupLat;$deliveryLng,$deliveryLat?overview=full&geometries=geojson');
      if (res.statusCode == 200 && res.data['routes'] != null && (res.data['routes'] as List).isNotEmpty) {
        final route = res.data['routes'][0];
        final coords = route['geometry']['coordinates'] as List;
        final points = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
        if (mounted) setState(() => _routePoints = points);
      }
    } catch (_) {}
  }

  Future<void> _cancelOrder() async {
    final orderId = widget.order['id'] as String?;
    if (orderId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.gradientSplash,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Annuler la commande ?',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 10),
              Text('Voulez-vous vraiment annuler cette commande en attente ?',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Non', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Oui, annuler', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(ordersRepositoryProvider).cancelOrder(orderId);
      if (mounted) {
        _showToast(context, message: 'Commande annulée avec succès', icon: Icons.check_circle_rounded, isError: false);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cancelling = false);
        _showToast(context, message: friendlyError(e), icon: Icons.error_outline_rounded, isError: true);
      }
    }
  }

  void _showToast(BuildContext ctx, {required String message, required IconData icon, required bool isError}) {
    showDemToast(ctx, message, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final order           = widget.order;
    final price           = (order['price'] as num?)?.toDouble();
    final demFee          = (order['demFee'] as num?)?.toDouble() ?? 0.0;
    final surge           = (order['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
    final pickupAddress   = order['pickupAddress'] as String? ?? 'Départ';
    final deliveryAddress = order['deliveryAddress'] as String? ?? 'Arrivée';

    final pickupLat = order['pickupLatitude'] as num?;
    final pickupLng = order['pickupLongitude'] as num?;
    final deliveryLat = order['deliveryLatitude'] as num?;
    final deliveryLng = order['deliveryLongitude'] as num?;

    Set<Marker> markers = {};
    Set<Polyline> polylines = {};

    if (pickupLat != null && pickupLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    if (deliveryLat != null && deliveryLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(deliveryLat.toDouble(), deliveryLng.toDouble()),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    if (_routePoints.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints,
        color: AppColors.primary,
        width: 4,
      ));
    }

    final initialTarget = pickupLat != null && pickupLng != null 
        ? LatLng(pickupLat.toDouble(), pickupLng.toDouble()) 
        : const LatLng(14.6937, -17.4441);

    return Scaffold(
      body: Stack(
        children: [
          // ── Map Background ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14, tilt: 40),
              style: _mapStyle,
              markers: markers,
              polylines: polylines,
              zoomControlsEnabled: false,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
              onMapCreated: (controller) {
                _mapController = controller;
                // Zoom pour montrer les deux points dès l'ouverture
                if (pickupLat != null && pickupLng != null &&
                    deliveryLat != null && deliveryLng != null) {
                  Future.delayed(const Duration(milliseconds: 400), () {
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngBounds(
                        LatLngBounds(
                          southwest: LatLng(
                            pickupLat.toDouble() < deliveryLat.toDouble() ? pickupLat.toDouble() : deliveryLat.toDouble(),
                            pickupLng.toDouble() < deliveryLng.toDouble() ? pickupLng.toDouble() : deliveryLng.toDouble(),
                          ),
                          northeast: LatLng(
                            pickupLat.toDouble() > deliveryLat.toDouble() ? pickupLat.toDouble() : deliveryLat.toDouble(),
                            pickupLng.toDouble() > deliveryLng.toDouble() ? pickupLng.toDouble() : deliveryLng.toDouble(),
                          ),
                        ),
                        90, // padding en pixels
                      ),
                    );
                  });
                }
              },
            ),
          ),

          // ── MAP THEME TOGGLE ──────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: max(_kMinContent + 22.0, _kMaxContent - _panelDragOffset + 22.0)
                + 60
                + MediaQuery.of(context).viewPadding.bottom,
            child: GestureDetector(
              onTap: _toggleMapTheme,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1535), shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
                ),
                child: Icon(
                  ref.watch(mapNightProvider) ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                  color: ref.watch(mapNightProvider) ? const Color(0xFFFFB300) : AppColors.primary,
                  size: 20,
                ),
              ),
            ),
          ),

          // ── Bouton partager ──────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: () {
                final id = widget.order['id'] as String? ?? '';
                final url = 'https://api.dem.sn/track/$id';
                SharePlus.instance.share(ShareParams(text: 'Suivez ma livraison DEM en temps réel : $url'));
              },
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
                ),
                child: const Icon(Icons.share_outlined, size: 18, color: Colors.black87),
              ),
            ),
          ),

          // ── Panneau bas dégradé cyan ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.gradientSplash,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragStart: (_) => setState(() => _isDragging = true),
                        onVerticalDragUpdate: (d) {
                          final maxOffset = _kMaxContent - _kMinContent;
                          setState(() {
                            _panelDragOffset = (_panelDragOffset + d.delta.dy).clamp(0.0, maxOffset);
                          });
                        },
                        onVerticalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          final maxOffset = _kMaxContent - _kMinContent;
                          setState(() {
                            _isDragging = false;
                            _panelDragOffset = (v > 200 || _panelDragOffset > maxOffset / 2) ? maxOffset : 0.0;
                          });
                        },
                        onTap: () {
                          final maxOffset = _kMaxContent - _kMinContent;
                          setState(() {
                            _isDragging = false;
                            _panelDragOffset = _panelDragOffset == 0 ? maxOffset : 0.0;
                          });
                        },
                        child: SizedBox(
                          width: double.infinity,
                          height: 22,
                          child: Center(child: Container(width: 36, height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)))),
                        ),
                      ),

                      AnimatedContainer(
                        duration: _isDragging ? Duration.zero : const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        height: (_kMaxContent - _panelDragOffset).clamp(_kMinContent, _kMaxContent),
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            maxHeight: _kMaxContent,
                            child: SizedBox(
                              height: _kMaxContent,
                              child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(
                          children: [
                            // ── Header : radar normal OU timeout 5 min ──
                            if (_waitTimedOut)
                              _TimeoutBanner(onContinue: _continueWaiting, onCancel: _cancelOrder)
                            else
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedBuilder(
                                    animation: _radarAnim,
                                    builder: (ctx, child) => SizedBox(
                                      width: 36, height: 36,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Opacity(
                                            opacity: (1 - _radarAnim.value).clamp(0.0, 1.0),
                                            child: Container(
                                              width: 36 * _radarAnim.value,
                                              height: 36 * _radarAnim.value,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(color: AppColors.primary, width: 1.5),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 10, height: 10,
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Recherche d\'un livreur…',
                                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                      Text('Attente : $_waitLabel',
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                                    ],
                                  ),
                                ],
                              ),
                            const SizedBox(height: 16),

                            // ── Route recap ──
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _RouteRow(icon: Icons.circle, color: const Color(0xFF69F0AE), text: pickupAddress),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Container(width: 2, height: 14, color: Colors.white.withValues(alpha: 0.25)),
                                  ),
                                  _RouteRow(icon: Icons.location_on, color: AppColors.error, text: deliveryAddress),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Price breakdown ──
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(children: [
                                Row(children: [
                                  Text('Course', style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 13)),
                                  const Spacer(),
                                  if (surge > 1.0) ...[
                                    const Icon(Icons.flash_on, color: Color(0xFFFF9800), size: 13),
                                    const SizedBox(width: 3),
                                  ],
                                  Text('${price?.toInt() ?? '—'} FCFA',
                                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                                ]),
                                if (demFee > 0) ...[
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    Text('Frais DEM', style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 13)),
                                    const Spacer(),
                                    Text('+${demFee.toInt()} FCFA',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 13)),
                                  ]),
                                ],
                              ]),
                            ),
                            const Spacer(),

                            // ── Boutons Action ──
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _cancelling ? null : _cancelOrder,
                                    child: Container(
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF5252),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 8, offset: const Offset(0, 3))],
                                      ),
                                      child: Center(
                                        child: _cancelling
                                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                            : const Text('Annuler', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _cancelling ? null : () {
                      context.go(appStartupNotifier.homeForRole);
                      Future.microtask(() {
                        if (context.mounted) {
                          showDemToast(context, 'Votre commande est en attente — vous serez notifié dès qu\'un livreur est trouvé.');
                        }
                      });
                    },
                                    child: Container(
                                      height: 50,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF00D2FF), Color(0xFF0086C8)],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 8, offset: const Offset(0, 3))],
                                      ),
                                      child: const Center(
                                        child: Text('Retour à l\'accueil',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),       // Column
                      ),         // Padding
                    ),           // SizedBox
                  ),             // OverflowBox
                ),               // ClipRect
              ),                 // AnimatedContainer
            ],                   // outer Column children
          ),                     // outer Column
        ),                       // Padding(top:8)
      ),                         // SafeArea
    ),                           // Container
  ),                             // Align
],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RouteRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

// ── Bannière timeout 5 min ────────────────────────────────────────────────────
class _TimeoutBanner extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onCancel;
  const _TimeoutBanner({required this.onContinue, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_off_rounded, color: Colors.white70, size: 28),
        const SizedBox(height: 8),
        const Text(
          'Aucun livreur disponible pour le moment',
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Nous continuons de chercher en arrière-plan.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.60)),
                ),
                child: const Text('Annuler',
                    style: TextStyle(color: Color(0xFFFF5252), fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onContinue,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.60)),
                ),
                child: const Text('Continuer d\'attendre',
                    style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
