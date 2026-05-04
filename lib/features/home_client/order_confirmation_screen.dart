import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../deliveries/providers/orders_provider.dart';
import '../home_driver/navigation/map_theme.dart';

/// Affiché après la création d'une commande.
/// Reçoit l'objet `order` retourné par le backend.
class OrderConfirmationScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  const OrderConfirmationScreen({super.key, required this.order});

  @override
  ConsumerState<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends ConsumerState<OrderConfirmationScreen> {
  String? _mapStyle;
  List<LatLng> _routePoints = [];
  bool _cancelling = false;

  StreamSubscription<Map<String, dynamic>>? _acceptedSub;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchRoute();
    _connectSocket();
  }

  @override
  void dispose() {
    _acceptedSub?.cancel();
    super.dispose();
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
      context.pushReplacement('/orders/tracking', extra: {
        'orderId': data['orderId'] as String,
        'driverId': driverId,
        'etaPickupMin': data['etaPickupMin'] as int?,
      });
    });
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString(MapTheme.styleAsset);
    if (mounted) setState(() => _mapStyle = style);
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
        _showToast(context, message: e.toString(), icon: Icons.error_outline_rounded, isError: true);
      }
    }
  }

  void _showToast(BuildContext ctx, {required String message, required IconData icon, required bool isError}) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: isError
                ? const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFFE53935)])
                : AppColors.gradientSplash,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: Row(children: [
            Icon(icon, color: isError ? Colors.white : const Color(0xFF69F0AE), size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))),
          ]),
        ),
      ),
    );
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
              initialCameraPosition: CameraPosition(target: initialTarget, zoom: 17, tilt: 55),
              style: _mapStyle,
              markers: markers,
              polylines: polylines,
              zoomControlsEnabled: false,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
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
                      Center(child: Container(width: 36, height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 16),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(
                          children: [
                            // ── Indicateur de chargement ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                                const SizedBox(width: 12),
                                const Text('Recherche d\'un driver en cours…',
                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
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
                                  Divider(color: Colors.white.withValues(alpha: 0.15), height: 14),
                                ],
                                Row(children: [
                                  const Text('TOTAL', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                                  const Spacer(),
                                  Text(
                                    '${((price ?? 0) + demFee).toInt()} FCFA',
                                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                ]),
                              ]),
                            ),
                            const SizedBox(height: 20),

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
                                    onTap: _cancelling ? null : () => context.pop(),
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
                        ),
                      ),
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
