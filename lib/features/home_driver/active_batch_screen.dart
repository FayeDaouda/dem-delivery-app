import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error/app_exception.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/map_theme_provider.dart';
import '../../core/utils/dem_toast.dart';
import '../deliveries/providers/orders_provider.dart';
import 'navigation/map_theme.dart';
import 'navigation/navigation_service.dart';

const _dakarBatch = LatLng(14.6937, -17.4441);

class ActiveBatchScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> batch;
  const ActiveBatchScreen({super.key, required this.batch});

  @override
  ConsumerState<ActiveBatchScreen> createState() => _ActiveBatchScreenState();
}

class _ActiveBatchScreenState extends ConsumerState<ActiveBatchScreen>
    with WidgetsBindingObserver {
  // ── Map ───────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _driverIcon;

  // ── GPS ───────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _driverPosition;
  bool _autoFollow = true;
  DateTime? _lastLocationEmit;

  // ── Batch state ───────────────────────────────────────────────────────────
  late List<Map<String, dynamic>> _stops;
  bool _isPickedUp = false;
  int _currentStopIndex = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final orders = (widget.batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _stops = List.from(orders)
      ..sort((a, b) => ((a['sequenceIndex'] as num?) ?? 0)
          .compareTo((b['sequenceIndex'] as num?) ?? 0));
    _buildDriverIcon().then((icon) {
      if (mounted) setState(() => _driverIcon = icon);
    });
    _loadMapStyle();
    _startGPS();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  static Future<BitmapDescriptor> _buildDriverIcon() async {
    const double size = 96;
    const double cx = size / 2;
    const double cy = size / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(const Offset(cx, cy), 40,
        Paint()..color = const Color(0x4033BCD4));
    final path = Path()
      ..moveTo(cx, cy - 18)
      ..lineTo(cx + 14, cy + 10)
      ..lineTo(cx - 14, cy + 10)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF33BCD4));
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 48, height: 48);
  }

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _startGPS() async {
    final fresh = await NavigationService.requestAndGetPosition();
    if (!mounted) return;
    setState(() => _driverPosition = fresh);
    _centerOn(fresh);
    _locationSub = NavigationService.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _driverPosition = pos);
      if (_autoFollow) _centerOn(pos);
      _maybeEmitLocation(pos);
    });
  }

  void _maybeEmitLocation(Position pos) {
    final now = DateTime.now();
    if (_lastLocationEmit == null ||
        now.difference(_lastLocationEmit!).inSeconds >= 10) {
      _lastLocationEmit = now;
      ref.read(ordersRepositoryProvider).updateDriverLocation(
        pos.latitude, pos.longitude,
      ).catchError((_) {});
    }
  }

  void _centerOn(Position pos) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 15.5,
        ),
      ),
    );
  }

  LatLng get _targetLatLng {
    if (!_isPickedUp) {
      return LatLng(
        (widget.batch['pickupLatitude'] as num).toDouble(),
        (widget.batch['pickupLongitude'] as num).toDouble(),
      );
    }
    final stop = _stops[_currentStopIndex];
    final lat = stop['deliveryLatitude'] ?? stop['latitude'];
    final lng = stop['deliveryLongitude'] ?? stop['longitude'];
    return LatLng((lat as num).toDouble(), (lng as num).toDouble());
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    if (_driverPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
        icon: _driverIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
      ));
    }
    markers.add(Marker(
      markerId: const MarkerId('target'),
      position: _targetLatLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(
        _isPickedUp ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
      ),
      zIndexInt: 1,
    ));
    return markers;
  }

  void _fitToTarget() {
    if (_driverPosition == null) return;
    final target = _targetLatLng;
    final driver = LatLng(_driverPosition!.latitude, _driverPosition!.longitude);
    if ((driver.latitude - target.latitude).abs() < 0.0001 &&
        (driver.longitude - target.longitude).abs() < 0.0001) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(target, 16),
      );
      return;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(
        driver.latitude < target.latitude ? driver.latitude : target.latitude,
        driver.longitude < target.longitude ? driver.longitude : target.longitude,
      ),
      northeast: LatLng(
        driver.latitude > target.latitude ? driver.latitude : target.latitude,
        driver.longitude > target.longitude ? driver.longitude : target.longitude,
      ),
    );
    setState(() => _autoFollow = false);
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  Future<void> _confirmPickup() async {
    if (_stops.isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(ordersRepositoryProvider).pickupOrder(
            _stops[0]['id'] as String,
          );
      NotificationService.showOngoingNotification(
        id: 9998,
        title: 'Tournée en cours',
        body: 'Arrêt 1/${_stops.length} : ${_stops[0]['deliveryAddress'] ?? ''}',
      );
      setState(() {
        _isPickedUp = true;
        _currentStopIndex = 0;
      });
      _fitToTarget();
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDelivery() async {
    final stop = _stops[_currentStopIndex];
    setState(() => _loading = true);
    try {
      await ref.read(ordersRepositoryProvider).deliverOrder(
            stop['id'] as String,
          );
      if (_currentStopIndex < _stops.length - 1) {
        final next = _stops[_currentStopIndex + 1];
        NotificationService.showOngoingNotification(
          id: 9998,
          title: 'Tournée en cours',
          body:
              'Arrêt ${_currentStopIndex + 2}/${_stops.length} : ${next['deliveryAddress'] ?? ''}',
        );
        setState(() {
          _currentStopIndex++;
          _autoFollow = true;
        });
        _fitToTarget();
      } else {
        NotificationService.cancelNotification(9998);
        if (mounted) _showCompletionDialog();
      }
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF0C1628),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Color(0xFF00E08C), size: 28),
          SizedBox(width: 10),
          Text(
            'Tournée terminée !',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
        content: Text(
          'Tous les ${_stops.length} arrêts ont été livrés avec succès.',
          style:
              const TextStyle(color: Color(0xFF6B8BAA), fontSize: 14, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/driver/home');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00AECB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Retour à l'accueil"),
          ),
        ],
      ),
    );
  }

  Future<void> _openMaps() async {
    final t = _targetLatLng;
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${t.latitude},${t.longitude}&travelmode=two-wheeler');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _callReceiver() {
    if (!_isPickedUp || _currentStopIndex >= _stops.length) return;
    final phone = _stops[_currentStopIndex]['receiverPhone'] as String?;
    if (phone == null || phone.isEmpty) return;
    launchUrl(Uri.parse('tel:$phone'));
  }

  void _callClient() {
    final phone = widget.batch['clientPhone'] as String?
        ?? (widget.batch['client'] as Map?)?['phone'] as String?;
    if (phone == null || phone.isEmpty) return;
    launchUrl(Uri.parse('tel:$phone'));
  }

  String? get _clientPhone =>
      widget.batch['clientPhone'] as String?
      ?? (widget.batch['client'] as Map?)?['phone'] as String?;

  String? get _clientName =>
      widget.batch['clientName'] as String?
      ?? (widget.batch['client'] as Map?)?['name'] as String?;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // ── Carte ─────────────────────────────────────────────────────────
        SizedBox.expand(
          child: GoogleMap(
            initialCameraPosition:
                const CameraPosition(target: _dakarBatch, zoom: 14),
            onMapCreated: (c) {
              _mapController = c;
              if (_driverPosition != null) _centerOn(_driverPosition!);
            },
            style: _mapStyle,
            markers: _markers,
            onCameraMove: (_) {
              if (_autoFollow) setState(() => _autoFollow = false);
            },
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            trafficEnabled: false,
          ),
        ),

        // ── Header ────────────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              // Progress badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8)
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.route, color: Color(0xFF00AECB), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _isPickedUp
                        ? 'Arrêt ${_currentStopIndex + 1} / ${_stops.length}'
                        : 'Récupération',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
              const Spacer(),
              // Recenter button when camera drifted
              if (!_autoFollow)
                GestureDetector(
                  onTap: () {
                    setState(() => _autoFollow = true);
                    if (_driverPosition != null) _centerOn(_driverPosition!);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8)
                      ],
                    ),
                    child: const Icon(Icons.my_location,
                        color: Color(0xFF00AECB), size: 22),
                  ),
                ),
            ]),
          ),
        ),

        // ── Stop progress dots (when picked up) ───────────────────────────
        if (_isPickedUp)
          Positioned(
            top: MediaQuery.of(context).padding.top + 72,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_stops.length, (i) {
                final done = i < _currentStopIndex;
                final current = i == _currentStopIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: current ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: done
                        ? const Color(0xFF00E08C)
                        : current
                            ? const Color(0xFF00AECB)
                            : Colors.white.withValues(alpha: 0.35),
                  ),
                );
              }),
            ),
          ),

        // ── Bottom sheet ──────────────────────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomSheet(),
        ),
      ]),
    );
  }

  Widget _buildBottomSheet() {
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
                color: Colors.white.withValues(alpha: 0.15), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 32,
                offset: const Offset(0, -4),
              )
            ],
          ),
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).viewPadding.bottom + 24),
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
              if (!_isPickedUp)
                ..._buildPickupContent()
              else
                ..._buildDeliveryContent(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPickupContent() {
    final address = widget.batch['pickupAddress'] as String? ?? '';
    return [
      Row(children: [
        const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Récupérer les colis',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  '${_stops.length} arrêt${_stops.length > 1 ? 's' : ''} à livrer',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ]),
        ),
        _MapBtn(onTap: _openMaps),
        if (_clientPhone != null && _clientPhone!.isNotEmpty) ...[
          const SizedBox(width: 8),
          _MapBtn(onTap: _callClient, icon: Icons.phone_outlined),
        ],
      ]),
      const SizedBox(height: 14),
      _AddressCard(
        icon: Icons.circle,
        label: 'Point de départ',
        address: address,
        receiverName: _clientName,
      ),
      if (_clientPhone != null && _clientPhone!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: GestureDetector(
            onTap: _callClient,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.person_outline, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                if (_clientName != null) ...[
                  Text(_clientName!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                ],
                Text(_clientPhone!, style: const TextStyle(color: Color(0xFF00AECB), fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Icon(Icons.phone_outlined, color: Color(0xFF00AECB), size: 16),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 14),
      _ActionButton(
        onTap: _loading ? null : _confirmPickup,
        loading: _loading,
        label: 'Colis récupérés',
        color: Colors.white,
        textColor: const Color(0xFF0671BA),
      ),
    ];
  }

  List<Widget> _buildDeliveryContent() {
    final stop = _stops[_currentStopIndex];
    final isLastStop = _currentStopIndex == _stops.length - 1;
    final receiverName = stop['receiverName'] as String?;
    final receiverPhone = stop['receiverPhone'] as String?;
    final price = (stop['price'] as num?)?.toInt() ?? 0;
    final address = stop['deliveryAddress'] as String? ?? '';
    final landmark = stop['landmark'] as String?;

    return [
      Row(children: [
        // Stop number badge
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF00AECB).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF00AECB).withValues(alpha: 0.4)),
          ),
          child: Center(
            child: Text(
              '${_currentStopIndex + 1}',
              style: const TextStyle(
                  color: Color(0xFF00AECB),
                  fontSize: 16,
                  fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Arrêt ${_currentStopIndex + 1} sur ${_stops.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                if (price > 0)
                  Text(
                    '$price FCFA',
                    style: const TextStyle(
                        color: Color(0xFF00AECB),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
              ]),
        ),
        _MapBtn(onTap: _openMaps),
        if (receiverPhone != null && receiverPhone.isNotEmpty) ...[
          const SizedBox(width: 8),
          _MapBtn(
            onTap: _callReceiver,
            icon: Icons.phone_outlined,
          ),
        ],
      ]),
      const SizedBox(height: 14),
      _AddressCard(
        icon: Icons.location_on,
        label: 'Livraison',
        address: address,
        sub: landmark,
        receiverName: receiverName,
      ),
      if (receiverPhone != null && receiverPhone.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: GestureDetector(
            onTap: _callReceiver,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.person_outline, color: Colors.white70, size: 16),
                const SizedBox(width: 8),
                if (receiverName != null && receiverName.isNotEmpty) ...[
                  Text(receiverName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                ],
                Text(receiverPhone, style: const TextStyle(color: Color(0xFF00AECB), fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Icon(Icons.phone_outlined, color: Color(0xFF00AECB), size: 16),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 14),
      _ActionButton(
        onTap: _loading ? null : _confirmDelivery,
        loading: _loading,
        label: isLastStop ? 'Dernière livraison ✓' : 'Livré — Arrêt suivant →',
        color: isLastStop ? const Color(0xFF00E08C) : Colors.white,
        textColor:
            isLastStop ? Colors.white : const Color(0xFF0671BA),
      ),
    ];
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  const _MapBtn({required this.onTap, this.icon = Icons.navigation_outlined});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.8),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String address;
  final String? sub;
  final String? receiverName;
  const _AddressCard({
    required this.icon,
    required this.label,
    required this.address,
    this.sub,
    this.receiverName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(icon, color: Colors.black87, size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3)),
                    Text(address,
                        style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (sub != null && sub!.isNotEmpty)
                      Text(sub!,
                          style: const TextStyle(
                              color: Colors.black45, fontSize: 11)),
                  ]),
            ),
          ]),
          if (receiverName != null && receiverName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.black12, height: 1),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.person_outline, color: Colors.black45, size: 14),
              const SizedBox(width: 8),
              Text(receiverName!,
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ]),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool loading;
  final String label;
  final Color color;
  final Color textColor;
  const _ActionButton({
    required this.onTap,
    required this.loading,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: onTap == null ? color.withValues(alpha: 0.5) : color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: textColor),
                  )
                : Text(
                    label,
                    style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }
}
