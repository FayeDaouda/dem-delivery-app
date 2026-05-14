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

import '../../core/notifications/notification_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/map_theme_provider.dart';
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
  List<LatLng> _displayRoute = [];
  int _lastTrimIdx = 0;

  BitmapDescriptor? _driverMarkerIcon;
  double _driverHeading = 0;
  LatLng? _prevDriverLocation;

  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _driverLocationSub;
  LatLng? _driverLocation;
  Timer? _pollTimer;
  Timer? _routeRefreshTimer;
  DateTime? _lastNotifUpdate; // throttle notifications persistantes

  // Autres commandes actives du client (multi-commandes)
  List<Map<String, dynamic>> _otherActiveOrders = [];

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchOrder();
    _connectSocket();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _fetchOrder());
    _buildDriverMarkerIcon().then((icon) {
      if (mounted) setState(() => _driverMarkerIcon = icon);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _driverLocationSub?.cancel();
    _pollTimer?.cancel();
    _routeRefreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
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

  void _updateDisplayRoute() {
    if (_routePoints.isEmpty || _driverLocation == null) {
      if (_routePoints.isNotEmpty) setState(() => _displayRoute = _routePoints);
      return;
    }
    // Les deux phases : la route part toujours de la position du driver → on coupe le début parcouru
    final idx = _closestPointIdx(_routePoints, _driverLocation!, _lastTrimIdx);
    if (idx == _lastTrimIdx && _displayRoute.isNotEmpty) return;
    _lastTrimIdx = idx;
    if (mounted) setState(() => _displayRoute = _routePoints.sublist(idx));
  }

  Future<void> _fetchOrder() async {
    try {
      final repo = ref.read(ordersRepositoryProvider);
      // Charge la commande courante + toutes les commandes pour le multi-suivi
      final results = await Future.wait([
        repo.getOrderById(widget.orderId),
        repo.getMyOrders(),
      ]);
      if (!mounted) return;

      final order = results[0] as Map<String, dynamic>;
      final allOrders = results[1] as List<Map<String, dynamic>>;
      final newStatus = order['status'] as String? ?? _status;

      const activeStatuses = ['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'];
      final others = allOrders.where((o) {
        final s = (o['status'] as String? ?? '').toUpperCase();
        return activeStatuses.contains(s) && o['id'] != widget.orderId;
      }).toList();

      final prevStatus = _status;
      setState(() {
        _order = order;
        _status = newStatus;
        _loading = false;
        _otherActiveOrders = others;
      });

      // Re-fetch route si le statut a changé (ACCEPTED → PICKED_UP)
      if (prevStatus != newStatus || _routePoints.isEmpty) _fetchRoute();

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
    final pickupLat  = (order['pickupLatitude']   as num?)?.toDouble();
    final pickupLng  = (order['pickupLongitude']  as num?)?.toDouble();
    final delivLat   = (order['deliveryLatitude'] as num?)?.toDouble();
    final delivLng   = (order['deliveryLongitude'] as num?)?.toDouble();
    if (pickupLat == null || pickupLng == null || delivLat == null || delivLng == null) return;

    // Route selon la phase :
    //  ACCEPTED  → driver → pickup
    //  PICKED_UP → driver (ou pickup) → delivery
    //  autre     → pickup → delivery (preview)
    final double oLat, oLng, dLat, dLng;
    if (_status == 'ACCEPTED' && _driverLocation != null) {
      oLat = _driverLocation!.latitude;  oLng = _driverLocation!.longitude;
      dLat = pickupLat;                  dLng = pickupLng;
    } else if (_status == 'PICKED_UP') {
      oLat = _driverLocation?.latitude  ?? pickupLat;
      oLng = _driverLocation?.longitude ?? pickupLng;
      dLat = delivLat;                   dLng = delivLng;
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
            _lastTrimIdx  = 0;
          });
          _updateDisplayRoute();
        }
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
      // Changement de phase → recalcule la route (driver→delivery au lieu de driver→pickup)
      _fetchRoute();
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
      final newLoc = LatLng(lat, lng);

      // Cap : calculé depuis la position précédente
      if (_prevDriverLocation != null) {
        final bearing = _calculateBearing(_prevDriverLocation!, newLoc);
        setState(() { _driverLocation = newLoc; _driverHeading = bearing; });
      } else {
        setState(() => _driverLocation = newLoc);
      }
      _prevDriverLocation = newLoc;

      // Rétrécissement en temps réel
      _updateDisplayRoute();

      // Recalcul si déviation > 70m depuis la route (ACCEPTED et PICKED_UP)
      if (_routePoints.isNotEmpty &&
          (_status == 'ACCEPTED' || _status == 'PICKED_UP')) {
        double minDist = double.infinity;
        final end = (_lastTrimIdx + 60).clamp(0, _routePoints.length);
        for (int i = _lastTrimIdx; i < end; i++) {
          final d = Geolocator.distanceBetween(
              lat, lng, _routePoints[i].latitude, _routePoints[i].longitude);
          if (d < minDist) minDist = d;
        }
        if (minDist > 70) _fetchRoute();
      }

      // Caméra suit le driver
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: newLoc, zoom: 17, tilt: 55)));

      // Notification persistante avec ETA estimé
      final isPickedUp = _status == 'PICKED_UP';
      final targetLat = isPickedUp
          ? (_order?['deliveryLatitude']  as num?)?.toDouble()
          : (_order?['pickupLatitude']    as num?)?.toDouble();
      final targetLng2 = isPickedUp
          ? (_order?['deliveryLongitude'] as num?)?.toDouble()
          : (_order?['pickupLongitude']   as num?)?.toDouble();
      final targetName = isPickedUp
          ? (_order?['deliveryAddress']?.toString() ?? 'Destination')
          : (_order?['pickupAddress']?.toString()   ?? 'Pickup');

      if (targetLat != null && targetLng2 != null) {
        final now = DateTime.now();
        // Throttle : mise à jour max toutes les 60 secondes
        if (_lastNotifUpdate == null ||
            now.difference(_lastNotifUpdate!).inSeconds >= 60) {
          _lastNotifUpdate = now;
          final dist = Geolocator.distanceBetween(lat, lng, targetLat, targetLng2);
          final min = (dist / 416).round();
          final etaText = min > 0 ? ' (~$min min)' : ' (Proche)';
          final statusText = isPickedUp
              ? 'Le livreur est en route vers vous'
              : 'Le livreur récupère votre commande';
          NotificationService.showOngoingNotification(
            id: 8888, title: statusText, body: '$targetName$etaText',
          );
        }
      }
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

  bool get _isDelivery => (_order?['orderType'] as String?) == 'DELIVERY';

  String get _statusLabel => switch (_status) {
        'ACCEPTED' => _isDelivery
            ? 'Livreur en route pour récupérer votre colis'
            : 'Chauffeur en route vers vous',
        'PICKED_UP' => _isDelivery
            ? 'Colis pris en charge — en route'
            : 'En route vers la destination',
        'DELIVERED' => _isDelivery ? 'Colis livré ✓' : 'Arrivée effectuée ✓',
        _ => 'Commande en cours',
      };

  IconData get _statusIcon => switch (_status) {
        'ACCEPTED' => _isDelivery ? Icons.inventory_2_outlined : Icons.directions_bike,
        'PICKED_UP' => Icons.two_wheeler,
        'DELIVERED' => Icons.check_circle,
        _ => Icons.access_time,
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
    final driverRating = (driverMap?['averageRating'] as num?)?.toDouble();
    final pickupAddress = order?['pickupAddress'] as String? ?? '';
    final deliveryAddress = order?['deliveryAddress'] as String? ?? '';
    final price = (order?['price'] as num?)?.toInt() ?? 0;

    // Fallback : dernière position connue du driver depuis l'API si socket pas encore reçu
    final driverLat = _driverLocation?.latitude
        ?? (order?['driver'] as Map?)?['lastLatitude'] as double?
        ?? (order?['driverLatitude'] as num?)?.toDouble();
    final driverLng = _driverLocation?.longitude
        ?? (order?['driver'] as Map?)?['lastLongitude'] as double?
        ?? (order?['driverLongitude'] as num?)?.toDouble();
    final effectiveDriverLoc = (driverLat != null && driverLng != null)
        ? LatLng(driverLat, driverLng) : null;

    final markers = <Marker>{
      // Pickup : visible seulement avant prise en charge
      if (pickupLat != null && pickupLng != null && _status == 'ACCEPTED')
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
                    if (_otherActiveOrders.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _otherActiveOrders.map((o) {
                              final idx = _otherActiveOrders.indexOf(o) + 2;
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
                                      if (widget.etaPickupMin != null && _status == 'ACCEPTED')
                                        const Text(' · ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                    ],
                                    if (widget.etaPickupMin != null && _status == 'ACCEPTED')
                                      Text('${widget.etaPickupMin} min',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
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
