import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import '../../core/error/app_exception.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../shared/widgets/map_theme_toggle_button.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/swipe_to_confirm.dart';

import '../../core/router/app_startup_notifier.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../deliveries/providers/orders_provider.dart';
import '../../core/theme/map_theme_provider.dart';
import '../home_driver/navigation/map_theme.dart';

const _kBatchAccent = Color(0xFF0C7A5C);

// Une moto fictive — identique à order_confirmation_screen.dart. `lastEnd`
// sert de point de départ au tronçon suivant, pour un déplacement continu.
class _DecoyMoto {
  LatLng lastEnd;
  List<LatLng> route = [];
  List<double> cumDist = [];
  double totalDist = 0;
  double bearing = 0;
  AnimationController? ctrl;
  _DecoyMoto(this.lastEnd);
}

/// Affichée après la création d'une tournée groupée — pendant du
/// OrderConfirmationScreen pour la livraison simple/Express (même radar,
/// mêmes motos fictives, même carte), adaptée à plusieurs arrêts au lieu
/// d'un seul point de livraison. Reçoit l'objet `batch` retourné par le
/// backend (avec `orders`, un par arrêt).
class BatchConfirmationScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> batch;
  const BatchConfirmationScreen({super.key, required this.batch});

  @override
  ConsumerState<BatchConfirmationScreen> createState() =>
      _BatchConfirmationScreenState();
}

class _BatchConfirmationScreenState
    extends ConsumerState<BatchConfirmationScreen>
    with TickerProviderStateMixin {
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

  List<Map<String, dynamic>> get _stops =>
      (widget.batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  // Hauteur du panneau ajustée au contenu réel — contrairement à la
  // livraison simple (toujours 2 adresses), une tournée a 2 à 3 arrêts : la
  // carte récap grandit avec leur nombre. Même principe que
  // order_confirmation_screen.dart (_kMaxContent), formule adaptée.
  double get _kMaxContent {
    final demFee = (widget.batch['demFee'] as num?)?.toDouble() ?? 0.0;
    final stopsExtra = _stops.length * 34.0; // ~34px par ligne d'arrêt
    return (_waitTimedOut ? 370.0 : 300.0) +
        (demFee > 0 ? 21 : 0) +
        stopsExtra +
        _bottomInset;
  }

  static const double _kMinContent = 64.0;
  double get _bottomInset => MediaQuery.of(context).viewPadding.bottom;

  // Animation radar
  late final AnimationController _radarCtrl;
  late final Animation<double> _radarAnim;

  // ── Motos fictives — identique à order_confirmation_screen.dart ──────────
  static const _kDecoyCount = 4;
  static const _kDecoyRadiusM = 1800.0;
  static const _kDecoySpeedMps = 2.2; // ~8 km/h
  final _decoyRnd = Random();
  final _decoyDio = Dio(
    BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}),
  );
  List<_DecoyMoto> _decoyMotos = [];

  List<Map<String, dynamic>> _realNearbyDrivers = [];
  Timer? _nearbyDriversTimer;
  BitmapDescriptor? _decoyMotoIcon;
  LatLng? _decoyCenter;

  // ── Pulse premium au point pickup — identique à order_confirmation_screen ──
  static const _kPickupPulseFrameCount = 20;
  List<BitmapDescriptor>? _pickupPulseFrames;

  LatLng _randomPointNear(LatLng center) {
    final angle = _decoyRnd.nextDouble() * 2 * pi;
    final dist = 250 + _decoyRnd.nextDouble() * (_kDecoyRadiusM - 250);
    final dLat = (dist * cos(angle)) / 111320.0;
    final dLng =
        (dist * sin(angle)) / (111320.0 * cos(center.latitude * pi / 180));
    return LatLng(center.latitude + dLat, center.longitude + dLng);
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
    a.latitude + (b.latitude - a.latitude) * t,
    a.longitude + (b.longitude - a.longitude) * t,
  );

  double _haversineM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final la1 = a.latitude * pi / 180, la2 = b.latitude * pi / 180;
    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(la1) * cos(la2) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  double _bearingDeg(LatLng a, LatLng b) {
    final lat1 = a.latitude * pi / 180, lat2 = b.latitude * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  Future<void> _fetchNearbyDrivers(LatLng pickup) async {
    final drivers = await ref
        .read(ordersRepositoryProvider)
        .getNearbyDrivers(
          lat: pickup.latitude,
          lng: pickup.longitude,
          radiusKm: _kDecoyRadiusM / 1000,
        );
    if (mounted) setState(() => _realNearbyDrivers = drivers);
  }

  void _initDecoyMotos(LatLng pickup) {
    if (_decoyMotos.isNotEmpty) return;
    _decoyCenter = pickup;
    _decoyMotos = List.generate(
      _kDecoyCount,
      (_) => _DecoyMoto(_randomPointNear(pickup)),
    );
    for (final moto in _decoyMotos) {
      _advanceDecoy(moto);
    }
    _buildDecoyMotoIcon().then((icon) {
      if (mounted) setState(() => _decoyMotoIcon = icon);
    });
  }

  Future<void> _advanceDecoy(_DecoyMoto moto) async {
    final center = _decoyCenter;
    if (!mounted || center == null) return;
    final dest = _randomPointNear(center);
    List<LatLng> pts = [moto.lastEnd, dest];
    try {
      final res = await _decoyDio.get(
        'https://router.project-osrm.org/route/v1/driving/'
        '${moto.lastEnd.longitude},${moto.lastEnd.latitude};'
        '${dest.longitude},${dest.latitude}?overview=full&geometries=geojson',
      );
      if (res.statusCode == 200 &&
          res.data['routes'] != null &&
          (res.data['routes'] as List).isNotEmpty) {
        final coords = res.data['routes'][0]['geometry']['coordinates'] as List;
        final routePts = coords
            .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList();
        if (routePts.length >= 2) pts = routePts;
      }
    } catch (_) {
      // secours : ligne droite déjà posée dans `pts`
    }
    if (!mounted) return;

    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + _haversineM(pts[i - 1], pts[i]));
    }
    final total = cum.last < 30 ? 30.0 : cum.last;

    moto.route = pts;
    moto.cumDist = cum;
    moto.totalDist = total;
    moto.lastEnd = pts.last;

    final durationMs = (total / _kDecoySpeedMps * 1000).clamp(9000, 120000);
    moto.ctrl?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs.round()),
    );
    moto.ctrl = ctrl;
    ctrl
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advanceDecoy(moto);
      })
      ..forward();
  }

  LatLng _decoyPosition(_DecoyMoto moto) {
    if (moto.route.length < 2 || moto.ctrl == null) return moto.lastEnd;
    final t = Curves.easeInOutSine.transform(moto.ctrl!.value);
    final targetDist = t * moto.totalDist;
    for (var i = 1; i < moto.cumDist.length; i++) {
      if (targetDist <= moto.cumDist[i]) {
        final segStart = moto.cumDist[i - 1];
        final segLen = moto.cumDist[i] - segStart;
        final segT = segLen > 0 ? (targetDist - segStart) / segLen : 0.0;
        moto.bearing = _bearingDeg(moto.route[i - 1], moto.route[i]);
        return _lerpLatLng(moto.route[i - 1], moto.route[i], segT);
      }
    }
    return moto.route.last;
  }

  static Future<BitmapDescriptor> _buildDecoyMotoIcon() async {
    const double size = 84;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(center, 38, Paint()..color = const Color(0x220CB8DE));
    canvas.drawCircle(center, 27, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      27,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final iconPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.two_wheeler_rounded.codePoint),
        style: TextStyle(
          fontSize: 28,
          fontFamily: Icons.two_wheeler_rounded.fontFamily,
          package: Icons.two_wheeler_rounded.fontPackage,
          color: AppColors.primary,
        ),
      )
      ..layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: 32,
      height: 32,
    );
  }

  static Future<List<BitmapDescriptor>> _buildPickupPulseFrames() async {
    const double size = 96;
    const center = Offset(size / 2, size / 2);
    final frames = <BitmapDescriptor>[];
    for (var i = 0; i < _kPickupPulseFrameCount; i++) {
      final t = i / _kPickupPulseFrameCount;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawCircle(
        center,
        14 + t * 28,
        Paint()
          ..color = AppColors.successBright.withValues(
            alpha: (1 - t).clamp(0.0, 1.0) * 0.35,
          ),
      );
      canvas.drawCircle(center, 14, Paint()..color = Colors.white);
      canvas.drawCircle(
        center,
        14,
        Paint()
          ..color = AppColors.successBright
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawCircle(center, 7, Paint()..color = AppColors.successBright);

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      frames.add(
        BitmapDescriptor.bytes(
          bytes!.buffer.asUint8List(),
          width: 44,
          height: 44,
        ),
      );
    }
    return frames;
  }

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _buildPickupPulseFrames().then((frames) {
      if (mounted) setState(() => _pickupPulseFrames = frames);
    });
    _fetchRoute();
    _connectSocket();

    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _radarCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _radarAnim = CurvedAnimation(parent: _radarCtrl, curve: Curves.easeOut);

    final pickupLat = widget.batch['pickupLatitude'] as num?;
    final pickupLng = widget.batch['pickupLongitude'] as num?;
    if (pickupLat != null && pickupLng != null) {
      final pickup = LatLng(pickupLat.toDouble(), pickupLng.toDouble());
      _initDecoyMotos(pickup);
      _fetchNearbyDrivers(pickup);
      _nearbyDriversTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _fetchNearbyDrivers(pickup),
      );
    }

    _startPolling();

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
    for (final moto in _decoyMotos) {
      moto.ctrl?.dispose();
    }
    _nearbyDriversTimer?.cancel();
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
    final batchId = widget.batch['id'] as String?;
    _acceptedSub = SocketService.instance.onBatchAccepted.listen((data) {
      if (!mounted) return;
      if (batchId != null && data['batchId'] != batchId) return;
      _pollTimer?.cancel();
      context.pushReplacement('/orders/batch/mine/$batchId');
    });
  }

  // ── Polling REST fallback (si socket mort au moment de l'acceptation) ────
  void _startPolling() {
    final batchId = widget.batch['id'] as String?;
    if (batchId == null) return;

    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      try {
        final batch = await ref
            .read(ordersRepositoryProvider)
            .getBatchById(batchId);
        final status = (batch['status'] as String? ?? '').toUpperCase();
        if (!mounted) return;

        if (status == 'ACCEPTED') {
          _pollTimer?.cancel();
          context.pushReplacement('/orders/batch/mine/$batchId');
        } else if (status == 'CANCELLED') {
          _pollTimer?.cancel();
          showDemToast(
            context,
            'Votre tournée a été annulée — aucun livreur n\'a pu être trouvé à temps.',
            isError: true,
          );
          context.pop();
        }
      } catch (_) {
        // réseau indisponible — on réessaie au prochain tick
      }
    });
  }

  void _continueWaiting() => setState(() {
    _waitTimedOut = false;
    _waitSeconds = 0;
  });

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleMapTheme() async {
    await ref.read(mapNightProvider.notifier).toggle();
    await _loadMapStyle();
  }

  // Itinéraire complet collecte → arrêt 1 → arrêt 2 → … via OSRM (plusieurs
  // points de passage dans une seule requête) — secours en lignes droites
  // point à point si le réseau est indisponible.
  Future<void> _fetchRoute() async {
    final pickupLat = widget.batch['pickupLatitude'] as num?;
    final pickupLng = widget.batch['pickupLongitude'] as num?;
    if (pickupLat == null || pickupLng == null) return;

    final waypoints = [
      LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
      for (final s in _stops)
        if (s['deliveryLatitude'] != null && s['deliveryLongitude'] != null)
          LatLng(
            (s['deliveryLatitude'] as num).toDouble(),
            (s['deliveryLongitude'] as num).toDouble(),
          ),
    ];
    if (waypoints.length < 2) return;

    if (mounted) setState(() => _routePoints = waypoints);

    try {
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
      final coordsParam = waypoints
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      final res = await dio.get(
        'https://router.project-osrm.org/route/v1/driving/$coordsParam?overview=full&geometries=geojson',
      );
      if (res.statusCode == 200 &&
          res.data['routes'] != null &&
          (res.data['routes'] as List).isNotEmpty) {
        final route = res.data['routes'][0];
        final coords = route['geometry']['coordinates'] as List;
        final points = coords
            .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList();
        if (mounted) setState(() => _routePoints = points);
      }
    } catch (_) {}
  }

  Future<void> _cancelBatch() async {
    final batchId = widget.batch['id'] as String?;
    if (batchId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.gradientSplash,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Annuler la tournée ?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Voulez-vous vraiment annuler cette tournée en attente ?',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              SwipeToConfirm(
                label: 'Glissez pour annuler',
                onConfirmed: () async => Navigator.pop(ctx, true),
                trackColor: AppColors.error,
                thumbColor: Colors.white,
                iconColor: AppColors.error,
                labelColor: Colors.white,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'Non',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(ordersRepositoryProvider).cancelBatch(batchId);
      if (mounted) {
        showDemToast(context, 'Tournée annulée avec succès');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cancelling = false);
        showDemToast(context, friendlyError(e), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    final totalPrice = (batch['totalPrice'] as num?)?.toDouble();
    final demFee = (batch['demFee'] as num?)?.toDouble() ?? 0.0;
    final pickupAddress = batch['pickupAddress'] as String? ?? 'Départ';

    final pickupLat = batch['pickupLatitude'] as num?;
    final pickupLng = batch['pickupLongitude'] as num?;

    Set<Marker> markers = {};
    Set<Polyline> polylines = {};

    if (pickupLat != null && pickupLng != null) {
      final pulseFrames = _pickupPulseFrames;
      final pickupIcon = pulseFrames != null && pulseFrames.isNotEmpty
          ? pulseFrames[(_radarCtrl.value * pulseFrames.length).floor().clamp(
              0,
              pulseFrames.length - 1,
            )]
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
          icon: pickupIcon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 1,
        ),
      );
    }
    for (var i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      final lat = s['deliveryLatitude'] as num?;
      final lng = s['deliveryLongitude'] as num?;
      if (lat == null || lng == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId('stop-$i'),
          position: LatLng(lat.toDouble(), lng.toDouble()),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: 'Arrêt ${i + 1}'),
        ),
      );
    }

    if (_routePoints.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: _routePoints,
          color: AppColors.primary,
          width: 4,
        ),
      );
    }

    if (_decoyMotoIcon != null) {
      for (var i = 0; i < _decoyMotos.length; i++) {
        final moto = _decoyMotos[i];
        if (moto.ctrl == null) continue;
        markers.add(
          Marker(
            markerId: MarkerId('decoy-moto-$i'),
            position: _decoyPosition(moto),
            icon: _decoyMotoIcon!,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 0,
          ),
        );
      }
    }

    if (_decoyMotoIcon != null) {
      for (final driver in _realNearbyDrivers) {
        final dLat = (driver['lat'] as num?)?.toDouble();
        final dLng = (driver['lng'] as num?)?.toDouble();
        final id = driver['id'] as String?;
        if (dLat == null || dLng == null || id == null) continue;
        markers.add(
          Marker(
            markerId: MarkerId('real-driver-$id'),
            position: LatLng(dLat, dLng),
            icon: _decoyMotoIcon!,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 0,
          ),
        );
      }
    }

    final initialTarget = pickupLat != null && pickupLng != null
        ? LatLng(pickupLat.toDouble(), pickupLng.toDouble())
        : const LatLng(14.6937, -17.4441);

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: 14.5,
                tilt: 40,
              ),
              padding: EdgeInsets.only(bottom: _kMaxContent + 24),
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
              },
            ),
          ),

          Positioned(
            right: 16,
            bottom:
                max(
                  _kMinContent + 22.0,
                  _kMaxContent - _panelDragOffset + 22.0,
                ) +
                60 +
                MediaQuery.of(context).viewPadding.bottom,
            child: MapThemeToggleButton(onTap: _toggleMapTheme),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.gradientSplash,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragStart: (_) =>
                            setState(() => _isDragging = true),
                        onVerticalDragUpdate: (d) {
                          final maxOffset = _kMaxContent - _kMinContent;
                          setState(() {
                            _panelDragOffset = (_panelDragOffset + d.delta.dy)
                                .clamp(0.0, maxOffset);
                          });
                        },
                        onVerticalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          final maxOffset = _kMaxContent - _kMinContent;
                          setState(() {
                            _isDragging = false;
                            _panelDragOffset =
                                (v > 200 || _panelDragOffset > maxOffset / 2)
                                ? maxOffset
                                : 0.0;
                          });
                        },
                        onTap: () {
                          final maxOffset = _kMaxContent - _kMinContent;
                          setState(() {
                            _isDragging = false;
                            _panelDragOffset = _panelDragOffset == 0
                                ? maxOffset
                                : 0.0;
                          });
                        },
                        child: SizedBox(
                          width: double.infinity,
                          height: 22,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),

                      AnimatedContainer(
                        duration: _isDragging
                            ? Duration.zero
                            : const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        height: (_kMaxContent - _panelDragOffset).clamp(
                          _kMinContent,
                          _kMaxContent,
                        ),
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            maxHeight: _kMaxContent,
                            child: SizedBox(
                              height: _kMaxContent,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  12 + _bottomInset,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (_waitTimedOut)
                                      _TimeoutBanner(
                                        onContinue: _continueWaiting,
                                        onCancel: _cancelBatch,
                                      )
                                    else
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          AnimatedBuilder(
                                            animation: _radarAnim,
                                            builder: (ctx, child) => SizedBox(
                                              width: 36,
                                              height: 36,
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Opacity(
                                                    opacity:
                                                        (1 - _radarAnim.value)
                                                            .clamp(0.0, 1.0),
                                                    child: Container(
                                                      width:
                                                          36 * _radarAnim.value,
                                                      height:
                                                          36 * _radarAnim.value,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: _kBatchAccent,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    width: 10,
                                                    height: 10,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: _kBatchAccent,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Recherche d\'un livreur…',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'Attente : $_waitLabel',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.5),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 16),

                                    // ── Récap trajet — collecte + N arrêts ──
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _RouteLine(
                                            icon: Icons.circle,
                                            iconColor: AppColors.successBright,
                                            label: pickupAddress,
                                          ),
                                          for (
                                            var i = 0;
                                            i < _stops.length;
                                            i++
                                          ) ...[
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 6,
                                              ),
                                              child: Container(
                                                width: 2,
                                                height: 10,
                                                color: Colors.white.withValues(
                                                  alpha: 0.25,
                                                ),
                                              ),
                                            ),
                                            _RouteLine(
                                              icon: Icons.location_on,
                                              iconColor: AppColors.error,
                                              label:
                                                  _stops[i]['deliveryAddress']
                                                      as String? ??
                                                  'Arrêt ${i + 1}',
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Prix ──
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                '${_stops.length} arrêt${_stops.length > 1 ? 's' : ''}',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.70),
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const Spacer(),
                                              Text(
                                                totalPrice != null
                                                    ? formatFcfa(totalPrice)
                                                    : '—',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (demFee > 0) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  'Frais DEM',
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.70,
                                                        ),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  '+${formatFcfa(demFee)}',
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.70,
                                                        ),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          if (totalPrice != null) ...[
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              child: Divider(
                                                height: 1,
                                                color: Colors.white.withValues(
                                                  alpha: 0.15,
                                                ),
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                const Text(
                                                  'Total à payer',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  formatFcfa(totalPrice),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: _cancelling
                                              ? null
                                              : _cancelBatch,
                                          child: Container(
                                            height: 50,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: AppColors.error
                                                    .withValues(alpha: 0.6),
                                              ),
                                            ),
                                            child: Center(
                                              child: _cancelling
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color:
                                                                AppColors.error,
                                                          ),
                                                    )
                                                  : const Text(
                                                      'Annuler',
                                                      style: TextStyle(
                                                        color: AppColors.error,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: PrimaryButton(
                                            label: 'Retour à l\'accueil',
                                            height: 50,
                                            // Dégradé par défaut (même que
                                            // Simple/Express) au lieu du vert
                                            // plein _kBatchAccent — trop
                                            // sombre/plat sur ce fond dégradé.
                                            onTap: _cancelling
                                                ? null
                                                : () {
                                                    context.go(
                                                      appStartupNotifier
                                                          .homeForRole,
                                                    );
                                                    Future.microtask(() {
                                                      if (context.mounted) {
                                                        showDemToast(
                                                          context,
                                                          'Votre tournée est en attente — vous serez notifié dès qu\'un livreur est trouvé.',
                                                        );
                                                      }
                                                    });
                                                  },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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

// Ligne du récap trajet (point coloré + adresse) — pendant de AddressRow
// mais avec `maxLines`/`overflow` gérés ici directement, plus simple que le
// widget partagé pour ce cas précis (pas besoin de ses autres options).
class _RouteLine extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  const _RouteLine({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ── Bannière timeout 5 min — identique à order_confirmation_screen.dart ──
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
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Nous continuons de chercher en arrière-plan.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.60),
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.60),
                  ),
                ),
                child: Text(
                  'Annuler',
                  style: ClientText.body.copyWith(color: AppColors.error),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onContinue,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _kBatchAccent.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _kBatchAccent.withValues(alpha: 0.60),
                  ),
                ),
                child: Text(
                  'Continuer d\'attendre',
                  style: ClientText.body.copyWith(color: _kBatchAccent),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
