import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_exception.dart';
import '../../core/services/location_queue_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/theme/map_theme_provider.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/call_button.dart';
import '../../shared/widgets/gradient_dialog.dart';
import '../../shared/widgets/gradient_sheet.dart';
import '../../shared/widgets/operator_picker_sheet.dart';
import '../../shared/widgets/samirpay_payment_sheet.dart';
import '../../shared/widgets/swipe_to_confirm.dart';
import '../deliveries/providers/orders_provider.dart';
import 'navigation/alert_banner.dart';
import 'navigation/alert_manager.dart';
import 'navigation/directions_service.dart';
import 'navigation/driver_marker_icon.dart';
import 'navigation/map_theme.dart';
import 'navigation/navigation_service.dart';
import 'navigation/route_tracker.dart';
import 'navigation/voice_nav_service.dart';

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
  late final _locationQueue = LocationQueueService(
    ref.read(ordersRepositoryProvider),
  );

  // ── Batch state ───────────────────────────────────────────────────────────
  late List<Map<String, dynamic>> _stops;
  bool _isPickedUp = false;
  int _currentStopIndex = 0;
  bool _loading = false;
  // Incrémenté à l'échec d'une action — force la réinitialisation visuelle
  // du curseur "glisser pour confirmer" (sinon il resterait verrouillé).
  int _swipeTick = 0;
  StreamSubscription<Map<String, dynamic>>? _cancelledSub;

  // ── Route ─────────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  List<LatLng> _displayRoute = [];
  int _lastTrimIdx = 0;
  bool _loadingRoute = true;
  bool _isRerouting = false;
  DateTime? _lastReroute;

  // ── Alertes ───────────────────────────────────────────────────────────────
  var _alertManager = AlertManager();
  String? _currentAlert;
  AlertPriority? _alertPriority;
  Timer? _alertTimer;

  // ── Guidage vocal ──────────────────────────────────────────────────────────
  bool _voiceNavEnabled = true;

  // ── Preuve de livraison (photo optionnelle, par arrêt) ────────────────────
  final _proofPicker = ImagePicker();
  File? _proofPhoto;

  Future<void> _pickProofPhoto() async {
    final xfile = await _proofPicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (xfile != null && mounted) {
      setState(() => _proofPhoto = File(xfile.path));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final orders =
        (widget.batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _stops = List.from(orders)
      ..sort(
        (a, b) => ((a['sequenceIndex'] as num?) ?? 0).compareTo(
          (b['sequenceIndex'] as num?) ?? 0,
        ),
      );
    buildDriverMarkerIcon().then((icon) {
      if (mounted) setState(() => _driverIcon = icon);
    });
    _loadMapStyle();
    _startNavigation();
    _listenForCancellations();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    _cancelledSub?.cancel();
    _alertTimer?.cancel();
    _mapController?.dispose();
    VoiceNavService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _driverPosition != null) {
      _loadRoute();
    }
  }

  /// Un client peut annuler une commande alors que le livreur est déjà en
  /// tournée vers d'autres arrêts — sans ça, il continue de naviguer vers un
  /// arrêt annulé sans jamais être prévenu (contrairement à la course simple).
  void _listenForCancellations() {
    _cancelledSub = SocketService.instance.onOrderCancelled.listen((data) {
      if (!mounted) return;
      final cancelledId = data['orderId'] as String?;
      final index = _stops.indexWhere((s) => s['id'] == cancelledId);
      if (index == -1) return;
      final reason =
          data['reason'] as String? ??
          'Un arrêt de cette tournée a été annulé.';

      if (_isPickedUp && index == _currentStopIndex) {
        showGradientInfoDialog(
          context,
          title: 'Arrêt annulé',
          message: reason,
          icon: Icons.cancel_outlined,
          actionLabel: index < _stops.length - 1
              ? 'Arrêt suivant'
              : 'Terminer la tournée',
          onAction: () => _removeCancelledStop(index),
        );
      } else {
        showDemToast(context, 'Un arrêt de la tournée a été annulé et retiré.');
        _removeCancelledStop(index);
      }
    });
  }

  void _removeCancelledStop(int index) {
    setState(() {
      _stops.removeAt(index);
      if (index < _currentStopIndex) _currentStopIndex--;
    });
    if (_stops.isEmpty || (_isPickedUp && _currentStopIndex >= _stops.length)) {
      NotificationService.cancelNotification(9998);
      if (_stops.isEmpty) {
        if (mounted) context.go('/driver/home');
      } else {
        _showCompletionDialog();
      }
      return;
    }
    if (_isPickedUp) {
      setState(() {
        _autoFollow = true;
        _alertManager = AlertManager();
      });
      _fitToTarget();
      _loadRoute();
    }
  }

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _startNavigation() async {
    await VoiceNavService.instance.init();
    if (mounted)
      setState(() => _voiceNavEnabled = VoiceNavService.instance.enabled);
    VoiceNavService.instance.onPhaseChanged(isPickedUp: _isPickedUp);

    final fresh = await NavigationService.requestAndGetPosition();
    if (!mounted) return;
    if (fresh != null) {
      setState(() => _driverPosition = fresh);
      _centerOn(fresh);
    } else {
      NavigationService.promptOpenSettingsIfPermanentlyDenied(context);
    }

    await _loadRoute();

    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  Future<void> _loadRoute() async {
    final origin = _driverPosition != null
        ? LatLng(_driverPosition!.latitude, _driverPosition!.longitude)
        : _targetLatLng;
    final destination = _targetLatLng;

    try {
      final result = await DirectionsService.getRoute(
        origin: origin,
        destination: destination,
        apiKey: AppConfig.mapsApiKey,
      );
      if (!mounted) return;
      setState(() {
        _routePoints = result.points;
        _displayRoute = result.points;
        _lastTrimIdx = 0;
      });
      if (result.steps.isNotEmpty) {
        VoiceNavService.instance.updateSteps(result.steps);
      }
    } catch (_) {
      // Best-effort : la ligne droite (marqueurs seuls) reste affichée.
    } finally {
      if (mounted)
        setState(() {
          _loadingRoute = false;
          _isRerouting = false;
        });
    }
  }

  // Recale la position GPS sur le tracé (projection sur segment, pas juste
  // sur les sommets) — voir RouteTracker. Réutilisé à la fois pour
  // raccourcir le tracé affiché et pour détecter une déviation.
  RouteProjection? _matchRoute(LatLng driverLatLng) {
    if (_routePoints.isEmpty) return null;
    return RouteTracker.closestMatch(_routePoints, driverLatLng, _lastTrimIdx);
  }

  void _trimDisplayRoute(RouteProjection match) {
    if (match.segmentIndex < _lastTrimIdx) return;
    _lastTrimIdx = match.segmentIndex;
    if (mounted) {
      setState(
        () => _displayRoute = RouteTracker.remainingRoute(_routePoints, match),
      );
    }
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _driverPosition = position);
    if (_autoFollow) _centerOn(position);
    _maybeEmitLocation(position);
    final driverLatLng = LatLng(position.latitude, position.longitude);
    final routeMatch = _matchRoute(driverLatLng);
    if (routeMatch != null) _trimDisplayRoute(routeMatch);
    VoiceNavService.instance.onPositionUpdate(position);

    // Alertes de proximité
    final dist = NavigationService.distanceTo(position, _targetLatLng);
    final alert = _alertManager.check(dist, isPickupPhase: !_isPickedUp);
    if (alert != null) {
      _showAlert(alert.message, alert.priority);
      VoiceNavService.instance.speakDirect(alert.message);
    }

    // Recalcul si déviation > 60m depuis la route — limité à 1/15s.
    // Réutilise la distance perpendiculaire déjà calculée par _matchRoute.
    if (_routePoints.isNotEmpty && !_loadingRoute && routeMatch != null) {
      final now = DateTime.now();
      if (_lastReroute == null ||
          now.difference(_lastReroute!).inSeconds >= 15) {
        if (routeMatch.distanceMeters > 60) {
          _lastReroute = now;
          _lastTrimIdx = 0;
          setState(() => _isRerouting = true);
          _loadRoute();
        }
      }
    }
  }

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

  void _maybeEmitLocation(Position pos) {
    final now = DateTime.now();
    if (_lastLocationEmit == null ||
        now.difference(_lastLocationEmit!).inSeconds >= 10) {
      _lastLocationEmit = now;
      _locationQueue.emit(pos.latitude, pos.longitude);
    }
  }

  void _centerOn(Position pos) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 15.5),
      ),
    );
  }

  double? get _distanceToTarget => _driverPosition == null
      ? null
      : NavigationService.distanceTo(_driverPosition!, _targetLatLng);

  // Distance sous laquelle la confirmation "récupéré"/"livré" est permise —
  // évite les clics accidentels loin du point qui font perdre l'itinéraire
  // (retours livreurs : swipe déclenché par erreur en poche, sans être arrivé).
  static const double _confirmRadiusMeters = 500;

  bool get _canConfirmAction =>
      _distanceToTarget != null && _distanceToTarget! <= _confirmRadiusMeters;

  // 0..1 : progression visuelle de l'anneau autour du cadenas tant que hors
  // zone — 0 à 2x le rayon de confirmation, 1 pile au seuil des 500 m.
  double get _lockProgress {
    final d = _distanceToTarget;
    if (d == null) return 0;
    const farRef = _confirmRadiusMeters * 2;
    return (1 - (d / farRef)).clamp(0.0, 1.0);
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
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(
            _driverPosition!.latitude,
            _driverPosition!.longitude,
          ),
          icon:
              _driverIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          rotation: _driverPosition!.heading,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 2,
        ),
      );
    }
    markers.add(
      Marker(
        markerId: const MarkerId('target'),
        position: _targetLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _isPickedUp ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
        ),
        zIndexInt: 1,
      ),
    );
    return markers;
  }

  Set<Polyline> get _polylines {
    if (_displayRoute.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _displayRoute,
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

  void _fitToTarget() {
    if (_driverPosition == null) return;
    final target = _targetLatLng;
    final driver = LatLng(
      _driverPosition!.latitude,
      _driverPosition!.longitude,
    );
    if ((driver.latitude - target.latitude).abs() < 0.0001 &&
        (driver.longitude - target.longitude).abs() < 0.0001) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      return;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(
        driver.latitude < target.latitude ? driver.latitude : target.latitude,
        driver.longitude < target.longitude
            ? driver.longitude
            : target.longitude,
      ),
      northeast: LatLng(
        driver.latitude > target.latitude ? driver.latitude : target.latitude,
        driver.longitude > target.longitude
            ? driver.longitude
            : target.longitude,
      ),
    );
    setState(() => _autoFollow = false);
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  Future<void> _confirmPickup() async {
    if (_stops.isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(ordersRepositoryProvider)
          .pickupOrder(_stops[0]['id'] as String);
      NotificationService.showOngoingNotification(
        id: 9998,
        title: 'Tournée en cours',
        body:
            'Arrêt 1/${_stops.length} : ${_stops[0]['deliveryAddress'] ?? ''}',
      );
      setState(() {
        _isPickedUp = true;
        _currentStopIndex = 0;
        _alertManager = AlertManager();
      });
      VoiceNavService.instance.onPhaseChanged(isPickedUp: true);
      _fitToTarget();
      _loadRoute();
    } catch (e) {
      if (mounted) {
        setState(() => _swipeTick++);
        showDemToast(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDelivery() async {
    final stop = _stops[_currentStopIndex];
    setState(() => _loading = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);
      await repo.deliverOrder(stop['id'] as String);
      // Photo optionnelle — jamais bloquante, la livraison de cet arrêt est
      // déjà confirmée. Réinitialisée pour laisser reprendre une photo au
      // prochain arrêt.
      final photo = _proofPhoto;
      if (photo != null) {
        repo
            .uploadProofPhoto(stop['id'] as String, photo)
            .catchError((_) => <String, dynamic>{});
      }
      _proofPhoto = null;
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
          _alertManager = AlertManager();
        });
        VoiceNavService.instance.speakDirect(
          'Livraison confirmée. Direction l\'arrêt suivant.',
        );
        _fitToTarget();
        _loadRoute();
      } else {
        NotificationService.cancelNotification(9998);
        if (mounted) _showCompletionDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _swipeTick++);
        showDemToast(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCompletionDialog() {
    int selectedRating = 5;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: AppColors.gradientDialog,
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
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'Tournée terminée !',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Tous les ${_stops.length} arrêts ont été livrés avec succès.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Notez le client',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
                          star <= selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: star <= selectedRating
                              ? AppColors.ratingGold
                              : Colors.white38,
                          size: 32,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final batchId = widget.batch['id'] as String?;
                      final clientId = widget.batch['clientId'] as String?;
                      if (batchId != null &&
                          clientId != null &&
                          selectedRating > 0) {
                        try {
                          final firstOrderId = _stops.isNotEmpty
                              ? _stops.first['id'] as String?
                              : null;
                          if (firstOrderId != null) {
                            await ref
                                .read(ordersRepositoryProvider)
                                .rateDriver(
                                  orderId: firstOrderId,
                                  driverId: clientId,
                                  score: selectedRating,
                                );
                          }
                        } catch (_) {}
                      }
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      context.go('/driver/home');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Terminer',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

  Future<void> _openMaps() async {
    final t = _targetLatLng;
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${t.latitude},${t.longitude}&travelmode=two-wheeler',
    );
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  void _callReceiver() {
    if (!_isPickedUp || _currentStopIndex >= _stops.length) return;
    final phone = _stops[_currentStopIndex]['receiverPhone'] as String?;
    if (phone == null || phone.isEmpty) return;
    launchUrl(Uri.parse('tel:$phone'));
  }

  void _callClient() {
    final phone =
        widget.batch['clientPhone'] as String? ??
        (widget.batch['client'] as Map?)?['phone'] as String?;
    if (phone == null || phone.isEmpty) return;
    launchUrl(Uri.parse('tel:$phone'));
  }

  String? get _clientPhone =>
      widget.batch['clientPhone'] as String? ??
      (widget.batch['client'] as Map?)?['phone'] as String?;

  String? get _clientName =>
      widget.batch['clientName'] as String? ??
      (widget.batch['client'] as Map?)?['name'] as String?;

  // Affiche le QR SamirPay pour l'arrêt en cours — même logique que sur
  // l'écran de course simple (active_order_screen.dart), adaptée à l'arrêt
  // actuellement servi plutôt qu'à une commande unique.
  Future<void> _openPaymentQr() async {
    if (_currentStopIndex >= _stops.length) return;
    final stop = _stops[_currentStopIndex];
    final orderId = stop['id'] as String?;
    if (orderId == null) return;
    final estimatedAmount = clientChargeFor(stop);

    final operatorName = await chooseOperator(
      context,
      title: 'Le client paie avec',
    );
    if (operatorName == null || !mounted) return;

    await SamirpayPaymentSheet.show(
      context,
      amount: estimatedAmount,
      title: 'Paiement de l\'arrêt ${_currentStopIndex + 1}',
      initPayment: () =>
          ref.read(ordersRepositoryProvider).payOnline(orderId, operatorName),
      confirmationStream: SocketService.instance.onOrderPaymentConfirmed.where(
        (event) => event['orderId'] == orderId,
      ),
      onSuccess: () => showDemToast(context, 'Paiement confirmé !'),
      displayOnly: true,
    );
  }

  Future<void> _confirmExit() async {
    final router = GoRouter.of(context);
    final confirmed = await showGradientConfirmDialog(
      context,
      title: 'Quitter la tournée ?',
      message:
          'La tournée est toujours en cours.\nVous pourrez y revenir depuis l\'accueil.',
      cancelLabel: 'Rester',
      confirmLabel: 'Quitter',
    );
    if (confirmed == true) router.go('/driver/home');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: Stack(
          children: [
            // ── Carte ─────────────────────────────────────────────────────────
            SizedBox.expand(
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _dakarBatch,
                  zoom: 14,
                ),
                onMapCreated: (c) {
                  _mapController = c;
                  if (_driverPosition != null) _centerOn(_driverPosition!);
                },
                style: _mapStyle,
                markers: _markers,
                polylines: _polylines,
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

            // ── Bannière d'alerte (glisse depuis le haut) ──────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              top: _currentAlert != null ? 0 : -120,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _currentAlert != null
                    ? AlertBanner(
                        message: _currentAlert!,
                        priority: _alertPriority ?? AlertPriority.low,
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // ── Bouton guidage vocal ────────────────────────────────────────────
            Positioned(
              right: 16,
              bottom: 230,
              child: GestureDetector(
                onTap: () async {
                  await VoiceNavService.instance.toggle();
                  if (mounted)
                    setState(
                      () => _voiceNavEnabled = VoiceNavService.instance.enabled,
                    );
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _voiceNavEnabled ? AppColors.primary : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(
                    _voiceNavEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    color: _voiceNavEnabled ? Colors.white : Colors.grey,
                    size: 22,
                  ),
                ),
              ),
            ),

            // ── Header ────────────────────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    // Progress badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.route,
                            color: AppColors.accentIndigo,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isPickedUp
                                ? 'Arrêt ${_currentStopIndex + 1} / ${_stops.length}'
                                : 'Récupération',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Paiement en ligne de l'arrêt en cours — pertinent seulement
                    // une fois le colis récupéré (chaque arrêt a alors son propre
                    // montant/destinataire ; avant récupération, il n'y a qu'un
                    // point de départ partagé par toute la tournée).
                    if (_isPickedUp && _currentStopIndex < _stops.length) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _openPaymentQr,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.qr_code_2_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                    // Recenter button when camera drifted
                    if (!_autoFollow) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          setState(() => _autoFollow = true);
                          if (_driverPosition != null)
                            _centerOn(_driverPosition!);
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
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: AppColors.accentIndigo,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
                            ? AppColors.driverAccentDone
                            : current
                            ? AppColors.accentIndigo
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
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    return GradientSheet(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewPadding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetDragHandle(),
          if (!_isPickedUp)
            ..._buildPickupContent()
          else
            ..._buildDeliveryContent(),
        ],
      ),
    );
  }

  int get _totalTourPrice =>
      _stops.fold(0, (s, o) => s + ((o['price'] as num?)?.toInt() ?? 0));

  int get _remainingTourPrice => _stops
      .skip(_currentStopIndex)
      .fold(0, (s, o) => s + ((o['price'] as num?)?.toInt() ?? 0));

  List<Widget> _buildPickupContent() {
    final address = widget.batch['pickupAddress'] as String? ?? '';
    return [
      Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Récupérer les colis',
                  style: ClientText.subtitle.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_stops.length} arrêt${_stops.length > 1 ? 's' : ''} à livrer',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          _MapBtn(onTap: _openMaps),
          if (_clientPhone != null && _clientPhone!.isNotEmpty) ...[
            const SizedBox(width: 8),
            CallButton(onTap: _callClient, size: 44),
          ],
        ],
      ),
      const SizedBox(height: 14),
      _AddressCard(
        icon: Icons.circle,
        label: 'Point de départ',
        address: address,
        receiverName: _clientName,
      ),
      // Aperçu de toute la tournée avant même de partir — jusqu'ici le
      // livreur ne voyait qu'un compteur ("3 arrêts à livrer"), jamais les
      // adresses, impossible de se projeter sur le trajet à venir.
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _stops.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i < _stops.length - 1 ? 8 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: AppColors.accentIndigo.withValues(alpha: 0.20),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: AppColors.accentIndigo,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (_stops[i]['deliveryAddress'] as String?) ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: Colors.white24),
            ),
            Row(
              children: [
                const Text(
                  'Total de la tournée',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '$_totalTourPrice FCFA',
                  style: const TextStyle(
                    color: AppColors.accentIndigo,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
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
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  if (_clientName != null) ...[
                    Text(
                      _clientName!,
                      style: ClientText.body.copyWith(color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _clientPhone!,
                    style: ClientText.body.copyWith(
                      color: AppColors.accentIndigo,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.phone_outlined,
                    color: AppColors.accentIndigo,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 14),
      SwipeToConfirm(
        key: ValueKey('pickup-$_swipeTick'),
        label: 'Glissez : colis récupérés',
        lockedLabel: _distanceToTarget != null
            ? 'Trop loin (${NavigationService.formatDistance(_distanceToTarget!)})'
            : 'Localisation requise',
        enabled: _canConfirmAction,
        lockProgress: _lockProgress,
        onLockedTap: () => showDemToast(
          context,
          'Rapprochez-vous à moins de ${_confirmRadiusMeters.round()} m du point de collecte pour confirmer.',
          isError: true,
        ),
        onConfirmed: _confirmPickup,
        loading: _loading,
        trackColor: Colors.white,
        thumbColor: AppColors.primaryMid,
        iconColor: Colors.white,
        labelColor: AppColors.primaryMid,
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
      Row(
        children: [
          // Stop number badge
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.accentIndigo.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.accentIndigo.withValues(alpha: 0.4),
              ),
            ),
            child: Center(
              child: Text(
                '${_currentStopIndex + 1}',
                style: const TextStyle(
                  color: AppColors.accentIndigo,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
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
                  style: ClientText.subtitle.copyWith(color: Colors.white),
                ),
                if (price > 0)
                  Text(
                    '$price FCFA',
                    style: ClientText.label.copyWith(
                      color: AppColors.accentIndigo,
                    ),
                  ),
                // Total restant sur la tournée — avant, seul le prix de cet
                // arrêt était visible pendant l'exécution, jamais un total.
                if (!isLastStop)
                  Text(
                    'Reste $_remainingTourPrice FCFA sur la tournée',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ),
          _MapBtn(onTap: _openMaps),
          if (receiverPhone != null && receiverPhone.isNotEmpty) ...[
            const SizedBox(width: 8),
            CallButton(onTap: _callReceiver, size: 44),
          ],
        ],
      ),
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
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  if (receiverName != null && receiverName.isNotEmpty) ...[
                    Text(
                      receiverName,
                      style: ClientText.body.copyWith(color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    receiverPhone,
                    style: ClientText.body.copyWith(
                      color: AppColors.accentIndigo,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.phone_outlined,
                    color: AppColors.accentIndigo,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: _pickProofPhoto,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              if (_proofPhoto != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _proofPhoto!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Photo ajoutée — appuyez pour la reprendre',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 18,
                ),
              ] else ...[
                const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ajouter une photo de preuve (optionnel)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      SwipeToConfirm(
        key: ValueKey('stop-$_currentStopIndex-$_swipeTick'),
        label: isLastStop
            ? 'Glissez : dernière livraison'
            : 'Glissez : livré, arrêt suivant',
        lockedLabel: _distanceToTarget != null
            ? 'Trop loin (${NavigationService.formatDistance(_distanceToTarget!)})'
            : 'Localisation requise',
        enabled: _canConfirmAction,
        lockProgress: _lockProgress,
        onLockedTap: () => showDemToast(
          context,
          'Rapprochez-vous à moins de ${_confirmRadiusMeters.round()} m du point de livraison pour confirmer.',
          isError: true,
        ),
        onConfirmed: _confirmDelivery,
        loading: _loading,
        trackColor: isLastStop ? AppColors.driverAccentDone : Colors.white,
        thumbColor: isLastStop ? Colors.white : AppColors.primaryMid,
        iconColor: isLastStop ? AppColors.driverAccentDone : Colors.white,
        labelColor: isLastStop ? Colors.white : AppColors.primaryMid,
      ),
    ];
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _MapBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _MapBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.8,
          ),
        ),
        child: const Icon(
          Icons.navigation_outlined,
          color: Colors.white,
          size: 20,
        ),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(icon, color: Colors.black87, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: ClientText.micro.copyWith(color: Colors.black45),
                    ),
                    Text(
                      address,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub != null && sub!.isNotEmpty)
                      Text(
                        sub!,
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (receiverName != null && receiverName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.black12, height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  color: Colors.black45,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  receiverName!,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
