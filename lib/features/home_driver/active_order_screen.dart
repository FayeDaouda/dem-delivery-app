import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import 'navigation/map_theme.dart';
import '../deliveries/providers/orders_provider.dart';
import 'navigation/alert_manager.dart';
import 'navigation/directions_service.dart';
import 'navigation/navigation_service.dart';

class ActiveOrderScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  const ActiveOrderScreen({super.key, required this.order});

  @override
  ConsumerState<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends ConsumerState<ActiveOrderScreen> {
  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;

  // ── Commande ─────────────────────────────────────────────────────────────
  late Map<String, dynamic> _order;

  // ── GPS ──────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _driverPosition;
  bool _autoFollow = true;

  // ── Route ─────────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  bool _loadingRoute = true;
  int? _etaSeconds;

  // ── Alertes ───────────────────────────────────────────────────────────────
  final _alertManager = AlertManager();
  String? _currentAlert;
  AlertPriority? _alertPriority;
  Timer? _alertTimer;

  // ── Getters ───────────────────────────────────────────────────────────────
  LatLng get _pickupLatLng => LatLng(
        (_order['pickupLatitude'] as num).toDouble(),
        (_order['pickupLongitude'] as num).toDouble(),
      );

  LatLng get _deliveryLatLng => LatLng(
        (_order['deliveryLatitude'] as num).toDouble(),
        (_order['deliveryLongitude'] as num).toDouble(),
      );

  bool get _isPickedUp => _order['status'] == 'PICKED_UP';
  bool get _isDelivered => _order['status'] == 'DELIVERED';

  LatLng get _targetLatLng => _isPickedUp ? _deliveryLatLng : _pickupLatLng;

  double? get _distanceToTarget => _driverPosition == null
      ? null
      : NavigationService.distanceTo(_driverPosition!, _targetLatLng);

  BitmapDescriptor? _driverIcon;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _buildDriverIcon().then((icon) {
      if (mounted) setState(() => _driverIcon = icon);
    });
    _startNavigation();
  }

  static Future<BitmapDescriptor> _buildDriverIcon() async {
    const double size = 96;
    const double cx = size / 2, cy = size / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(cx, cy), 40,
      Paint()..color = const Color(0x4033BCD4),
    );
    final path = Path()
      ..moveTo(cx, cy - 18)
      ..lineTo(cx + 14.4, cy + 10.8)
      ..lineTo(cx - 14.4, cy + 10.8)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF33BCD4));
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 48, height: 48);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _alertTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  Future<void> _startNavigation() async {
    final style = await rootBundle.loadString(MapTheme.styleAsset);
    if (mounted) setState(() => _mapStyle = style);
    await _loadRoute();

    final initial = await NavigationService.requestAndGetPosition();
    if (initial != null && mounted) {
      setState(() => _driverPosition = initial);
    }

    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  Future<void> _loadRoute() async {
    // Phase 1 : driver → pickup | Phase 2 : pickup → delivery
    final origin = _isPickedUp
        ? _pickupLatLng
        : (_driverPosition != null
            ? LatLng(_driverPosition!.latitude, _driverPosition!.longitude)
            : _pickupLatLng);
    final destination = _isPickedUp ? _deliveryLatLng : _pickupLatLng;

    final result = await DirectionsService.getRoute(
      origin: origin,
      destination: destination,
      apiKey: AppConfig.mapsApiKey,
    );
    if (!mounted) return;
    setState(() {
      _routePoints = result.points;
      _etaSeconds = result.durationSeconds;
      _loadingRoute = false;
    });
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _driverPosition = position);

    // Auto-follow : caméra suit le driver avec cap + inclinaison Waze
    if (_autoFollow && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 17.5,
            bearing: position.heading,
            tilt: 55,
          ),
        ),
      );
    }

    // Alertes de proximité
    final dist = _distanceToTarget;
    if (dist != null) {
      final alert = _alertManager.check(dist, isPickupPhase: !_isPickedUp);
      if (alert != null) _showAlert(alert.message, alert.priority);
    }
  }

  void _recenter() {
    if (_driverPosition == null) return;
    setState(() => _autoFollow = true);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
          zoom: 17.5,
          bearing: _driverPosition!.heading,
          tilt: 55,
        ),
      ),
    );
  }

  void _fitBounds() {
    final bounds = LatLngBounds(
      southwest: LatLng(
        [_pickupLatLng.latitude, _deliveryLatLng.latitude]
            .reduce((a, b) => a < b ? a : b),
        [_pickupLatLng.longitude, _deliveryLatLng.longitude]
            .reduce((a, b) => a < b ? a : b),
      ),
      northeast: LatLng(
        [_pickupLatLng.latitude, _deliveryLatLng.latitude]
            .reduce((a, b) => a > b ? a : b),
        [_pickupLatLng.longitude, _deliveryLatLng.longitude]
            .reduce((a, b) => a > b ? a : b),
      ),
    );
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  // ── Alertes visuelles ─────────────────────────────────────────────────────
  void _showAlert(String message, AlertPriority priority) {
    _alertTimer?.cancel();
    setState(() {
      _currentAlert = message;
      _alertPriority = priority;
    });
    _alertTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _currentAlert = null);
    });
  }

  // ── Actions commande ──────────────────────────────────────────────────────
  Future<void> _pickup() async {
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final updated = await repo.pickupOrder(_order['id']);
      setState(() => _order = updated);
      await _loadRoute(); // recharge la route depuis pickup → delivery
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deliver() async {
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final updated = await repo.deliverOrder(_order['id']);
      setState(() => _order = updated);
      if (mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _showSuccessDialog() {
    final price = (_order['price'] as num?)?.toInt() ?? 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFF00C853),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              const Text('Livraison effectuée !',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('$price FCFA encaissés',
                  style: const TextStyle(fontSize: 15, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(_order['deliveryAddress'] ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/driver/home');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Retour à l\'accueil',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Carte : marqueurs ─────────────────────────────────────────────────────
  Set<Marker> get _markers {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow:
            InfoWindow(title: 'Collecte', snippet: _order['pickupAddress']),
      ),
      Marker(
        markerId: const MarkerId('delivery'),
        position: _deliveryLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
            title: 'Livraison', snippet: _order['deliveryAddress']),
      ),
    };

    // Marqueur driver (point bleu plat, tourne avec le cap)
    if (_driverPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position:
              LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
          icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          rotation: _driverPosition!.heading,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 2,
        ),
      );
    }

    return markers;
  }

  // ── Carte : polylines ─────────────────────────────────────────────────────
  Set<Polyline> get _polylines {
    if (_routePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints,
        color: MapTheme.routeColor,
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Carte ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: _pickupLatLng, zoom: 13),
              style: _mapStyle,
              onMapCreated: (controller) {
                _mapController = controller;
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (_driverPosition != null && _autoFollow) {
                    _recenter();
                  } else {
                    _fitBounds();
                  }
                });
              },
              onCameraMove: (_) {
                // L'utilisateur a bougé la carte → pause auto-follow
                if (_autoFollow) setState(() => _autoFollow = false);
              },
              polylines: _polylines,
              markers: _markers,
              trafficEnabled: true,       // couche trafic en temps réel
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
            ),
          ),

          // ── Bannière d'alerte (glisse depuis le haut) ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            top: _currentAlert != null ? 0 : -120,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _currentAlert != null
                  ? _AlertBanner(
                      message: _currentAlert!,
                      priority: _alertPriority ?? AlertPriority.low,
                    )
                  : const SizedBox.shrink(),
            ),
          ),

          // ── Bouton retour ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_currentAlert == null) // masqué quand alerte visible
                    GestureDetector(
                      onTap: () => context.go('/driver/home'),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                            )
                          ],
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.black87, size: 20),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Bouton re-centrer (visible quand autoFollow désactivé) ──
          if (!_autoFollow && _driverPosition != null)
            Positioned(
              right: 16,
              bottom: 230,
              child: GestureDetector(
                onTap: _recenter,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: const Icon(Icons.my_location,
                      color: AppColors.primary, size: 22),
                ),
              ),
            ),

          // ── Feuille infos bas ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Phase + distance en temps réel
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PhaseChip(
                              isPickedUp: _isPickedUp,
                              isDelivered: _isDelivered,
                            ),
                            const SizedBox(height: 6),
                            // Distance en gros (style Waze)
                            if (_distanceToTarget != null && !_isDelivered)
                              Text(
                                NavigationService.formatDistance(
                                    _distanceToTarget!),
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                  height: 1,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // ETA
                      if (_etaSeconds != null && !_isDelivered)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                NavigationService.formatDuration(_etaSeconds!),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              const Text(
                                'ETA',
                                style: TextStyle(
                                    fontSize: 10, color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  if (_loadingRoute)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: LinearProgressIndicator(
                        color: AppColors.primary,
                        backgroundColor: Color(0xFFE0E0E0),
                        minHeight: 2,
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Adresses
                  _AddressRow(
                    icon: Icons.circle,
                    iconColor: const Color(0xFF00C853),
                    label: 'Collecte',
                    address: _order['pickupAddress'] ?? '',
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 9),
                    child: SizedBox(
                      height: 12,
                      child: VerticalDivider(
                          color: Color(0xFFBDBDBD), thickness: 1.5),
                    ),
                  ),
                  _AddressRow(
                    icon: Icons.location_on,
                    iconColor: Colors.red,
                    label: 'Livraison',
                    address: _order['deliveryAddress'] ?? '',
                  ),

                  const SizedBox(height: 12),

                  // Prix
                  Row(
                    children: [
                      const Icon(Icons.payments_outlined,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        '${((_order['price'] as num?)?.toInt() ?? 0)} FCFA',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Bouton action
                  if (!_isDelivered)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isPickedUp ? _deliver : _pickup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isPickedUp
                              ? AppColors.primary
                              : const Color(0xFF00C853),
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          _isPickedUp
                              ? 'Livraison effectuée'
                              : "J'ai récupéré le colis",
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                  if (_isDelivered)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF00C853).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'Commande livrée avec succès !',
                          style: TextStyle(
                            color: Color(0xFF00C853),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

// ── Widgets privés ────────────────────────────────────────────────────────────

class _PhaseChip extends StatelessWidget {
  final bool isPickedUp;
  final bool isDelivered;

  const _PhaseChip({required this.isPickedUp, required this.isDelivered});

  @override
  Widget build(BuildContext context) {
    final (label, color) = isDelivered
        ? ('Livraison effectuée ✓', const Color(0xFF00C853))
        : isPickedUp
            ? ('En route vers la livraison', AppColors.primary)
            : ('En route vers le pickup', Colors.orange);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final String message;
  final AlertPriority priority;

  const _AlertBanner({required this.message, required this.priority});

  Color get _color => switch (priority) {
        AlertPriority.low => Colors.blue.shade700,
        AlertPriority.medium => Colors.orange.shade700,
        AlertPriority.high => const Color(0xFF00C853),
      };

  IconData get _icon => switch (priority) {
        AlertPriority.low => Icons.info_outline,
        AlertPriority.medium => Icons.warning_amber_outlined,
        AlertPriority.high => Icons.check_circle_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        color: _color,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(_icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  const _AddressRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              Text(address,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}
