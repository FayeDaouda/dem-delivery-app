import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../deliveries/providers/orders_provider.dart';
import '../home_driver/navigation/map_theme.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String driverId;
  final int? etaPickupMin;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.driverId,
    this.etaPickupMin,
  });

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  Map<String, dynamic>? _order;
  String _status = 'ACCEPTED';
  bool _loading = true;
  bool _rated = false;

  GoogleMapController? _mapController;
  String? _mapStyle;
  List<LatLng> _routePoints = [];

  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _driverLocationSub;
  LatLng? _driverLocation;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchOrder();
    _connectSocket();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _fetchOrder());
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _driverLocationSub?.cancel();
    _pollTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString(MapTheme.styleAsset);
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _fetchOrder() async {
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final order = await repo.getOrderById(widget.orderId);
      if (!mounted) return;
      final newStatus = order['status'] as String? ?? _status;
      setState(() {
        _order = order;
        _status = newStatus;
        _loading = false;
      });
      _fetchRoute();
      if (newStatus == 'DELIVERED' && !_rated) {
        Future.delayed(const Duration(milliseconds: 300), _showRatingDialog);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchRoute() async {
    final order = _order;
    if (order == null) return;
    final pickupLat = (order['pickupLatitude'] as num?)?.toDouble();
    final pickupLng = (order['pickupLongitude'] as num?)?.toDouble();
    final deliveryLat = (order['deliveryLatitude'] as num?)?.toDouble();
    final deliveryLng = (order['deliveryLongitude'] as num?)?.toDouble();
    if (pickupLat == null ||
        pickupLng == null ||
        deliveryLat == null ||
        deliveryLng == null) {
      return;
    }

    try {
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
      final res = await dio.get(
        'https://router.project-osrm.org/route/v1/driving/$pickupLng,$pickupLat;$deliveryLng,$deliveryLat?overview=full&geometries=geojson',
      );
      if (res.statusCode == 200 &&
          (res.data['routes'] as List?)?.isNotEmpty == true) {
        final coords =
            res.data['routes'][0]['geometry']['coordinates'] as List;
        final points = coords
            .map((c) =>
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (mounted) setState(() => _routePoints = points);
      }
    } catch (_) {}
  }

  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;
    SocketService.instance.connect(token);
    _statusSub = SocketService.instance.onOrderStatusUpdated.listen((data) {
      if (!mounted) return;
      if (data['orderId'] != widget.orderId) return;
      final newStatus = data['status'] as String?;
      if (newStatus == null) return;
      setState(() => _status = newStatus);
      if (newStatus == 'DELIVERED' && !_rated) {
        Future.delayed(const Duration(milliseconds: 300), _showRatingDialog);
      }
    });

    _driverLocationSub = SocketService.instance.onDriverLocation.listen((data) {
      if (!mounted) return;
      if (data['orderId'] != widget.orderId) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      setState(() => _driverLocation = LatLng(lat, lng));
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(lat, lng), zoom: 17, tilt: 55)));
    });
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
                    '${((_order?['price'] as num?)?.toInt() ?? 0)} FCFA',
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
    final phone = (_order?['driver'] as Map<String, dynamic>?)?['phone']
        as String?;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  String get _statusLabel => switch (_status) {
        'ACCEPTED' => 'Driver en route vers vous',
        'PICKED_UP' => 'En route vers la destination',
        'DELIVERED' => 'Livraison effectuée ✓',
        _ => 'Commande en cours',
      };

  Color get _statusColor => switch (_status) {
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

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final pickupLat = (order?['pickupLatitude'] as num?)?.toDouble();
    final pickupLng = (order?['pickupLongitude'] as num?)?.toDouble();
    final deliveryLat = (order?['deliveryLatitude'] as num?)?.toDouble();
    final deliveryLng = (order?['deliveryLongitude'] as num?)?.toDouble();
    final initialTarget =
        pickupLat != null && pickupLng != null
            ? LatLng(pickupLat, pickupLng)
            : const LatLng(14.6937, -17.4441);

    final driverMap =
        order?['driver'] as Map<String, dynamic>?;
    final driverName = driverMap?['name'] as String? ?? 'Livreur';
    final hasDriverPhone =
        (driverMap?['phone'] as String?)?.isNotEmpty == true;
    final pickupAddress = order?['pickupAddress'] as String? ?? '';
    final deliveryAddress = order?['deliveryAddress'] as String? ?? '';
    final price = (order?['price'] as num?)?.toInt() ?? 0;

    final markers = <Marker>{
      if (pickupLat != null && pickupLng != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(pickupLat, pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      if (deliveryLat != null && deliveryLng != null)
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(deliveryLat, deliveryLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      if (_driverLocation != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: const InfoWindow(title: 'Votre livreur'),
        ),
    };

    final polylines = _routePoints.isNotEmpty
        ? {
            Polyline(
              polylineId: const PolylineId('route'),
              points: _routePoints,
              color: AppColors.primary,
              width: 4,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          }
        : <Polyline>{};

    if (_loading) {
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

          // Back button (iOS — pas de bouton physique)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTap: () => context.canPop() ? context.pop() : context.go('/client/home'),
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

                      // Status chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              _statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_status != 'DELIVERED')
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            else
                              const Icon(Icons.check_circle,
                                  color: Color(0xFF00C853), size: 14),
                            const SizedBox(width: 8),
                            Text(_statusLabel,
                                style: TextStyle(
                                    color: _statusColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

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
                                        fontWeight:
                                            FontWeight.bold)),
                                if (widget.etaPickupMin != null &&
                                    _status == 'ACCEPTED')
                                  Text(
                                      'Arrivée dans ~${widget.etaPickupMin} min',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12)),
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
                      ]),

                      if (_status == 'DELIVERED' && !_rated) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _showRatingDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF00C853),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: const Text('Noter le livreur',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
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
