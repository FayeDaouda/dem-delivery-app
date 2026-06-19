import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/map_theme_provider.dart';
import '../home_driver/navigation/map_theme.dart';
import 'providers/guest_order_state_provider.dart';
import 'providers/order_state.dart';

class GuestTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;

  const GuestTrackingScreen({super.key, required this.orderId});

  @override
  ConsumerState<GuestTrackingScreen> createState() => _GuestTrackingScreenState();
}

class _GuestTrackingScreenState extends ConsumerState<GuestTrackingScreen> {
  GoogleMapController? _mapController;
  String? _mapStyle;
  List<LatLng> _routePoints = [];
  List<LatLng> _displayRoute = [];
  int _lastTrimIdx = 0;
  bool _isRerouting = false;

  BitmapDescriptor? _driverMarkerIcon;
  double _driverHeading = 0;
  LatLng? _prevDriverLocation;

  bool _autoFollow = true;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _buildDriverMarkerIcon().then((icon) {
      if (mounted) setState(() => _driverMarkerIcon = icon);
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final bool isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  static Future<BitmapDescriptor> _buildDriverMarkerIcon() async {
    const double size = 120;
    const double cx = size / 2;
    const double cy = size / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(const Offset(cx, cy), 56, Paint()..color = const Color(0x18FF6B00));
    canvas.drawCircle(const Offset(cx, cy), 42, Paint()..color = const Color(0x30FF6B00));

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

    canvas.drawCircle(const Offset(cx, cy + 4), 22, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(cx, cy + 4), 20, Paint()..color = const Color(0xFFFF6B00));

    final arrowPath = Path()
      ..moveTo(cx, cy - 26)
      ..lineTo(cx + 16, cy + 13)
      ..lineTo(cx, cy + 7)
      ..lineTo(cx - 16, cy + 13)
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
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 54, height: 54);
  }

  static double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

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
    if (_routePoints.isEmpty) return;
    final idx = _closestPointIdx(_routePoints, driverLoc, _lastTrimIdx);
    if (idx == _lastTrimIdx && _displayRoute.isNotEmpty) return;
    _lastTrimIdx = idx;
    if (mounted) setState(() => _displayRoute = _routePoints.sublist(idx));
  }

  Future<void> _fetchRoute(ClientOrderState s) async {
    if (_isRerouting) return;
    final order = s.orderData;
    if (order == null) return;
    _isRerouting = true;

    final pickupLat = (order['pickupLatitude'] as num?)?.toDouble();
    final pickupLng = (order['pickupLongitude'] as num?)?.toDouble();
    final delivLat = (order['deliveryLatitude'] as num?)?.toDouble();
    final delivLng = (order['deliveryLongitude'] as num?)?.toDouble();
    if (pickupLat == null || pickupLng == null || delivLat == null || delivLng == null) {
      _isRerouting = false;
      return;
    }

    final driverLoc = s.driverLocation;
    final double oLat, oLng, dLat, dLng;
    if (s.phase == 'ACCEPTED' && driverLoc != null) {
      oLat = driverLoc.latitude; oLng = driverLoc.longitude;
      dLat = pickupLat; dLng = pickupLng;
    } else if (s.phase == 'PICKED_UP' || s.phase == 'IN_TRANSIT') {
      oLat = driverLoc?.latitude ?? pickupLat;
      oLng = driverLoc?.longitude ?? pickupLng;
      dLat = delivLat; dLng = delivLng;
    } else {
      oLat = pickupLat; oLng = pickupLng;
      dLat = delivLat; dLng = delivLng;
    }

    try {
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
      final res = await dio.get(
        'https://router.project-osrm.org/route/v1/driving/$oLng,$oLat;$dLng,$dLat?overview=full&geometries=geojson',
      );
      if (res.statusCode == 200 && (res.data['routes'] as List?)?.isNotEmpty == true) {
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

  Future<void> _callDriver(Map<String, dynamic>? driver) async {
    final phone = driver?['phone'] as String?;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(guestOrderStateProvider(widget.orderId));
    final order = s.orderData;

    if (s.isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (order == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text("Commande introuvable")),
      );
    }

    if (s.phase == 'CANCELLED') {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cancel, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                'Ce lien n\'est plus actif',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              const Text('Téléchargez l\'application DEM !', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final pickupLat = (order['pickupLatitude'] as num?)?.toDouble() ?? 0.0;
    final pickupLng = (order['pickupLongitude'] as num?)?.toDouble() ?? 0.0;
    final deliveryLat = (order['deliveryLatitude'] as num?)?.toDouble() ?? 0.0;
    final deliveryLng = (order['deliveryLongitude'] as num?)?.toDouble() ?? 0.0;
    
    LatLng center = LatLng(pickupLat, pickupLng);
    if (s.driverLocation != null) {
      center = s.driverLocation!;
    }

    // Gestion cap
    if (s.driverLocation != null && _prevDriverLocation != null) {
      if (s.driverLocation!.latitude != _prevDriverLocation!.latitude ||
          s.driverLocation!.longitude != _prevDriverLocation!.longitude) {
        _driverHeading = _calculateBearing(_prevDriverLocation!, s.driverLocation!);
        _prevDriverLocation = s.driverLocation;
        _updateDisplayRoute(s.driverLocation!);
        if (_routePoints.isEmpty && !_isRerouting) _fetchRoute(s);
      }
    } else if (s.driverLocation != null) {
      _prevDriverLocation = s.driverLocation;
      if (_routePoints.isEmpty && !_isRerouting) _fetchRoute(s);
    }

    if (_autoFollow && _mapController != null && s.driverLocation != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: s.driverLocation!,
            zoom: 17,
            tilt: 45,
            bearing: _driverHeading,
          ),
        ),
      );
    }

    final driver = order['driver'] as Map<String, dynamic>?;
    final isDelivery = order['orderType'] == 'DELIVERY';
    
    final pickupAddress = order['pickupAddress'] as String? ?? 'Point de départ';
    final deliveryAddress = order['deliveryAddress'] as String? ?? 'Point d\'arrivée';
    final price = order['price']?.toString() ?? '-';

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            style: _mapStyle,
            compassEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            onMapCreated: (c) {
              _mapController = c;
              if (_routePoints.isEmpty) _fetchRoute(s);
            },
            onCameraMoveStarted: () => setState(() => _autoFollow = false),
            polylines: {
              if (_displayRoute.isNotEmpty)
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: _displayRoute,
                  color: AppColors.primary,
                  width: 5,
                  jointType: JointType.round,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                ),
            },
            markers: {
              Marker(
                markerId: const MarkerId('pickup'),
                position: LatLng(pickupLat, pickupLng),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
              ),
              Marker(
                markerId: const MarkerId('delivery'),
                position: LatLng(deliveryLat, deliveryLng),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              ),
              if (s.driverLocation != null && _driverMarkerIcon != null)
                Marker(
                  markerId: const MarkerId('driver'),
                  position: s.driverLocation!,
                  icon: _driverMarkerIcon!,
                  rotation: _driverHeading,
                  anchor: const Offset(0.5, 0.5),
                  flat: true,
                ),
            },
          ),
          
          // Header / Recenter
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/client/home');
                          }
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
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: const Row(
                          children: [
                            Icon(Icons.remove_red_eye, color: AppColors.primary, size: 18),
                            SizedBox(width: 8),
                            Text('Mode Invité', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!_autoFollow)
                    FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: () => setState(() => _autoFollow = true),
                      child: const Icon(Icons.my_location, color: AppColors.primary),
                    ),
                ],
              ),
            ),
          ),

          // Bottom Sheet
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              decoration: BoxDecoration(
                gradient: AppColors.gradientSplash,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.phase == 'DELIVERED')
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                          child: const Icon(Icons.two_wheeler, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.phase == 'ACCEPTED' ? (isDelivery ? 'Livreur en route' : 'Chauffeur en route') : 'En route vers la destination',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              if (s.etaMin != null) ...[
                                const SizedBox(height: 4),
                                Text('Arrive dans environ ${s.etaMin} min', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (driver != null) ...[
                      Divider(height: 24, color: Colors.white.withValues(alpha: 0.3)),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            backgroundImage: driver['avatar'] != null ? NetworkImage(driver['avatar']!) : null,
                            child: driver['avatar'] == null ? const Icon(Icons.person, color: Colors.white) : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(driver['name'] ?? 'Livreur', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                if (driver['vehiclePlate'] != null)
                                  Text(driver['vehiclePlate']!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ),
                          if (driver['phone'] != null)
                            GestureDetector(
                              onTap: () => _callDriver(driver),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(color: Color(0xFF00C853), shape: BoxShape.circle),
                                child: const Icon(Icons.phone, color: Colors.white, size: 20),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                  
                  const SizedBox(height: 16),
                  
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
                              color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        _RouteRow(
                            icon: Icons.location_on,
                            color: AppColors.error,
                            text: deliveryAddress),
                      ],
                    ),
                  ),
                ],
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
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}
