import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/theme/map_theme_provider.dart';
import '../../deliveries/providers/orders_provider.dart';
import '../../home_driver/navigation/map_theme.dart';
import '../../home_driver/navigation/route_tracker.dart';
import '../../../shared/widgets/operator_picker_sheet.dart';
import '../../../shared/widgets/samirpay_payment_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';

class DemProOrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String driverId;
  final int? etaPickupMin;
  final Map<String, dynamic>? initialOrder;

  const DemProOrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.driverId,
    this.etaPickupMin,
    this.initialOrder,
  });

  @override
  ConsumerState<DemProOrderTrackingScreen> createState() =>
      _DemProOrderTrackingScreenState();
}

class _DemProOrderTrackingScreenState
    extends ConsumerState<DemProOrderTrackingScreen> {
  // ── Map ───────────────────────────────────────────────────────────────────
  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  BitmapDescriptor? _driverIcon;
  LatLng? _driverPos;

  // ── Ordre ─────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _order;
  String _status = 'ACCEPTED';
  bool _done = false;

  // ── Route ─────────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  List<LatLng> _displayRoute = [];
  int _lastTrimIdx = 0;
  DateTime? _lastReroute;

  // ── Sockets ───────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _locationSub;
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  // ── Polling ───────────────────────────────────────────────────────────────
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _status = (widget.initialOrder?['status'] as String? ?? 'ACCEPTED').toUpperCase();
    _initDriverPos();
    _loadMapStyle();
    _buildDriverIcon();
    _fetchRoute();
    _connectSocket();
    _startPolling();
  }

  void _initDriverPos() {
    final driver = widget.initialOrder?['driver'] as Map<String, dynamic>?;
    final lat = (driver?['latitude'] as num?)?.toDouble();
    final lng = (driver?['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      _driverPos = LatLng(lat, lng);
    }
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _statusSub?.cancel();
    _pollTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ── Setup ─────────────────────────────────────────────────────────────────
  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _buildDriverIcon() async {
    _driverIcon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(40, 40)),
      'assets/images/moto_marker.png',
    );
  }

  // ── Socket ────────────────────────────────────────────────────────────────
  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;
    SocketService.instance.connect(token);

    _locationSub = SocketService.instance.onDriverLocation.listen((data) {
      if (!mounted) return;
      final driverId = data['driverId'] as String?;
      if (driverId != widget.driverId) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final loc = LatLng(lat, lng);
      setState(() => _driverPos = loc);
      _mapCtrl?.animateCamera(CameraUpdate.newLatLng(loc));
      _matchAndTrimRoute(loc);
    });

    _statusSub = SocketService.instance.onOrderStatusUpdated.listen((data) {
      if (!mounted) return;
      if (data['orderId'] != widget.orderId) return;
      final s = (data['status'] as String? ?? '').toUpperCase();
      final phaseChanged = s != _status;
      setState(() => _status = s);
      // Changement de phase (récupération → livraison) : l'itinéraire doit
      // repartir du livreur vers la nouvelle destination, pas rester sur
      // l'ancien trajet pickup→livraison.
      if (phaseChanged) _fetchRoute();
      if (s == 'DELIVERED') {
        _pollTimer?.cancel();
        _showCompletionDialog();
      }
    });
  }

  // ── Recalage position ↔ tracé ────────────────────────────────────────────
  // Raccourcit le tracé affiché jusqu'à la position projetée du livreur (pas
  // seulement le sommet le plus proche — voir RouteTracker) et déclenche un
  // recalcul si le livreur dévie de plus de 70 m, limité à 1 fois/15s.
  void _matchAndTrimRoute(LatLng driverLoc) {
    if (_routePoints.isEmpty) return;
    final match = RouteTracker.closestMatch(_routePoints, driverLoc, _lastTrimIdx);
    if (match == null) return;

    if (match.segmentIndex >= _lastTrimIdx) {
      _lastTrimIdx = match.segmentIndex;
      if (mounted) {
        setState(() => _displayRoute = RouteTracker.remainingRoute(_routePoints, match));
      }
    }

    final now = DateTime.now();
    if (match.distanceMeters > 70 &&
        (_lastReroute == null || now.difference(_lastReroute!).inSeconds >= 15)) {
      _lastReroute = now;
      _lastTrimIdx = 0;
      _fetchRoute();
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || _done) return;
      try {
        final order = await ref
            .read(ordersRepositoryProvider)
            .getOrderById(widget.orderId);
        if (!mounted) return;
        final s = (order['status'] as String? ?? '').toUpperCase();
        final driver = order['driver'] as Map<String, dynamic>?;
        final lat = (driver?['latitude'] as num?)?.toDouble();
        final lng = (driver?['longitude'] as num?)?.toDouble();
        final phaseChanged = s != _status;
        LatLng? newPos;
        if (lat != null && lng != null && lat != 0 && lng != 0) newPos = LatLng(lat, lng);
        setState(() {
          _order = order;
          _status = s;
          if (newPos != null) _driverPos = newPos;
        });
        if (phaseChanged) {
          _fetchRoute();
        } else if (newPos != null) {
          _matchAndTrimRoute(newPos);
        }
        if (s == 'DELIVERED' || s == 'CANCELLED') {
          _pollTimer?.cancel();
          if (s == 'DELIVERED') _showCompletionDialog();
          if (s == 'CANCELLED' && mounted) context.go('/dem-pro/home');
        }
      } catch (_) {}
    });
  }

  // ── Route ─────────────────────────────────────────────────────────────────
  Future<void> _fetchRoute() async {
    final o = _order ?? widget.initialOrder;
    if (o == null) return;
    final pLat = o['pickupLatitude']    as double?;
    final pLng = o['pickupLongitude']   as double?;
    final dLat = o['deliveryLatitude']  as double?;
    final dLng = o['deliveryLongitude'] as double?;
    if (pLat == null || pLng == null || dLat == null || dLng == null) return;

    // Origine/destination selon la phase — avant récupération le trajet va
    // du livreur vers le point de collecte, après vers le point de livraison
    // (sinon le tracé reste figé sur pickup→livraison toute la course).
    final double oLat, oLng, tLat, tLng;
    if (_status == 'ACCEPTED' && _driverPos != null) {
      oLat = _driverPos!.latitude;  oLng = _driverPos!.longitude;
      tLat = pLat;                  tLng = pLng;
    } else if (_status == 'PICKED_UP' || _status == 'IN_TRANSIT') {
      oLat = _driverPos?.latitude  ?? pLat;
      oLng = _driverPos?.longitude ?? pLng;
      tLat = dLat;                  tLng = dLng;
    } else {
      oLat = pLat; oLng = pLng;
      tLat = dLat; tLng = dLng;
    }

    try {
      final res = await Dio().get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin':      '$oLat,$oLng',
          'destination': '$tLat,$tLng',
          'key':         AppConfig.mapsApiKey,
        },
      );
      final steps = (res.data['routes'] as List?)?.first['legs']?.first['steps'] as List?;
      if (steps == null || !mounted) return;
      final pts = <LatLng>[];
      for (final s in steps) {
        pts.addAll(_decodePolyline(s['polyline']['points'] as String));
      }
      if (mounted) {
        setState(() {
          _routePoints = pts;
          _displayRoute = pts;
          _lastTrimIdx = 0;
        });
      }
    } catch (_) {}
  }

  List<LatLng> _decodePolyline(String encoded) {
    final pts = <LatLng>[];
    int idx = 0, lat = 0, lng = 0;
    while (idx < encoded.length) {
      int b, shift = 0, result = 0;
      do { b = encoded.codeUnitAt(idx++) - 63; result |= (b & 0x1F) << shift; shift += 5; } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0; result = 0;
      do { b = encoded.codeUnitAt(idx++) - 63; result |= (b & 0x1F) << shift; shift += 5; } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
  }

  // ── Completion ────────────────────────────────────────────────────────────
  void _showCompletionDialog() {
    if (_done) return;
    _done = true;
    int selectedRating = 5;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.success, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'Livraison effectuée !',
              style: ClientText.title.copyWith(color: AppColors.textPrimary, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Commande #${widget.orderId.substring(0, 8).toUpperCase()} livrée avec succès.',
              style: ClientText.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text('Notez le livreur', style: ClientText.subtitle.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setDialogState(() => selectedRating = star),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      star <= selectedRating ? Icons.star : Icons.star_border,
                      color: star <= selectedRating ? AppColors.ratingGold : AppColors.textSecondary,
                      size: 32,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final dId = (_order?['driver'] as Map?)?['id'] as String?;
                  if (dId != null && selectedRating > 0) {
                    try {
                      await ref.read(ordersRepositoryProvider).rateDriver(
                        orderId: widget.orderId,
                        driverId: dId,
                        score: selectedRating,
                      );
                    } catch (_) {}
                  }
                  if (!mounted) return;
                  Navigator.pop(context);
                  context.pushReplacement('/dem-pro/orders/receipt', extra: _order ?? widget.initialOrder ?? {});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Voir le reçu', style: ClientText.body.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/dem-pro/home');
                },
                child: Text('Retour au tableau de bord', style: ClientText.body.copyWith(color: AppColors.textSecondary)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _shareOrder() {
    final baseUrl = 'https://api.dem.sn';
    final url = '$baseUrl/track/${widget.orderId}';
    SharePlus.instance.share(ShareParams(text: 'Suivez ma livraison DEM en temps réel : $url'));
  }

  // "Vous payez la livraison" (paymentMode merchant) : c'est l'entreprise
  // DEM Pro elle-même qui règle en ligne, pas le destinataire — même flux
  // que le client classique (payOnline autorise déjà order.clientId ===
  // requesterId, quel que soit le rôle, voir samirpay.service.js).
  Future<void> _payOnline() async {
    final o = _order ?? widget.initialOrder ?? {};
    final price = clientChargeFor(o);

    final operatorName = await chooseOperator(context, title: 'Payer avec');
    if (operatorName == null || !mounted) return;

    await SamirpayPaymentSheet.show(
      context,
      amount: price,
      title: 'Paiement de la livraison',
      initPayment: () => ref.read(ordersRepositoryProvider).payOnline(widget.orderId, operatorName),
      confirmationStream: SocketService.instance.onOrderPaymentConfirmed
          .where((event) => event['orderId'] == widget.orderId),
      onSuccess: () {
        if (mounted) setState(() => _order = {..._order ?? widget.initialOrder ?? {}, 'paymentStatus': 'PAID'});
      },
    );
  }

  // ── Contact livreur ───────────────────────────────────────────────────────
  void _callDriver() {
    final phone = (_order?['driver'] as Map?)?['phone'] as String?;
    if (phone == null) return;
    launchUrl(Uri.parse('tel:$phone'));
  }

  void _whatsAppDriver(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final number = cleaned.startsWith('221') ? cleaned : '221$cleaned';
    launchUrl(
      Uri.parse('https://wa.me/$number'),
      mode: LaunchMode.externalApplication,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _short(String? addr) =>
      (addr == null || addr.isEmpty) ? '—' : addr.split(',').first.trim();

  (String, Color) get _statusInfo => switch (_status) {
    'ACCEPTED'   => ('Livreur en route vers le colis', AppColors.primary),
    'PICKED_UP'  => ('Colis récupéré · En route', AppColors.warning),
    'IN_TRANSIT' => ('En route vers la destination', AppColors.primary),
    'DELIVERED'  => ('Livraison effectuée', AppColors.success),
    'CANCELLED'  => ('Commande annulée', AppColors.error),
    _            => ('En attente', AppColors.textSecondary),
  };

  String? get _distanceInfo {
    if (_driverPos == null) return null;
    final o = _order ?? widget.initialOrder ?? {};
    final targetLat = _status == 'PICKED_UP'
        ? (o['deliveryLatitude'] as num?)?.toDouble()
        : (o['pickupLatitude'] as num?)?.toDouble();
    final targetLng = _status == 'PICKED_UP'
        ? (o['deliveryLongitude'] as num?)?.toDouble()
        : (o['pickupLongitude'] as num?)?.toDouble();
    if (targetLat == null || targetLng == null) return null;
    final km = _haversineKm(_driverPos!.latitude, _driverPos!.longitude, targetLat, targetLng);
    final mins = (km / 25 * 60).round(); // ~25 km/h en ville
    if (km < 1) return '${(km * 1000).round()} m · ~$mins min';
    return '${km.toStringAsFixed(1)} km · ~$mins min';
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    const deg2rad = 3.141592653589793 / 180;
    final dLat = (lat2 - lat1) * deg2rad;
    final dLng = (lng2 - lng1) * deg2rad;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * deg2rad) * cos(lat2 * deg2rad) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final o        = _order ?? widget.initialOrder ?? {};
    final pLat     = o['pickupLatitude']    as double? ?? 14.6928;
    final pLng     = o['pickupLongitude']   as double? ?? -17.4467;
    final dLat     = o['deliveryLatitude']  as double? ?? 14.6928;
    final dLng     = o['deliveryLongitude'] as double? ?? -17.4467;
    final pickup   = _short(o['pickupAddress']   as String?);
    final delivery = _short(o['deliveryAddress'] as String?);
    final price    = (o['price'] as num?) ?? 0;
    final needsMerchantPayment =
        o['paymentMode'] == 'merchant' && o['paymentStatus'] != 'PAID';
    final driver   = o['driver'] as Map<String, dynamic>?;
    final dName    = driver?['name'] as String? ?? 'Livreur DEM';
    final dPhone   = driver?['phone'] as String?;
    final (statusLabel, statusColor) = _statusInfo;

    // Marqueurs
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pLat, pLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(dLat, dLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      if (_driverPos != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPos!,
          icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        ),
    };

    final initTarget = _driverPos ?? LatLng((pLat + dLat) / 2, (pLng + dLng) / 2);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Carte ────────────────────────────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: initTarget, zoom: 14),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              style: _mapStyle,
              markers: markers,
              polylines: _displayRoute.isNotEmpty
                  ? {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: _displayRoute,
                        color: AppColors.primary,
                        width: 4,
                      ),
                    }
                  : {},
              onMapCreated: (c) {
                _mapCtrl = c;
                if (_driverPos == null) {
                  final sw = LatLng(min(pLat, dLat), min(pLng, dLng));
                  final ne = LatLng(max(pLat, dLat), max(pLng, dLng));
                  c.animateCamera(
                    CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 80),
                  );
                }
              },
            ),
          ),

          // ── Dégradé haut ─────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0, height: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.background.withValues(alpha: 0.9), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── App bar ───────────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12, right: 12,
            child: Row(children: [
              _MapBtn(
                icon: Icons.arrow_back,
                onTap: () => context.go('/dem-pro/home'),
              ),
              const Spacer(),
              _MapBtn(
                icon: Icons.my_location,
                onTap: () {
                  final pos = _driverPos ?? LatLng(pLat, pLng);
                  _mapCtrl?.animateCamera(CameraUpdate.newLatLng(pos));
                },
              ),
            ]),
          ),

          // ── Panel bas ─────────────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Pill drag indicator
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // ── Statut ─────────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    statusLabel,
                    textAlign: TextAlign.center,
                    style: ClientText.bodyStrong.copyWith(color: statusColor),
                  ),
                ),
                if (_distanceInfo != null) ...[
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.near_me_outlined, color: AppColors.primary, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      _distanceInfo!,
                      style: ClientText.bodyStrong.copyWith(color: AppColors.primary),
                    ),
                  ]),
                ],
                const SizedBox(height: 16),

                // ── Livreur ────────────────────────────────────────────────
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _initials(dName),
                        style: ClientText.title.copyWith(color: AppColors.primary, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(dName,
                          style: ClientText.subtitle.copyWith(color: AppColors.textPrimary)),
                      Text('Livreur DEM',
                          style: ClientText.label.copyWith(color: AppColors.textSecondary)),
                    ]),
                  ),
                ]),
                if (dPhone != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _ActionChip(
                        icon: Icons.chat_bubble_outline,
                        label: 'WhatsApp',
                        onTap: () => _whatsAppDriver(dPhone),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionChip(
                        icon: Icons.phone_outlined,
                        label: 'Appeler',
                        onTap: _callDriver,
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 16),

                // ── Adresses ───────────────────────────────────────────────
                _AddressCard(pickup: pickup, delivery: delivery),
                const SizedBox(height: 14),

                // ── Prix ───────────────────────────────────────────────────
                Row(children: [
                  const Icon(Icons.payments_outlined,
                      color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 6),
                  Builder(builder: (context) {
                    final charge = clientChargeFor(o);
                    if (charge >= price.round()) {
                      return Text(
                        formatFcfa(price.toInt()),
                        style: ClientText.subtitle.copyWith(color: AppColors.textPrimary),
                      );
                    }
                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(formatFcfa(price.toInt()),
                          style: ClientText.label.copyWith(decoration: TextDecoration.lineThrough)),
                      const SizedBox(width: 6),
                      Text(formatFcfa(charge),
                          style: ClientText.subtitle.copyWith(color: AppColors.success)),
                    ]);
                  }),
                  const Spacer(),
                  Text(
                    '#${widget.orderId.substring(0, 8).toUpperCase()}',
                    style: ClientText.label.copyWith(color: AppColors.textSecondary),
                  ),
                ]),
                if (needsMerchantPayment) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _payOnline,
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: Text('Payer via SamirPay', style: ClientText.bodyStrong.copyWith(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _shareOrder,
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: Text('Partager le suivi', style: ClientText.bodyStrong.copyWith(color: AppColors.textPrimary)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _MapBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Icon(icon, color: AppColors.textPrimary, size: 20),
    ),
  );
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: AppColors.primary, size: 14),
        const SizedBox(width: 5),
        Text(label,
            style: ClientText.label.copyWith(color: AppColors.primary)),
      ]),
    ),
  );
}

class _AddressCard extends StatelessWidget {
  final String pickup;
  final String delivery;
  const _AddressCard({required this.pickup, required this.delivery});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.radio_button_on, color: AppColors.success, size: 13),
        const SizedBox(width: 10),
        Expanded(
          child: Text(pickup,
              style: ClientText.body.copyWith(color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 6, top: 3, bottom: 3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(width: 1.5, height: 10, color: AppColors.card),
        ),
      ),
      Row(children: [
        const Icon(Icons.location_on, color: AppColors.error, size: 13),
        const SizedBox(width: 10),
        Expanded(
          child: Text(delivery,
              style: ClientText.body.copyWith(color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    ]),
  );
}
