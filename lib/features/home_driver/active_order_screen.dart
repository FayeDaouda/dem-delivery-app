import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/theme/map_theme_provider.dart';
import 'navigation/map_theme.dart';
import '../deliveries/providers/orders_provider.dart';
import 'navigation/alert_banner.dart';
import 'navigation/alert_manager.dart';
import 'navigation/directions_service.dart';
import 'navigation/driver_marker_icon.dart';
import 'navigation/navigation_service.dart';
import 'navigation/route_tracker.dart';
import 'navigation/voice_nav_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../shared/widgets/address_row.dart';
import '../../shared/widgets/call_button.dart';
import '../../shared/widgets/gradient_dialog.dart';
import '../../shared/widgets/operator_picker_sheet.dart';
import '../../shared/widgets/payment_collection_dialog.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/samirpay_payment_sheet.dart';
import '../../shared/widgets/swipe_to_confirm.dart';
import '../../shared/widgets/support_report_sheet.dart';

class ActiveOrderScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  const ActiveOrderScreen({super.key, required this.order});

  @override
  ConsumerState<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends ConsumerState<ActiveOrderScreen>
    with WidgetsBindingObserver {
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
  DateTime? _lastNotifUpdate;
  double _smoothedHeading = 0;
  DateTime? _lastCameraUpdate;

  // ── Route ─────────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  List<LatLng> _displayRoute = [];
  int _lastTrimIdx = 0;
  bool _loadingRoute = true;
  bool _isRerouting = false;
  int? _etaSeconds;
  DateTime? _lastReroute;

  // ── Alertes ───────────────────────────────────────────────────────────────
  final _alertManager = AlertManager();
  String? _currentAlert;
  AlertPriority? _alertPriority;
  Timer? _alertTimer;

  StreamSubscription<Map<String, dynamic>>? _cancelledSub;

  // ── Guidage vocal ──────────────────────────────────────────────────────────
  bool _voiceNavEnabled = true;

  // ── Annulation livreur (1 min 30) ─────────────────────────────────────────
  Timer? _cancelWindowTimer;
  int _cancelSecondsLeft = 90;
  bool _driverCancelling = false;

  // ── Preuve de livraison (photo optionnelle) ───────────────────────────────
  final _proofPicker = ImagePicker();
  File? _proofPhoto;

  // ── Getters ───────────────────────────────────────────────────────────────
  double _parseCoord(dynamic val, [double fallback = 0.0]) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  LatLng get _pickupLatLng => LatLng(
    _parseCoord(_order['pickupLatitude']),
    _parseCoord(_order['pickupLongitude']),
  );

  LatLng get _deliveryLatLng => LatLng(
    _parseCoord(_order['deliveryLatitude']),
    _parseCoord(_order['deliveryLongitude']),
  );

  bool get _isPickedUp => _order['status'] == 'PICKED_UP';
  bool get _isDelivered => _order['status'] == 'DELIVERED';

  LatLng get _targetLatLng => _isPickedUp ? _deliveryLatLng : _pickupLatLng;

  double? get _distanceToTarget => _driverPosition == null
      ? null
      : NavigationService.distanceTo(_driverPosition!, _targetLatLng);

  // Distance sous laquelle la confirmation "récupéré"/"livré" est permise —
  // évite les clics accidentels loin du point qui font perdre l'itinéraire
  // (retours livreurs : swipe déclenché par erreur en poche, sans être arrivé).
  static const double _confirmRadiusMeters = 500;

  bool get _canConfirmAction =>
      _isDevOrder ||
      (_distanceToTarget != null && _distanceToTarget! <= _confirmRadiusMeters);

  // 0..1 : progression visuelle de l'anneau autour du cadenas tant que hors
  // zone — 0 à 2x le rayon de confirmation, 1 pile au seuil des 500 m.
  double get _lockProgress {
    final d = _distanceToTarget;
    if (d == null) return 0;
    const farRef = _confirmRadiusMeters * 2;
    return (1 - (d / farRef)).clamp(0.0, 1.0);
  }

  BitmapDescriptor? _driverIcon;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _order = widget.order;
    buildDriverMarkerIcon().then((icon) {
      if (mounted) setState(() => _driverIcon = icon);
    });
    _startNavigation();
    _startCancelWindow();

    final orderId = _order['id'] as String?;
    _cancelledSub = SocketService.instance.onOrderCancelled.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      final reason = data['reason'] as String? ?? 'Cette course a été annulée.';
      showGradientInfoDialog(
        context,
        title: 'Course annulée',
        message: reason,
        icon: Icons.cancel_outlined,
        actionLabel: 'Retour à l\'accueil',
        onAction: () {
          ref.read(availableOrdersProvider.notifier).clear();
          context.go('/driver/home');
        },
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelledSub?.cancel();
    _cancelWindowTimer?.cancel();
    _locationSub?.cancel();
    _alertTimer?.cancel();
    _mapController?.dispose();
    VoiceNavService.instance.dispose();
    super.dispose();
  }

  void _startCancelWindow() {
    final acceptedAt = _order['acceptedAt'] as String?;
    if (acceptedAt != null) {
      final elapsed = DateTime.now()
          .difference(DateTime.parse(acceptedAt))
          .inSeconds;
      _cancelSecondsLeft = (90 - elapsed).clamp(0, 90);
    }
    if (_cancelSecondsLeft <= 0 || _isPickedUp) return;
    _cancelWindowTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _cancelSecondsLeft--);
      if (_cancelSecondsLeft <= 0) _cancelWindowTimer?.cancel();
    });
  }

  Future<void> _driverCancel() async {
    final confirmed = await showGradientConfirmDialog(
      context,
      title: 'Annuler cette course ?',
      message:
          'La course sera re-dispatchée à un autre livreur. Cela affectera votre taux d\'acceptation.',
      cancelLabel: 'Continuer la course',
      confirmLabel: 'Annuler',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _driverCancelling = true);
    try {
      await ref
          .read(ordersRepositoryProvider)
          .driverCancelOrder(_order['id'] as String);
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).clear();
      context.go('/driver/home');
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _driverCancelling = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  /// Quand l'app revient au premier plan :
  /// 1. Reconnecte la socket si elle s'est déconnectée.
  /// 2. Réémet la position immédiatement (pas d'attente du prochain tick GPS).
  /// 3. Recalcule la route (le driver a peut-être bougé pendant l'absence).
  Future<void> _onResumed() async {
    // Reconnexion socket
    if (!SocketService.instance.isConnected) {
      final token = await _readToken();
      if (token != null) SocketService.instance.connect(token);
    }

    // Position immédiate → client
    if (_driverPosition != null && !_isDelivered) {
      final orderId = _order['id'] as String?;
      if (orderId != null) {
        SocketService.instance.emitDriverLocation(
          _driverPosition!.latitude,
          _driverPosition!.longitude,
          orderId,
        );
      }
    }

    // Recalcul de la route
    if (!_isDelivered) _loadRoute();
  }

  /// Lit le token JWT depuis le stockage local (SharedPreferences).
  Future<String?> _readToken() async {
    try {
      return await AuthStorage.getToken();
    } catch (_) {
      return null;
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  Future<void> _startNavigation() async {
    await VoiceNavService.instance.init();
    if (mounted)
      setState(() => _voiceNavEnabled = VoiceNavService.instance.enabled);
    VoiceNavService.instance.onPhaseChanged(isPickedUp: _isPickedUp);

    final bool isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);

    // GPS d'abord pour avoir une position de départ précise
    final initial = await NavigationService.requestAndGetPosition();
    if (initial != null && mounted) {
      setState(() => _driverPosition = initial);
      // Émet immédiatement la position au client — ne pas attendre le premier tick des 10s
      final orderId = _order['id'] as String?;
      if (orderId != null) {
        SocketService.instance.emitDriverLocation(
          initial.latitude,
          initial.longitude,
          orderId,
        );
      }
    } else if (mounted) {
      NavigationService.promptOpenSettingsIfPermanentlyDenied(context);
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
    final origin = _driverPosition != null
        ? LatLng(_driverPosition!.latitude, _driverPosition!.longitude)
        : (_isPickedUp ? _pickupLatLng : _pickupLatLng);
    final destination = _isPickedUp ? _deliveryLatLng : _pickupLatLng;

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
        _etaSeconds = result.durationSeconds;
        _loadingRoute = false;
      });
      if (result.steps.isNotEmpty) {
        VoiceNavService.instance.updateSteps(result.steps);
      }

      final dist = _distanceToTarget;
      if (dist != null) {
        final min = (dist / 416).round();
        final destName = _isPickedUp
            ? (_order['deliveryAddress'] ?? 'client')
            : (_order['pickupAddress'] ?? 'restaurant');
        final statusText = _isPickedUp
            ? 'En route vers la livraison'
            : 'En route vers la récupération';
        final etaText = min > 0 ? ' (~$min min)' : ' (Proche)';
        NotificationService.showOngoingNotification(
          id: 9999,
          title: statusText,
          body: '$destName$etaText',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ROUTE] Erreur calcul itinéraire: $e');
    } finally {
      // Garanti quoi qu'il arrive : exception, !mounted, succès
      if (mounted)
        setState(() {
          _loadingRoute = false;
          _isRerouting = false;
        });
    }
  }

  // Recale la position GPS sur le tracé (projection sur segment, pas juste
  // sur les sommets) — voir RouteTracker pour le détail. Réutilisé à la fois
  // pour raccourcir le tracé affiché et pour détecter une déviation, sur le
  // même calcul plutôt que deux recherches séparées.
  RouteProjection? _matchRoute(LatLng driverLatLng) {
    if (_routePoints.isEmpty) return null;
    return RouteTracker.closestMatch(_routePoints, driverLatLng, _lastTrimIdx);
  }

  void _trimDisplayRoute(RouteProjection match) {
    if (match.segmentIndex < _lastTrimIdx)
      return; // avance seulement, ne recule pas
    _lastTrimIdx = match.segmentIndex;
    if (mounted) {
      setState(
        () => _displayRoute = RouteTracker.remainingRoute(_routePoints, match),
      );
    }
  }

  // Zoom 18 à l'arrêt → 15 à 120 km/h (décroissance linéaire)
  static double _zoomForSpeed(double speedMs) {
    if (speedMs < 0) return 18.0;
    final kmh = (speedMs * 3.6).clamp(0.0, 120.0);
    return 18.0 - (kmh / 120.0) * 3.0;
  }

  // Lissage du cap : filtre passe-bas + gestion du wrap 0°/360°
  double _smoothHeading(double target) {
    if (target < 0)
      return _smoothedHeading; // heading invalide (arrêt) → on garde
    double diff = target - _smoothedHeading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (_smoothedHeading + diff * 0.25) % 360;
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _driverPosition = position);
    final driverLatLng = LatLng(position.latitude, position.longitude);
    final routeMatch = _matchRoute(driverLatLng);
    if (routeMatch != null) _trimDisplayRoute(routeMatch);
    VoiceNavService.instance.onPositionUpdate(position);

    // Auto-follow : caméra orientée dans la direction de déplacement
    if (_autoFollow && _mapController != null) {
      final now = DateTime.now();
      // Throttle à 350ms — évite d'annuler l'animation précédente
      if (_lastCameraUpdate == null ||
          now.difference(_lastCameraUpdate!).inMilliseconds >= 350) {
        _lastCameraUpdate = now;
        _smoothedHeading = _smoothHeading(position.heading);
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: _zoomForSpeed(position.speed),
              bearing: _smoothedHeading,
              tilt: 65,
            ),
          ),
        );
      }
    }

    // Émet la position au client toutes les 10s — stop après livraison
    final now = DateTime.now();
    if (!_isDelivered &&
        (_lastLocationEmit == null ||
            now.difference(_lastLocationEmit!).inSeconds >= 10)) {
      _lastLocationEmit = now;
      final orderId = _order['id'] as String?;
      if (orderId != null) {
        SocketService.instance.emitDriverLocation(
          position.latitude,
          position.longitude,
          orderId,
        );
      }

      // Notification persistante — throttle 60s
      final now2 = DateTime.now();
      if (_lastNotifUpdate == null ||
          now2.difference(_lastNotifUpdate!).inSeconds >= 60) {
        _lastNotifUpdate = now2;
        final dist2 = _distanceToTarget;
        if (dist2 != null) {
          final min = (dist2 / 416).round();
          final destName = _isPickedUp
              ? (_order['deliveryAddress'] ?? 'client')
              : (_order['pickupAddress'] ?? 'restaurant');
          final statusText = _isPickedUp
              ? 'En route vers la livraison'
              : 'En route vers la récupération';
          final etaText = min > 0 ? ' (~$min min)' : ' (Proche)';
          NotificationService.showOngoingNotification(
            id: 9999,
            title: statusText,
            body: '$destName$etaText',
          );
        }
      }
    }

    // Alertes de proximité
    final dist = _distanceToTarget;
    if (dist != null) {
      final alert = _alertManager.check(dist, isPickupPhase: !_isPickedUp);
      if (alert != null) {
        _showAlert(alert.message, alert.priority);
        VoiceNavService.instance.speakDirect(alert.message);
      }
    }

    // Recalcul si déviation > 60m depuis la route (couvre demi-tour et chemin alternatif)
    // Limité à 1 recalcul / 15s pour éviter les appels en rafale — réutilise
    // la distance perpendiculaire déjà calculée par _matchRoute ci-dessus,
    // fiable même sur un tracé très détaillé (pas de fenêtre bornée).
    if (_routePoints.isNotEmpty && !_loadingRoute && routeMatch != null) {
      final now2 = DateTime.now();
      if (_lastReroute == null ||
          now2.difference(_lastReroute!).inSeconds >= 15) {
        if (routeMatch.distanceMeters > 60) {
          _lastReroute = now2;
          _lastTrimIdx = 0; // reset trim pour nouvelle route
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
          bearing: _smoothedHeading,
          tilt: 55,
        ),
      ),
    );
  }

  // Affiche le QR SamirPay pour que l'expéditeur (à la récupération) ou le
  // destinataire (à la livraison) scanne et paie directement — alternative
  // au virement Wave/Orange envoyé au numéro du livreur.
  Future<void> _openPaymentQr() async {
    final orderId = _order['id'] as String?;
    if (orderId == null) return;
    final estimatedAmount = clientChargeFor(_order);

    final operatorName = await chooseOperator(
      context,
      title: 'Le client paie avec',
    );
    if (operatorName == null || !mounted) return;

    await SamirpayPaymentSheet.show(
      context,
      amount: estimatedAmount,
      title: 'Paiement de la course',
      initPayment: () =>
          ref.read(ordersRepositoryProvider).payOnline(orderId, operatorName),
      confirmationStream: SocketService.instance.onOrderPaymentConfirmed.where(
        (event) => event['orderId'] == orderId,
      ),
      onSuccess: () => showDemToast(context, 'Paiement confirmé !'),
      displayOnly: true,
    );
  }

  void _fitBounds() {
    final bounds = LatLngBounds(
      southwest: LatLng(
        [
          _pickupLatLng.latitude,
          _deliveryLatLng.latitude,
        ].reduce((a, b) => a < b ? a : b),
        [
          _pickupLatLng.longitude,
          _deliveryLatLng.longitude,
        ].reduce((a, b) => a < b ? a : b),
      ),
      northeast: LatLng(
        [
          _pickupLatLng.latitude,
          _deliveryLatLng.latitude,
        ].reduce((a, b) => a > b ? a : b),
        [
          _pickupLatLng.longitude,
          _deliveryLatLng.longitude,
        ].reduce((a, b) => a > b ? a : b),
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

  bool _actionLoading = false;
  // Incrémenté à l'échec d'une action — force la réinitialisation visuelle
  // du curseur "glisser pour confirmer" (sinon il resterait verrouillé).
  int _swipeTick = 0;

  Future<void> _pickup() async {
    if (_actionLoading) return;
    if (_isDevOrder) {
      setState(() => _order = {..._order, 'status': 'PICKED_UP'});
      await _loadRoute();
      return;
    }
    setState(() => _actionLoading = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final updated = await repo.pickupOrder(_order['id']);
      setState(() => _order = {..._order, ...updated});
      VoiceNavService.instance.onPhaseChanged(isPickedUp: true);
      await _loadRoute();
    } catch (e) {
      if (mounted) {
        setState(() => _swipeTick++);
        showDemToast(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _pickProofPhoto() async {
    final xfile = await _proofPicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (xfile != null && mounted) {
      setState(() => _proofPhoto = File(xfile.path));
    }
  }

  Future<void> _deliver() async {
    if (_actionLoading) return;
    if (_isDevOrder) {
      setState(() => _order = {..._order, 'status': 'DELIVERED'});
      if (mounted) _showPaymentDialog();
      return;
    }
    setState(() => _actionLoading = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final updated = await repo.deliverOrder(_order['id']);
      // Fusionne : _order (conserve client/clientPhone) + updated (nouveau statut)
      setState(() => _order = {..._order, ...updated});
      // Photo optionnelle — jamais bloquante : la livraison est déjà
      // confirmée, un échec d'upload ne doit surtout pas empêcher le
      // livreur d'avancer.
      final photo = _proofPhoto;
      if (photo != null) {
        repo
            .uploadProofPhoto(_order['id'], photo)
            .catchError((_) => <String, dynamic>{});
      }
      if (mounted) _showPaymentDialog();
    } catch (e) {
      if (mounted) {
        setState(() => _swipeTick++);
        showDemToast(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // ── Après livraison : déjà payé (en ligne/DEM Pro merchant) → juste
  // informer ; sinon demander comment le client règle (cash ou en ligne).
  void _showPaymentDialog() {
    if (_order['paymentStatus'] == 'PAID') {
      _showAlreadyPaidDialog();
    } else {
      _showChoosePaymentModeDialog();
    }
  }

  void _showAlreadyPaidDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.success,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isRide ? 'Course payée' : 'Livraison payée',
                style: ClientText.title.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'Le paiement a déjà été réglé en ligne — rien à collecter auprès du client.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'OK',
                  leadingIcon: Icons.check_circle_outline,
                  color: AppColors.success,
                  height: 48,
                  onTap: () {
                    Navigator.of(dialogCtx).pop();
                    showDemToast(
                      context,
                      _isRide ? 'Course effectuée !' : 'Livraison effectuée !',
                    );
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) context.go(_homeRoute);
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dialogue : comment le client règle-t-il ? (cash ou en ligne) ─────────
  void _showChoosePaymentModeDialog() {
    final orderId = _order['id'] as String?;
    if (orderId == null) return;
    showPaymentCollectionDialog(
      context,
      ref,
      orderId: orderId,
      price: clientChargeFor(_order),
      isRide: _isRide,
      simulate: _isDevOrder,
      successMessage: _isRide
          ? 'Course effectuée — paiement confirmé !'
          : 'Livraison effectuée — paiement confirmé !',
      onDispute: _showDisputeDialog,
      onPaid: () {
        if (mounted) context.go(_homeRoute);
      },
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
            gradient: AppColors.gradientDialog,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Décrire le problème',
                style: ClientText.subtitle.copyWith(color: Colors.white),
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
                  hintText:
                      'Ex: le client dit avoir payé par Wave mais je n\'ai rien reçu...',
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                  ),
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
                      child: const Text(
                        'Retour',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Signaler',
                      color: AppColors.surge,
                      height: 44,
                      onTap: () {
                        final note = noteController.text.trim();
                        if (note.isEmpty) return;
                        Navigator.of(context).pop();
                        _confirmPayment('DISPUTED', note: note);
                      },
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
          if (kDebugMode)
            debugPrint(
              '[PAYMENT] Erreur confirmPayment tentative $attempt: $e',
            );
        }
      }
      if (!confirmed) {
        if (mounted) {
          showDemToast(
            context,
            'Erreur : paiement non enregistré. Contactez le support.',
            isError: true,
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
        showDemToast(
          context,
          'Problème signalé. L\'admin va prendre en charge.',
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
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
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
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
                          star <= selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: star <= selectedRating
                              ? AppColors.ratingGold
                              : Colors.white38,
                          size: 36,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Retour à l\'accueil',
                  color: AppColors.success,
                  onTap: () async {
                    // Capturer avant le gap asynchrone
                    final nav = Navigator.of(context);
                    final router = GoRouter.of(context);
                    final homeRoute = _homeRoute;
                    final orderId = _order['id'] as String?;
                    // Le driver note le client — ratedId = ID du client
                    final ratedUserId =
                        (_order['client'] as Map<String, dynamic>?)?['id']
                            as String?;

                    if (orderId != null &&
                        ratedUserId != null &&
                        selectedRating > 0) {
                      try {
                        await ref
                            .read(ordersRepositoryProvider)
                            .rateDriver(
                              orderId: orderId,
                              driverId:
                                  ratedUserId, // ratedId envoyé au backend = client
                              score: selectedRating,
                            );
                      } catch (_) {}
                    }
                    if (!mounted) return;
                    nav.pop();
                    router.go(homeRoute);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isRide => _order['orderType'] == 'RIDE';
  bool get _isExpress => _order['priority'] == 'EXPRESS';

  /// Numéro du client — compatible format plat (dev) et imbriqué (API réelle)
  /// Dev order : _order['clientPhone'] = '+221...'
  /// API réelle : _order['client'] = { 'phone': '+221...' }
  String? get _clientPhone =>
      (_order['clientPhone'] as String?) ??
      ((_order['client'] as Map<String, dynamic>?)?['phone'] as String?);

  String? get _senderPhone => _order['senderPhone'] as String?;
  String? get _receiverPhone => _order['receiverPhone'] as String?;

  // Avant récupération : appeler l'EXPÉDITEUR saisi sur la commande (peut
  // différer du numéro du compte client) — pas le compte, sinon un client
  // qui commande pour quelqu'un d'autre ferait appeler le mauvais numéro.
  // Repli sur _clientPhone seulement si senderPhone n'a pas été renseigné
  // (ex: RIDE, où sender/receiver n'existent pas — voir orders.service.js).
  String? get _activePhone => _isPickedUp
      ? (_receiverPhone ?? _clientPhone)
      : (_senderPhone ?? _clientPhone);

  Future<void> _callActiveContact() async {
    final phone = _activePhone;
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
          title: 'Livraison',
          snippet: _order['deliveryAddress'],
        ),
      ),
    };

    // Marqueur driver (point bleu plat, tourne avec le cap)
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

    return markers;
  }

  // ── Carte : polylines ─────────────────────────────────────────────────────
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isNight = ref.watch(mapNightProvider);
    return Scaffold(
      body: Stack(
        children: [
          // ── Carte ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: _driverPosition != null
                  ? CameraPosition(
                      target: LatLng(
                        _driverPosition!.latitude,
                        _driverPosition!.longitude,
                      ),
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
                  ? AlertBanner(
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
                      onTap: () async {
                        final router = GoRouter.of(context);
                        final homeRoute = _homeRoute;
                        if (!_isDelivered) {
                          final confirmed = await showGradientConfirmDialog(
                            context,
                            title: 'Quitter la navigation ?',
                            message:
                                'La course est toujours en cours.\nVous pourrez y revenir depuis l\'accueil.',
                            cancelLabel: 'Rester',
                            confirmLabel: 'Quitter',
                          );
                          if (confirmed != true || !mounted) return;
                        }
                        router.go(homeRoute);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isNight ? AppColors.primary : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: isNight ? Colors.white : AppColors.primary,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Bouton paiement QR (expéditeur à la récupération, destinataire à
          // la livraison) — toujours visible, y compris pendant une alerte de
          // proximité (zones d'écran distinctes, aucun chevauchement réel) et
          // après livraison (le paiement peut être demandé au moment même de
          // la remise du colis). Le backend refuse déjà toute nouvelle
          // tentative sur une commande déjà payée (409), donc laisser le
          // bouton actif ne peut pas provoquer de double paiement.
          Positioned(
            right: 16,
            bottom: 350,
            child: GestureDetector(
              onTap: _openPaymentQr,
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
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
            ),
          ),

          // ── Bouton guidage vocal ──
          if (!_isDelivered)
            Positioned(
              right: 16,
              bottom: 290,
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
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
            ),

          // ── Feuille infos bas ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).viewPadding.bottom + 24,
              ),
              decoration: BoxDecoration(
                gradient: AppColors.gradientDialog,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                  ),
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
                            // Rappel Express visible sur toute la course —
                            // avant, rien ne le signalait après acceptation,
                            // le livreur oubliait qu'il transportait une
                            // course prioritaire.
                            if (_isExpress) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.warning.withValues(
                                      alpha: 0.40,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.bolt_rounded,
                                      size: 12,
                                      color: AppColors.warning,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'EXPRESS',
                                      style: TextStyle(
                                        color: AppColors.warning,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
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
                                  _distanceToTarget!,
                                ),
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
                            horizontal: 12,
                            vertical: 8,
                          ),
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
                  AddressRow(
                    icon: Icons.circle,
                    iconColor: AppColors.success,
                    label: _isRide ? 'Prise en charge' : 'Collecte',
                    address: _order['pickupAddress'] ?? '',
                    dark: true,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 9),
                    child: SizedBox(
                      height: 12,
                      child: VerticalDivider(
                        color: Colors.white38,
                        thickness: 1.5,
                      ),
                    ),
                  ),
                  // Pour Thiak Thiak : destination masquée avant prise en charge
                  if (_isRide && !_isPickedUp)
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: Colors.white.withValues(alpha: 0.40),
                          size: 16,
                        ),
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
                    AddressRow(
                      icon: Icons.location_on,
                      iconColor: AppColors.error,
                      label: _isRide ? 'Destination' : 'Livraison',
                      address: _order['deliveryAddress'] ?? '',
                      dark: true,
                    ),

                  // Commande DEM Pro : le livreur doit savoir qui règle —
                  // sinon il pourrait redemander du cash sur une commande déjà
                  // prise en charge par l'entreprise, ou l'inverse. Absent
                  // (null) pour les commandes hors DEM Pro — pas de badge.
                  if (_order['paymentMode'] == 'merchant' ||
                      _order['paymentMode'] == 'cod') ...[
                    const SizedBox(height: 10),
                    _PaymentModeBadge(
                      mode: _order['paymentMode'] as String,
                      paid: _order['paymentStatus'] == 'PAID',
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Prix + bouton signaler — icône bolt ambre en Express,
                  // rappel discret que le bonus (+30%) est déjà inclus.
                  Row(
                    children: [
                      Icon(
                        _isExpress
                            ? Icons.bolt_rounded
                            : Icons.payments_outlined,
                        size: 16,
                        color: _isExpress ? AppColors.warning : Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${((_order['price'] as num?)?.toInt() ?? 0)} FCFA',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (_isExpress) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(bonus Express inclus)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.warning.withValues(alpha: 0.90),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (!_isDelivered)
                        GestureDetector(
                          onTap: () => SupportReportSheet.show(
                            context,
                            orderId: _order['id'] as String? ?? '',
                            role: 'DRIVER',
                            repo: ref.read(ordersRepositoryProvider),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flag_outlined,
                                  size: 13,
                                  color: Colors.white.withValues(alpha: 0.70),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Signaler',
                                  style: ClientText.label.copyWith(
                                    color: Colors.white.withValues(alpha: 0.80),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Bouton annuler livreur (1 min 30)
                  if (!_isPickedUp && !_isDelivered && _cancelSecondsLeft > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _driverCancelling ? null : _driverCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: AppColors.error.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          child: _driverCancelling
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.error,
                                  ),
                                )
                              : Text(
                                  'Annuler la course (${_cancelSecondsLeft}s)',
                                  style: ClientText.label,
                                ),
                        ),
                      ),
                    ),

                  // Preuve de livraison — optionnelle, proposée uniquement
                  // juste avant le dernier swipe (colis en main, sur le
                  // point d'être livré). Aucune preuve n'existait jusqu'ici
                  // en cas de litige (ni photo, ni signature, ni code).
                  if (_isPickedUp && !_isDelivered) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickProofPhoto,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
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
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 8),

                  // Bouton action principal + cercle appel — transition
                  // fondu/zoom vers le bandeau succès plutôt qu'un cut brutal.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: _isDelivered
                        ? Container(
                            key: const ValueKey('delivered'),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                _isRide
                                    ? 'Course effectuée avec succès !'
                                    : 'Commande livrée avec succès !',
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        : Row(
                            key: const ValueKey('swipe'),
                            children: [
                              Expanded(
                                child: SwipeToConfirm(
                                  key: ValueKey(
                                    'action-$_isPickedUp-$_swipeTick',
                                  ),
                                  label:
                                      'Glissez : ${_isPickedUp ? (_isRide ? 'course terminée' : 'livraison effectuée') : (_isRide ? 'passager à bord' : "colis récupéré")}',
                                  lockedLabel: _distanceToTarget != null
                                      ? 'Trop loin (${NavigationService.formatDistance(_distanceToTarget!)})'
                                      : 'Localisation requise',
                                  enabled: _canConfirmAction,
                                  lockProgress: _lockProgress,
                                  onLockedTap: () => showDemToast(
                                    context,
                                    'Rapprochez-vous à moins de ${_confirmRadiusMeters.round()} m du point pour confirmer.',
                                    isError: true,
                                  ),
                                  onConfirmed: _isPickedUp ? _deliver : _pickup,
                                  loading: _actionLoading,
                                  trackColor: _isPickedUp
                                      ? AppColors.primary
                                      : AppColors.surge,
                                  thumbColor: Colors.white,
                                  iconColor: _isPickedUp
                                      ? AppColors.primary
                                      : AppColors.surge,
                                  labelColor: Colors.white,
                                ),
                              ),

                              // Cercle appel — visible jusqu'à livraison
                              if (_activePhone != null) ...[
                                const SizedBox(width: 10),
                                CallButton(onTap: _callActiveContact),
                              ],
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

// ── Widgets privés ────────────────────────────────────────────────────────────

class _PaymentModeBadge extends StatelessWidget {
  final String mode; // 'merchant' | 'cod'
  final bool paid;
  const _PaymentModeBadge({required this.mode, required this.paid});

  @override
  Widget build(BuildContext context) {
    final isMerchant = mode == 'merchant';
    final color = isMerchant ? AppColors.success : AppColors.surge;
    final label = isMerchant
        ? (paid
              ? 'Payé par l\'entreprise — ne rien demander au destinataire'
              : 'Pris en charge par l\'entreprise — ne rien demander au destinataire')
        : 'Paiement à collecter auprès du destinataire';
    final icon = isMerchant
        ? Icons.check_circle_outline
        : Icons.payments_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  final bool isPickedUp;
  final bool isDelivered;
  final bool isRide;

  const _PhaseChip({
    required this.isPickedUp,
    required this.isDelivered,
    required this.isRide,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = isDelivered
        ? (
            isRide ? 'Course effectuée ✓' : 'Livraison effectuée ✓',
            AppColors.success,
          )
        : isPickedUp
        ? (
            isRide
                ? 'En route vers la destination'
                : 'En route vers la livraison',
            Colors.white,
          )
        : (
            isRide
                ? 'En route vers le passager'
                : 'En route pour récupérer le colis',
            AppColors.surge,
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: ClientText.label.copyWith(color: color)),
    );
  }
}
