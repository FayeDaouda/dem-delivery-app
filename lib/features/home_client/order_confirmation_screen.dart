import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchRoute();
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

    if (pickupLat == null || pickupLng == null || deliveryLat == null || deliveryLng == null) return;
    
    // Draw basic straight line initially
    if (mounted) setState(() => _routePoints = [
      LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
      LatLng(deliveryLat.toDouble(), deliveryLng.toDouble()),
    ]);

    try {
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
      final res = await dio.get('https://router.project-osrm.org/route/v1/driving/${pickupLng},${pickupLat};${deliveryLng},${deliveryLat}?overview=full&geometries=geojson');
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
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Annuler la commande ?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text('Voulez-vous vraiment annuler cette commande en attente ?', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, annuler', style: TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(ordersRepositoryProvider).cancelOrder(orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Commande annulée avec succès'), backgroundColor: Color(0xFF4CAF50)),
        );
        context.pop(); // Returns to home
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order           = widget.order;
    final price           = order['price'] as num?;
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
              initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14),
              style: _mapStyle,
              markers: markers,
              polylines: polylines,
              zoomControlsEnabled: false,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Contenu superposé Exactement comme Step 3 ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 0), // 0 to allow panel flush bottom
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Center(child: Container(width: 36, height: 3, decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 16),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(
                          children: [
                            // ── Indicateur de chargement ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
                                const SizedBox(width: 12),
                                const Text('Recherche d\'un driver en cours…',
                                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // ── Route recap ──
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _RouteRow(icon: Icons.circle, color: AppColors.success, text: pickupAddress),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Container(width: 2, height: 14, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                                  ),
                                  _RouteRow(icon: Icons.location_on, color: AppColors.error, text: deliveryAddress),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ── Price row ──
                            Row(children: [
                              const Text('Prix estimé', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              const Spacer(),
                              if (surge > 1.0) ...[
                                const Icon(Icons.flash_on, color: Color(0xFFFF9800), size: 14),
                                const SizedBox(width: 4),
                              ],
                              Text('${price?.toInt() ?? '—'} FCFA',
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                            ]),
                            const SizedBox(height: 24),

                            // ── Boutons Action ──
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF5252),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    onPressed: _cancelling ? null : _cancelOrder,
                                    child: _cancelling
                                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Text('Annuler', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    onPressed: _cancelling ? null : () => context.pop(),
                                    child: const Text('Retour à l\'accueil', style: TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
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
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}
