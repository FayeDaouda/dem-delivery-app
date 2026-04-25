import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/map_theme_provider.dart';
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
  DateTime? _lastLocationEmit;

  // ── Route ─────────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  bool _loadingRoute = true;
  bool _isRerouting  = false;
  int? _etaSeconds;
  DateTime? _lastReroute;

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
    const double size = 128;
    const double cx = size / 2;
    const double cy = size / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Halo externe
    canvas.drawCircle(const Offset(cx, cy), 48, Paint()..color = const Color(0x2533BCD4));
    canvas.drawCircle(const Offset(cx, cy), 36, Paint()..color = const Color(0x4033BCD4));

    // Ombre portée
    final shadowPaint = Paint()
      ..color = const Color(0x6000B4C8)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    final shadowPath = Path()
      ..moveTo(cx, cy - 22 + 4)
      ..lineTo(cx + 16, cy + 14 + 4)
      ..lineTo(cx, cy + 8 + 4)
      ..lineTo(cx - 16, cy + 14 + 4)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // Cercle de base blanc 3D
    canvas.drawCircle(const Offset(cx, cy + 4), 20, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(const Offset(cx, cy + 4), 18, Paint()..color = const Color(0xFF1AB8CC));

    // Flèche de navigation avec gradient 3D
    final arrowPath = Path()
      ..moveTo(cx, cy - 22)
      ..lineTo(cx + 15, cy + 12)
      ..lineTo(cx, cy + 6)
      ..lineTo(cx - 15, cy + 12)
      ..close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(cx, cy - 22),
          const Offset(cx, cy + 12),
          [const Color(0xFF5EEEFF), const Color(0xFF00A8C0)],
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
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 56, height: 56);
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
    final bool isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);

    // GPS d'abord pour avoir une position de départ précise
    final initial = await NavigationService.requestAndGetPosition();
    if (initial != null && mounted) {
      setState(() => _driverPosition = initial);
    }

    // Route calculée depuis la vraie position du driver
    await _loadRoute();

    // Lance le suivi GPS continu
    _locationSub = NavigationService.positionStream.listen(_onPosition);

    // Mode conduite immédiat si position disponible
    if (_driverPosition != null && mounted) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _recenter();
      });
    }
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
      _routePoints  = result.points;
      _etaSeconds   = result.durationSeconds;
      _loadingRoute = false;
      _isRerouting  = false;
    });
  }

  // Zoom 18 à l'arrêt → 15 à 120 km/h (décroissance linéaire)
  static double _zoomForSpeed(double speedMs) {
    if (speedMs < 0) return 18.0;
    final kmh = (speedMs * 3.6).clamp(0.0, 120.0);
    return 18.0 - (kmh / 120.0) * 3.0;
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
            zoom: _zoomForSpeed(position.speed),
            bearing: position.heading,
            tilt: 65,
          ),
        ),
      );
    }

    // Émet la position au client toutes les 10s
    final now = DateTime.now();
    if (_lastLocationEmit == null || now.difference(_lastLocationEmit!).inSeconds >= 10) {
      _lastLocationEmit = now;
      final orderId = _order['id'] as String?;
      if (orderId != null) {
        SocketService.instance.emitDriverLocation(position.latitude, position.longitude, orderId);
      }
    }

    // Alertes de proximité
    final dist = _distanceToTarget;
    if (dist != null) {
      final alert = _alertManager.check(dist, isPickupPhase: !_isPickedUp);
      if (alert != null) _showAlert(alert.message, alert.priority);
    }

    // Recalcul de route si déviation > 50m et dernier recalcul > 20s
    if (_routePoints.isNotEmpty && !_loadingRoute) {
      final now2 = DateTime.now();
      if (_lastReroute == null || now2.difference(_lastReroute!).inSeconds >= 20) {
        final driverLatLng = LatLng(position.latitude, position.longitude);
        double minDist = double.infinity;
        for (final pt in _routePoints) {
          final d = Geolocator.distanceBetween(
              driverLatLng.latitude, driverLatLng.longitude, pt.latitude, pt.longitude);
          if (d < minDist) minDist = d;
        }
        if (minDist > 50) {
          _lastReroute = now2;
          setState(() => _isRerouting = true);
          _loadRoute();
        }
      }
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
  bool get _isDevOrder => _order['id']?.toString().startsWith('dev-') ?? false;

  Future<void> _pickup() async {
    if (_isDevOrder) {
      setState(() => _order = {..._order, 'status': 'PICKED_UP'});
      await _loadRoute();
      return;
    }
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final updated = await repo.pickupOrder(_order['id']);
      // Fusionne : _order (conserve client/clientPhone) + updated (nouveau statut)
      setState(() => _order = {..._order, ...updated});
      await _loadRoute();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deliver() async {
    if (_isDevOrder) {
      setState(() => _order = {..._order, 'status': 'DELIVERED'});
      if (mounted) _showPaymentDialog();
      return;
    }
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final updated = await repo.deliverOrder(_order['id']);
      // Fusionne : _order (conserve client/clientPhone) + updated (nouveau statut)
      setState(() => _order = {..._order, ...updated});
      if (mounted) _showPaymentDialog();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ── Dialogue : paiement reçu ? ────────────────────────────────────────────
  void _showPaymentDialog() {
    final price = (_order['price'] as num?)?.toInt() ?? 0;
    final orderId = _order['id'] as String?;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialog) {
          bool confirming = false;
          String? errorMsg;

          // Appelé dans StatefulBuilder → setDialog pour rebuilder le dialog
          void confirm() async {
            setDialog(() { confirming = true; errorMsg = null; });
            // Capture avant les await pour éviter l'usage de BuildContext après gap async
            final nav       = Navigator.of(dialogCtx);
            final messenger = ScaffoldMessenger.of(context);
            bool ok = false;
            for (int i = 0; i < 2; i++) {
              if (i > 0) await Future.delayed(const Duration(seconds: 2));
              try {
                if (!_isDevOrder && orderId != null) {
                  await ref.read(ordersRepositoryProvider)
                      .confirmPayment(orderId, 'PAID');
                }
                ok = true;
                break;
              } catch (_) {}
            }
            if (!mounted) return;
            if (ok) {
              nav.pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(_isRide ? 'Course effectuée — paiement confirmé !' : 'Livraison effectuée — paiement confirmé !'),
                  ]),
                  backgroundColor: const Color(0xFF00C853),
                  duration: const Duration(seconds: 3),
                ),
              );
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) context.go(_homeRoute);
              });
            } else {
              setDialog(() {
                confirming = false;
                errorMsg = 'Erreur réseau. Réessayez ou contactez le support.';
              });
            }
          }

          return PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.payments_outlined, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Paiement reçu ?',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$price FCFA',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    const Text('Cash ou Mobile Money', style: TextStyle(fontSize: 13, color: Colors.white70)),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(errorMsg!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        // Problème
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: confirming ? null : () {
                              Navigator.of(dialogCtx).pop();
                              _showDisputeDialog();
                            },
                            icon: const Icon(Icons.warning_amber_outlined, size: 18),
                            label: const Text('Problème'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange,
                              side: const BorderSide(color: Colors.orange),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Oui, reçu
                        Expanded(
                          child: ElevatedButton(
                            onPressed: confirming ? null : confirm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C853),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: confirming
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline, size: 18),
                                      SizedBox(width: 6),
                                      Text('Oui, reçu', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Dialogue : signaler un problème de paiement ───────────────────────────
  void _showDisputeDialog() {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Décrire le problème',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'L\'admin sera notifié immédiatement.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ex: le client dit avoir payé par Wave mais je n\'ai rien reçu...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showPaymentDialog(); // retour en arrière
                      },
                      child: const Text('Retour',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final note = noteController.text.trim();
                        if (note.isEmpty) return;
                        Navigator.of(context).pop();
                        _confirmPayment('DISPUTED', note: note);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Signaler'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Appel API confirmation paiement ──────────────────────────────────────
  Future<void> _confirmPayment(String status, {String? note}) async {
    if (!_isDevOrder) {
      bool confirmed = false;
      for (int attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(seconds: 2));
        try {
          final repo = ref.read(ordersRepositoryProvider);
          await repo.confirmPayment(_order['id'], status, note: note);
          confirmed = true;
          break;
        } catch (e) {
          debugPrint('[PAYMENT] Erreur confirmPayment tentative $attempt: $e');
        }
      }
      if (!confirmed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Erreur : paiement non enregistré. Contactez le support.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 6),
            ),
          );
        }
        return; // ne pas naviguer tant que non confirmé
      }
    }
    if (status == 'PAID') {
      if (mounted) _showSuccessDialog();
    } else {
      // DISPUTED : message simple + retour accueil
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Problème signalé. L\'admin va prendre en charge.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) context.go(_homeRoute);
        });
      }
    }
  }

  void _showSuccessDialog() {
    final price = (_order['price'] as num?)?.toInt() ?? 0;
    int selectedRating = 5;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.92),
                  const Color(0xFF1A6B7A).withValues(alpha: 0.97),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
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
                Text(
                  _isRide ? 'Course effectuée !' : 'Livraison effectuée !',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$price FCFA encaissés',
                  style: const TextStyle(fontSize: 15, color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  _order['deliveryAddress'] ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white60),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                // ── Notation ──
                Text(
                  _isRide ? 'Notez votre course' : 'Notez votre livraison',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
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
                          color: star <= selectedRating
                              ? const Color(0xFFFFD700)
                              : Colors.white38,
                          size: 36,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go(_homeRoute);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Retour à l\'accueil',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isRide => _order['orderType'] == 'RIDE';

  /// Numéro du client — compatible format plat (dev) et imbriqué (API réelle)
  /// Dev order : _order['clientPhone'] = '+221...'
  /// API réelle : _order['client'] = { 'phone': '+221...' }
  String? get _clientPhone =>
      (_order['clientPhone'] as String?) ??
      ((_order['client'] as Map<String, dynamic>?)?['phone'] as String?);

  Future<void> _callPickup() async {
    final phone = _clientPhone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  String get _homeRoute => _isRide ? '/driver/thiak/home' : '/driver/home';

  // ── Carte : marqueurs ─────────────────────────────────────────────────────
  Set<Marker> get _markers {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _isRide ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueGreen,
        ),
        infoWindow: InfoWindow(
          title: _isRide ? 'Prise en charge' : 'Collecte',
          snippet: _order['pickupAddress'],
        ),
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
        color: _isRerouting
            ? MapTheme.routeColor.withValues(alpha: 0.4)
            : MapTheme.routeColor,
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
              initialCameraPosition: _driverPosition != null
                  ? CameraPosition(
                      target: LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
                      zoom: 17.5,
                      bearing: _driverPosition!.heading,
                      tilt: 55,
                    )
                  : CameraPosition(target: _pickupLatLng, zoom: 14),
              style: _mapStyle,
              onMapCreated: (controller) {
                _mapController = controller;
                Future.delayed(const Duration(milliseconds: 400), () {
                  if (!mounted) return;
                  if (_driverPosition != null) {
                    _recenter();
                  } else {
                    _fitBounds();
                  }
                });
              },
              onCameraMove: (_) {
                if (_autoFollow) setState(() => _autoFollow = false);
              },
              polylines: _polylines,
              markers: _markers,
              trafficEnabled: false,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              buildingsEnabled: true,
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
                      onTap: () => context.go(_homeRoute),
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
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewPadding.bottom + 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
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
                              isRide: _isRide,
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
                                  color: Colors.white,
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
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                NavigationService.formatDuration(_etaSeconds!),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const Text(
                                'ETA',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white70),
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
                    label: _isRide ? 'Prise en charge' : 'Collecte',
                    address: _order['pickupAddress'] ?? '',
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 9),
                    child: SizedBox(
                      height: 12,
                      child: VerticalDivider(
                          color: Colors.white38, thickness: 1.5),
                    ),
                  ),
                  // Pour Thiak Thiak : destination masquée avant prise en charge
                  if (_isRide && !_isPickedUp)
                    Row(
                      children: [
                        Icon(Icons.lock_outline,
                            color: Colors.white.withValues(alpha: 0.40), size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Destination révélée après prise en charge',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    _AddressRow(
                      icon: Icons.location_on,
                      iconColor: Colors.red,
                      label: _isRide ? 'Destination' : 'Livraison',
                      address: _order['deliveryAddress'] ?? '',
                    ),

                  const SizedBox(height: 12),

                  // Prix
                  Row(
                    children: [
                      const Icon(Icons.payments_outlined,
                          size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        '${((_order['price'] as num?)?.toInt() ?? 0)} FCFA',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Bouton action principal + cercle appel
                  if (!_isDelivered)
                    Row(
                      children: [
                        Expanded(
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
                              ? (_isRide ? 'Course terminée' : 'Livraison effectuée')
                              : (_isRide ? 'Passager à bord' : "J'ai récupéré le colis"),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                        // Cercle appel — visible jusqu'à livraison
                        if (_clientPhone != null) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _callPickup,
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00C853),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.phone, color: Colors.white, size: 24),
                            ),
                          ),
                        ],
                      ],
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
                      child: Center(
                        child: Text(
                          _isRide ? 'Course effectuée avec succès !' : 'Commande livrée avec succès !',
                          style: const TextStyle(
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
  final bool isRide;

  const _PhaseChip({required this.isPickedUp, required this.isDelivered, required this.isRide});

  @override
  Widget build(BuildContext context) {
    final (label, color) = isDelivered
        ? (isRide ? 'Course effectuée ✓' : 'Livraison effectuée ✓', const Color(0xFF00C853))
        : isPickedUp
            ? (isRide ? 'En route vers la destination' : 'En route vers la livraison', AppColors.primary)
            : (isRide ? 'En route vers le passager' : 'En route vers la collecte', Colors.orange);

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
                      color: Colors.white60,
                      fontWeight: FontWeight.w500)),
              Text(address,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}
