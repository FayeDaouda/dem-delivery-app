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

import '../../shared/widgets/address_row.dart';
import '../../shared/widgets/cancel_reason_sheet.dart';
import '../../shared/widgets/map_theme_toggle_button.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/share_tracking_sheet.dart';
import '../../shared/widgets/swipe_to_confirm.dart';

import '../../core/router/app_startup_notifier.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../deliveries/providers/orders_provider.dart';
import '../../core/theme/map_theme_provider.dart';
import '../home_driver/navigation/map_theme.dart';

// Une moto fictive — voir _initDecoyMotos. `lastEnd` sert de point de départ
// au tronçon suivant, pour un déplacement continu (jamais de saut).
class _DecoyMoto {
  LatLng lastEnd;
  List<LatLng> route = [];
  List<double> cumDist = [];
  double totalDist = 0;
  double bearing = 0;
  AnimationController? ctrl;
  _DecoyMoto(this.lastEnd);
}

/// Affiché après la création d'une commande.
/// Reçoit l'objet `order` retourné par le backend.
class OrderConfirmationScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  const OrderConfirmationScreen({super.key, required this.order});

  @override
  ConsumerState<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState
    extends ConsumerState<OrderConfirmationScreen>
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
  // Hauteur du panneau ajustée au contenu réel de chaque état — la bannière
  // de timeout (icône + titre + sous-titre + 2 boutons) est bien plus haute
  // que la ligne radar normale ; une valeur fixe unique pour les deux
  // laissait un grand vide au-dessus du contenu en état normal (le Column
  // interne est aligné en bas via `mainAxisAlignment.end`). Les lignes
  // "Frais DEM"/"Réduction" sont conditionnelles (n'existaient pas quand
  // 300/370 ont été réglées) — sans ce supplément, leur simple présence
  // faisait déborder le panneau de quelques pixels.
  double get _kMaxContent {
    final demFee = (widget.order['demFee'] as num?)?.toDouble() ?? 0.0;
    final discountAmount =
        (widget.order['discountAmount'] as num?)?.toDouble() ?? 0.0;
    var extra = 0.0;
    if (demFee > 0) extra += 21;
    if (discountAmount > 0) extra += 21;
    return (_waitTimedOut ? 370.0 : 300.0) + extra + _bottomInset;
  }

  static const double _kMinContent = 64.0;
  double get _bottomInset => MediaQuery.of(context).viewPadding.bottom;

  // Animation radar
  late final AnimationController _radarCtrl;
  late final Animation<double> _radarAnim;

  // ── Motos fictives ────────────────────────────────────────────────────────
  // Purement décoratif — rassure visuellement le client pendant la
  // recherche ("des livreurs circulent tout près") sans prétendre montrer
  // de vraies positions. Chaque moto suit un VRAI itinéraire routier (même
  // API OSRM que le trajet réel, voir _fetchRoute) à une vitesse constante
  // et réaliste — un simple aller-retour en ligne droite à durée fixe se
  // voyait immédiatement comme artificiel (vitesse incohérente selon la
  // distance, trajectoire ignorant les routes).
  static const _kDecoyCount = 4;
  static const _kDecoyRadiusM = 1800.0;
  // Volontairement très lent — un mouvement d'ambiance en arrière-plan, à
  // peine perceptible, plutôt qu'un vrai déplacement qu'on regarde bouger.
  static const _kDecoySpeedMps = 2.2; // ~8 km/h
  final _decoyRnd = Random();
  final _decoyDio = Dio(
    BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}),
  );
  List<_DecoyMoto> _decoyMotos = [];

  // ── Vrais livreurs à proximité ───────────────────────────────────────────
  // Mêlés aux motos fictives, avec exactement la même icône — impossible à
  // distinguer visuellement des motos décoratives (voir _decoyMotoIcon).
  // Purement informatif : ces livreurs ne sont pas assignés à cette
  // commande, ce n'est qu'un signal de présence.
  List<Map<String, dynamic>> _realNearbyDrivers = [];
  Timer? _nearbyDriversTimer;
  BitmapDescriptor? _decoyMotoIcon;
  LatLng? _decoyCenter;

  // ── Pulse premium au point pickup ────────────────────────────────────────
  // Un Marker Google Maps ne peut pas s'animer nativement, et le repositionner
  // via un overlay Flutter (getScreenCoordinate) est peu fiable : ces
  // coordonnées sont en pixels physiques sur Android mais en points logiques
  // sur iOS, donc un seul calcul ne marche jamais sur les deux plateformes à
  // la fois. Solution robuste : on pré-rend une série d'images (anneau qui
  // s'étend et s'estompe autour d'un cœur fixe) et on fait défiler l'icône
  // du Marker lui-même — toujours pixel-parfait, quelle que soit la
  // plateforme, le zoom ou le pan.
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

  // Calcule (ou recalcule à l'arrivée) le prochain tronçon d'une moto : un
  // vrai itinéraire OSRM vers un point aléatoire proche, parcouru à vitesse
  // constante. Secours en ligne droite si le réseau indisponible — toujours
  // à la même vitesse, jamais de saut instantané.
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

  // Position + cap courants d'une moto, interpolés le long de son
  // itinéraire réel selon la distance parcourue (pas l'index du point) —
  // seule façon d'obtenir une vitesse vraiment constante sur des segments
  // de longueurs inégales.
  LatLng _decoyPosition(_DecoyMoto moto) {
    if (moto.route.length < 2 || moto.ctrl == null) return moto.lastEnd;
    // Ease in/out plutôt que linéaire : la moto démarre et s'arrête en
    // douceur à chaque tronçon — un rendu plus premium qu'un mouvement
    // mécanique à vitesse strictement constante.
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

  // Point pickup — une série d'images figées composant la boucle du pulse :
  // un cœur fixe (pastille pleine) entouré d'un anneau qui s'étend et
  // s'estompe. Générées une seule fois, puis simplement enchaînées comme un
  // flipbook au rythme de `_radarCtrl` — voir build().
  static Future<List<BitmapDescriptor>> _buildPickupPulseFrames() async {
    const double size = 96;
    const center = Offset(size / 2, size / 2);
    final frames = <BitmapDescriptor>[];
    for (var i = 0; i < _kPickupPulseFrameCount; i++) {
      final t = i / _kPickupPulseFrameCount; // 0..1 — phase du cycle
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Anneau qui s'étend en s'estompant
      canvas.drawCircle(
        center,
        14 + t * 28,
        Paint()
          ..color = AppColors.successBright.withValues(
            alpha: (1 - t).clamp(0.0, 1.0) * 0.35,
          ),
      );
      // Cœur fixe — pastille pleine bordée de blanc
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

    // Radar pulsé — anime aussi bien l'indicateur du panneau bas que le
    // flipbook du marker pickup (voir _pickupPulseFrames dans build()).
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _radarCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _radarAnim = CurvedAnimation(parent: _radarCtrl, curve: Curves.easeOut);

    final pickupLat = widget.order['pickupLatitude'] as num?;
    final pickupLng = widget.order['pickupLongitude'] as num?;
    if (pickupLat != null && pickupLng != null) {
      final pickup = LatLng(pickupLat.toDouble(), pickupLng.toDouble());
      _initDecoyMotos(pickup);
      _fetchNearbyDrivers(pickup);
      // Rafraîchi périodiquement — un livreur en ligne peut se déplacer,
      // ou passer en/hors ligne, pendant que le client patiente.
      _nearbyDriversTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _fetchNearbyDrivers(pickup),
      );
    }

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
    final orderId = widget.order['id'] as String?;
    _acceptedSub = SocketService.instance.onOrderAccepted.listen((data) {
      if (!mounted) return;
      if (orderId != null && data['orderId'] != orderId) return;
      final driverId = data['driverId'] as String?;
      if (driverId == null) return;
      _pollTimer?.cancel();
      context.pushReplacement(
        '/orders/tracking',
        extra: {
          'orderId': data['orderId'] as String,
          'driverId': driverId,
          'etaPickupMin': data['etaPickupMin'] as int?,
          'initialOrder': {
            ...widget.order,
            'status': 'ACCEPTED',
            'driverId': driverId,
          },
        },
      );
    });
  }

  // ── Polling REST fallback (si socket mort au moment de l'acceptation) ────────
  void _startPolling() {
    final orderId = widget.order['id'] as String?;
    if (orderId == null) return;

    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      try {
        final order = await ref
            .read(ordersRepositoryProvider)
            .getOrderById(orderId);
        final status = (order['status'] as String? ?? '').toUpperCase();
        if (!mounted) return;

        if (status == 'ACCEPTED') {
          _pollTimer?.cancel();
          final driverId =
              (order['driver'] as Map?)?['id'] as String? ??
              order['driverId'] as String?;
          if (driverId == null) return;
          context.pushReplacement(
            '/orders/tracking',
            extra: {
              'orderId': orderId,
              'driverId': driverId,
              'initialOrder': {...order, 'status': 'ACCEPTED'},
            },
          );
        } else if (status == 'CANCELLED') {
          _pollTimer?.cancel();
          // Annulation décidée côté serveur (délai dépassé, etc.) — sans ce
          // toast, le client se retrouve renvoyé en arrière sans comprendre
          // pourquoi sa commande a disparu (contrairement à l'annulation
          // manuelle, qui affiche bien une confirmation).
          showDemToast(
            context,
            'Votre commande a été annulée — aucun livreur n\'a pu être trouvé à temps.',
            isError: true,
          );
          context.pop();
        }
      } catch (_) {
        // réseau indisponible — on réessaie au prochain tick
      }
    });
  }

  // ── Timeout 5 min — le client choisit de continuer d'attendre ───────────────
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

  Future<void> _fetchRoute() async {
    final order = widget.order;
    final pickupLat = order['pickupLatitude'] as num?;
    final pickupLng = order['pickupLongitude'] as num?;
    final deliveryLat = order['deliveryLatitude'] as num?;
    final deliveryLng = order['deliveryLongitude'] as num?;

    if (pickupLat == null ||
        pickupLng == null ||
        deliveryLat == null ||
        deliveryLng == null) {
      return;
    }

    if (mounted) {
      setState(
        () => _routePoints = [
          LatLng(pickupLat.toDouble(), pickupLng.toDouble()),
          LatLng(deliveryLat.toDouble(), deliveryLng.toDouble()),
        ],
      );
    }

    try {
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
      final res = await dio.get(
        'https://router.project-osrm.org/route/v1/driving/$pickupLng,$pickupLat;$deliveryLng,$deliveryLat?overview=full&geometries=geojson',
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

  void _showShareSheet(BuildContext ctx) {
    ShareTrackingSheet.show(ctx, orderId: widget.order['id'] as String? ?? '');
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
                'Annuler la commande ?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Voulez-vous vraiment annuler cette commande en attente ?',
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

    final reason = await showCancelReasonSheet(
      context,
      reasons: kClientCancelReasons,
    );
    if (!mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref
          .read(ordersRepositoryProvider)
          .cancelOrder(orderId, reason: reason);
      if (mounted) {
        showDemToast(context, 'Commande annulée avec succès');
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
    final order = widget.order;
    final price = (order['price'] as num?)?.toDouble();
    final demFee = (order['demFee'] as num?)?.toDouble() ?? 0.0;
    final discountAmount = (order['discountAmount'] as num?)?.toDouble() ?? 0.0;
    final promoCode = order['promoCode'] as String?;
    final surge = (order['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
    final pickupAddress = order['pickupAddress'] as String? ?? 'Départ';
    final deliveryAddress = order['deliveryAddress'] as String? ?? 'Arrivée';

    final pickupLat = order['pickupLatitude'] as num?;
    final pickupLng = order['pickupLongitude'] as num?;
    final deliveryLat = order['deliveryLatitude'] as num?;
    final deliveryLng = order['deliveryLongitude'] as num?;

    Set<Marker> markers = {};
    Set<Polyline> polylines = {};

    if (pickupLat != null && pickupLng != null) {
      // Flipbook du pulse (voir _buildPickupPulseFrames) — l'icône avance
      // d'une frame à chaque tick de _radarCtrl, en boucle. Toujours
      // pixel-parfait sur le point, quels que soient plateforme/zoom/pan.
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
    if (deliveryLat != null && deliveryLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('delivery'),
          position: LatLng(deliveryLat.toDouble(), deliveryLng.toDouble()),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
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

    // Motos fictives — purement décoratives, voir _initDecoyMotos.
    if (_decoyMotoIcon != null) {
      for (var i = 0; i < _decoyMotos.length; i++) {
        final moto = _decoyMotos[i];
        if (moto.ctrl == null) continue;
        markers.add(
          Marker(
            markerId: MarkerId('decoy-moto-$i'),
            position: _decoyPosition(moto),
            // Pas de rotation : l'icône est une silhouette de profil, la
            // faire pivoter à un cap arbitraire la rendrait parfois à
            // l'envers — moins "pro" que de la garder simplement droite.
            icon: _decoyMotoIcon!,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 0,
          ),
        );
      }
    }

    // Vrais livreurs à proximité — MÊME icône que les motos fictives
    // ci-dessus, aucun moyen de les distinguer visuellement.
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
          // ── Map Background ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: 14.5,
                tilt: 40,
              ),
              // Décale le centre optique de la carte vers le haut de la zone
              // réellement visible — sans ça le point pickup se retrouve
              // centré derrière le panneau bas au lieu d'être bien visible.
              // C'est ce qui fait tout le travail de centrage par défaut :
              // pas besoin d'animer la caméra après coup.
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

          // ── MAP THEME TOGGLE ──────────────────────────────────────────────
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

          // ── Panneau bas dégradé cyan ──
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
                      // Drag handle
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
                                    // ── Header : radar normal OU timeout 5 min ──
                                    if (_waitTimedOut)
                                      _TimeoutBanner(
                                        onContinue: _continueWaiting,
                                        onCancel: _cancelOrder,
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
                                                          color:
                                                              AppColors.primary,
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
                                                          color:
                                                              AppColors.primary,
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

                                    // ── Route recap ──
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
                                          AddressRow(
                                            icon: Icons.circle,
                                            iconColor: AppColors.successBright,
                                            address: pickupAddress,
                                            dark: true,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            child: Container(
                                              width: 2,
                                              height: 14,
                                              color: Colors.white.withValues(
                                                alpha: 0.25,
                                              ),
                                            ),
                                          ),
                                          AddressRow(
                                            icon: Icons.location_on,
                                            iconColor: AppColors.error,
                                            address: deliveryAddress,
                                            dark: true,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Price breakdown ──
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
                                                'Course',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.70),
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const Spacer(),
                                              if (surge > 1.0) ...[
                                                const Icon(
                                                  Icons.flash_on,
                                                  color: AppColors.surge,
                                                  size: 13,
                                                ),
                                                const SizedBox(width: 3),
                                              ],
                                              Text(
                                                price != null
                                                    ? formatFcfa(price)
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
                                          if (discountAmount > 0) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  promoCode != null
                                                      ? 'Réduction ($promoCode)'
                                                      : 'Réduction',
                                                  style: const TextStyle(
                                                    color:
                                                        AppColors.successLight,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  '-${formatFcfa(discountAmount)}',
                                                  style: const TextStyle(
                                                    color:
                                                        AppColors.successLight,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          // Total — toujours affiché dès qu'un prix existe (frais et/ou
                                          // réduction ou non) : le client ne doit jamais avoir à
                                          // additionner Course + Frais DEM lui-même. Même règle que
                                          // order_create_screen.dart.
                                          if (price != null) ...[
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
                                                  formatFcfa(
                                                    (((price) +
                                                            demFee -
                                                            discountAmount))
                                                        .clamp(
                                                          0,
                                                          double.infinity,
                                                        ),
                                                  ),
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

                                    // ── Boutons Action ──
                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: _cancelling
                                              ? null
                                              : _cancelOrder,
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
                                                          'Votre commande est en attente — vous serez notifié dès qu\'un livreur est trouvé.',
                                                        );
                                                      }
                                                    });
                                                  },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ), // Column
                              ), // Padding
                            ), // SizedBox
                          ), // OverflowBox
                        ), // ClipRect
                      ), // AnimatedContainer
                    ], // outer Column children
                  ), // outer Column
                ), // Padding(top:8)
              ), // SafeArea
            ), // Container
          ), // Align
        ],
      ),
    );
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
                  color: AppColors.primary.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.60),
                  ),
                ),
                child: Text(
                  'Continuer d\'attendre',
                  style: ClientText.body.copyWith(color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
