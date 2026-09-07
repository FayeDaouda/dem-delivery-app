import 'dart:async';
import '../../../core/notifications/notification_service.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/services/location_queue_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/theme/map_theme_provider.dart';
import '../../shared/widgets/address_row.dart';
import '../../shared/widgets/gradient_sheet.dart';
import '../../shared/widgets/map_theme_toggle_button.dart';
import '../../shared/widgets/payment_collection_dialog.dart';
import '../../shared/widgets/swipe_to_confirm.dart';
import '../../features/deliveries/providers/orders_provider.dart';
import '../../features/notifications/data/notifications_repository.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../../features/profile/screens/document_upload_screen.dart';
import '../../features/profile/screens/driver_wallet_screen.dart';
import 'navigation/directions_service.dart';
import 'navigation/driver_marker_icon.dart';
import 'navigation/map_theme.dart';
import 'navigation/navigation_service.dart';
import '../../core/map/poi_data.dart';
import '../../core/map/poi_service.dart';
import '../../core/router/app_router.dart';

const _dakar = LatLng(14.6937, -17.4441);

class HomeDriverScreen extends ConsumerStatefulWidget {
  const HomeDriverScreen({super.key});

  @override
  ConsumerState<HomeDriverScreen> createState() => _HomeDriverScreenState();
}

class _HomeDriverScreenState extends ConsumerState<HomeDriverScreen>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _driverIcon;
  double _currentZoom = 15.5;
  PoiIconSet? _poiIconSet;
  List<PoiPoint>? _pois;

  // ── Heatmap de la demande (visible pendant les temps morts) ───────────────
  Set<Circle> _heatmapCircles = {};

  // ── Pulse animation ───────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;
  ScreenCoordinate? _driverScreenPos;

  // ── GPS ──────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _driverPosition;
  bool _autoFollow = true;

  // ── WebSocket ─────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _newOrderSub;
  StreamSubscription<String>? _expiredOrderSub;
  StreamSubscription<void>? _reconnectSub;
  StreamSubscription<Map<String, dynamic>>? _newBatchSub;
  StreamSubscription<String>? _batchExpiredSub;
  StreamSubscription<Map<String, dynamic>>? _cancelledOrderSub;
  StreamSubscription<Map<String, dynamic>>? _adminAssignedSub;
  StreamSubscription<Map<String, dynamic>>? _paymentConfirmedSub;

  // ── Offre de tournée (batch) ──────────────────────────────────────────────
  Map<String, dynamic>? _currentBatch;
  int _batchCountdown = 25;
  Timer? _batchCountdownTimer;
  bool _batchActionLoading = false;
  // Incrémenté à chaque nouvelle offre et à chaque échec d'acceptation — force
  // la réinitialisation visuelle du curseur "glisser pour accepter".
  int _batchSwipeTick = 0;

  // ── Offre de course simple : évite le double-tap Accepter/Refuser ────────
  bool _orderActionLoading = false;
  int _orderSwipeTick = 0;

  // ── Polling fallback (si socket déconnecté) ───────────────────────────────
  Timer? _pollTimer;

  // ── Heartbeat lastSeenAt ──────────────────────────────────────────────────
  Timer? _heartbeatTimer;

  // ── Route vers pickup (pendant notification) ──────────────────────────────
  List<LatLng> _pendingRoutePoints = [];
  LatLng? _pendingPickup;
  int? _pendingEtaSeconds;
  double? _pendingDistanceMeters;

  // ── Throttle émission position ────────────────────────────────────────────
  DateTime? _lastLocationEmit;
  late final _locationQueue = LocationQueueService(
    ref.read(ordersRepositoryProvider),
  );

  // ── Countdown nouvelle course ─────────────────────────────────────────────
  int _countdown = 60;
  Timer? _countdownTimer;

  // ── Stats du jour (pills accueil) ─────────────────────────────────────────
  int _todayCourses = 0;
  int _todayGains = 0;
  Map<String, dynamic>? _activeOrder;
  Map<String, dynamic>? _activeBatch;
  // Course livrée mais jamais encaissée (driver parti sans conclure le
  // paiement) — signalée par une bannière pour qu'il puisse la régulariser.
  Map<String, dynamic>? _unpaidOrder;

  // ── Passe journalière — bannière informative (le blocage réel est côté serveur) ──
  final _profileRepo = ProfileRepository();
  Map<String, dynamic>? _forfaitStatus;

  // ── Centre de notifications — aucun point d'accès n'existait côté livreur
  // (contrairement au client), alors que le backend persiste déjà tout
  // (rejet de document, statut KYC, etc.) via l'utilitaire notify().
  int _unreadNotifCount = 0;
  final _notifRepo = NotificationsRepository();

  Future<void> _loadUnreadNotifCount() async {
    try {
      final count = await _notifRepo.getUnreadCount();
      if (mounted) setState(() => _unreadNotifCount = count);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulseScale = Tween<double>(begin: 0.4, end: 2.2).animate(_pulseCtrl);
    _pulseOpacity = Tween<double>(begin: 0.7, end: 0.0).animate(_pulseCtrl);

    _loadMapStyle();
    buildDriverMarkerIcon().then((icon) {
      if (mounted) setState(() => _driverIcon = icon);
    });
    PoiService.loadPois().then((pois) {
      buildPoiIconSet(pois).then((set) {
        if (mounted)
          setState(() {
            _pois = pois;
            _poiIconSet = set;
          });
      });
    });
    _startGPS();
    _loadTodayStats();
    _loadForfaitStatus();
    _loadHeatmap();
    _loadUnreadNotifCount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(profileProvider.notifier)
          .fetchProfile(goOnlineIfOffline: true)
          .then((_) {
            // Sans ça, une course déjà en attente au moment de la connexion
            // (dispatchée avant que ce livreur ne soit disponible) ne
            // remonte que via un futur push socket ou l'expiration de
            // l'offre en cours (jusqu'à 60s) — le livreur devait auparavant
            // repasser hors ligne/en ligne pour forcer ce refresh REST.
            if (!mounted) return;
            if (ref.read(profileProvider).isAvailable) {
              ref.read(availableOrdersProvider.notifier).refresh();
            }
          });
      _connectSocket();
      _startPolling();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // Rechargement auto des stats et des commandes disponibles au retour de la livraison
    _loadTodayStats();
    _loadHeatmap();
    _loadUnreadNotifCount();
    _refreshAfterReturn();
  }

  Future<void> _refreshAfterReturn() async {
    final hadValidPass = _forfaitStatus?['todayCharged'] == true;
    await _loadForfaitStatus();
    final hasValidPassNow = _forfaitStatus?['todayCharged'] == true;
    // La passe vient d'être activée (typiquement depuis l'écran Portefeuille)
    // — le livreur ne doit pas avoir à re-glisser manuellement pour se
    // remettre en ligne. On ne retente PAS ça à chaque retour sur l'accueil
    // (sinon ça écraserait un passage hors ligne volontaire du livreur qui
    // avait déjà une passe valide) — seulement sur la transition invalide→valide.
    final justActivated = !hadValidPass && hasValidPassNow;
    // Solde affiché sur la pastille "Wallet" — sinon reste figé sur sa
    // valeur de connexion après une recharge/retrait/livraison payée.
    await ref
        .read(profileProvider.notifier)
        .fetchProfile(goOnlineIfOffline: justActivated);
    final isAvailable = ref.read(profileProvider).isAvailable;
    if (isAvailable) {
      ref.read(availableOrdersProvider.notifier).refresh();
    }
  }

  Future<void> _loadForfaitStatus() async {
    final status = await _profileRepo.getForfaitStatus();
    if (mounted) setState(() => _forfaitStatus = status);
  }

  Future<void> _loadHeatmap() async {
    final points = await ref
        .read(ordersRepositoryProvider)
        .getHeatmap(type: 'DELIVERY');
    if (mounted) setState(() => _heatmapCircles = _buildHeatmapCircles(points));
  }

  // Cercles semi-transparents dont la taille/couleur varie selon l'intensité
  // (pas de vrai calque de chaleur natif dans google_maps_flutter).
  Set<Circle> _buildHeatmapCircles(List<Map<String, dynamic>> points) {
    if (points.isEmpty) return {};
    final maxCount = points
        .map((p) => (p['count'] as num?)?.toInt() ?? 0)
        .fold(0, (a, b) => a > b ? a : b);
    if (maxCount == 0) return {};

    return points.map((p) {
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      final count = (p['count'] as num?)?.toInt() ?? 0;
      final intensity = (count / maxCount).clamp(0.0, 1.0);
      final color = Color.lerp(
        AppColors.primary,
        const Color(0xFFFF5C3C),
        intensity,
      )!;
      return Circle(
        circleId: CircleId('heat-$lat-$lng'),
        center: LatLng(lat, lng),
        radius: 350 + intensity * 450,
        fillColor: color.withValues(alpha: 0.18 + intensity * 0.22),
        strokeWidth: 0,
      );
    }).toSet();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _pulseCtrl.dispose();
    _locationSub?.cancel();
    _mapController?.dispose();
    _countdownTimer?.cancel();
    NotificationService.stopOrderAlert();
    _newOrderSub?.cancel();
    _expiredOrderSub?.cancel();
    _cancelledOrderSub?.cancel();
    _adminAssignedSub?.cancel();
    _paymentConfirmedSub?.cancel();
    _reconnectSub?.cancel();
    _newBatchSub?.cancel();
    _batchExpiredSub?.cancel();
    _batchCountdownTimer?.cancel();
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  /// Reconnexion socket au retour au premier plan.
  /// Uber/Bolt font exactement ça : retour foreground → reconnexion immédiate.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!SocketService.instance.isConnected) {
      // Reconnexion complète : dispose l'ancienne socket + crée une nouvelle
      AuthStorage.getToken().then((token) {
        if (token == null || !mounted) return;
        SocketService.instance.connect(token);
      });
    }
    // Recharge les courses disponibles (l'état peut avoir changé pendant l'absence)
    final isAvailable = ref.read(profileProvider).isAvailable;
    if (isAvailable && mounted) {
      ref.read(availableOrdersProvider.notifier).refresh();
    }
  }

  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null || !mounted) return;

    SocketService.instance.connect(token);

    _newOrderSub = SocketService.instance.onNewOrder.listen((order) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).injectSocketOrder(order);
      _startCountdown();
    });

    _expiredOrderSub = SocketService.instance.onOrderExpired.listen((orderId) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).removeOrder(orderId);
      _cancelCountdown();
    });

    _cancelledOrderSub = SocketService.instance.onOrderCancelled.listen((data) {
      if (!mounted) return;
      final orderId = data['orderId'] as String?;
      if (orderId != null) {
        ref.read(availableOrdersProvider.notifier).removeOrder(orderId);
        _cancelCountdown();
      }
    });

    _adminAssignedSub = SocketService.instance.onOrderAdminAssigned.listen((_) {
      if (!mounted) return;
      // Course attribuée directement par l'admin (sans passer par une offre) —
      // recharge la course active immédiatement au lieu d'attendre un retour sur l'accueil.
      _loadTodayStats();
    });

    _reconnectSub = SocketService.instance.onReconnect.listen((_) {
      if (!mounted) return;
      ref.read(availableOrdersProvider.notifier).refresh();
    });

    // Notification globale : un paiement en ligne peut se confirmer après
    // que le livreur ait quitté l'écran de paiement (QR fermé avant que le
    // client ait fini de scanner, ou passé à une autre course entre-temps)
    // — sans ça, il n'a aucun moyen de savoir que ça a finalement abouti.
    _paymentConfirmedSub = SocketService.instance.onOrderPaymentConfirmed
        .listen((data) {
          if (!mounted) return;
          final amount = (data['amount'] as num?)?.toInt();
          final address = data['deliveryAddress'] as String?;
          final where = address != null && address.trim().isNotEmpty
              ? ' — $address'
              : '';
          showDemToast(
            context,
            'Paiement confirmé${amount != null ? ' : $amount FCFA' : ''}$where',
          );
          _loadTodayStats();
        });

    _newBatchSub = SocketService.instance.onNewBatch.listen((batch) {
      if (!mounted) return;
      setState(() {
        _currentBatch = batch;
        _batchCountdown = 25;
        _batchSwipeTick++;
      });
      _startBatchCountdown();
    });

    _batchExpiredSub = SocketService.instance.onBatchExpired.listen((batchId) {
      if (!mounted) return;
      if (_currentBatch?['id'] == batchId) {
        setState(() => _currentBatch = null);
        _cancelBatchCountdown();
      }
    });

    // Heartbeat toutes les 30s pour maintenir lastSeenAt à jour côté backend
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!SocketService.instance.isConnected) return;
      final pos = _driverPosition;
      SocketService.instance.ping(lat: pos?.latitude, lng: pos?.longitude);
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final isAvailable = ref.read(profileProvider).isAvailable;
      final hasOrder =
          (ref.read(availableOrdersProvider).value ?? []).isNotEmpty;
      if (isAvailable && !hasOrder && !SocketService.instance.isConnected) {
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdown = 60;
      _orderSwipeTick++;
    });
    NotificationService.startOrderAlert();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        NotificationService.stopOrderAlert();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        NotificationService.stopOrderAlert();
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    NotificationService.stopOrderAlert();
    if (mounted) setState(() => _countdown = 60);
  }

  // ── Stats du jour (pills accueil) ─────────────────────────────────────────
  Future<void> _loadTodayStats() async {
    try {
      final res = await ApiClient.dio.get('/orders/my');
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['orders'] != null ? raw['orders'] as List : []);
      final now = DateTime.now();
      int courses = 0, gains = 0;
      Map<String, dynamic>? active;
      Map<String, dynamic>? unpaid;
      for (final o in List<Map<String, dynamic>>.from(list)) {
        final status = (o['status'] as String? ?? '').toUpperCase();
        if (['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'].contains(status)) {
          active = o;
        }
        // paymentMode 'merchant' exclu — rien à encaisser auprès du
        // destinataire, c'est au commerçant DEM Pro de régler en ligne (voir
        // active_order_screen.dart:_showMerchantHandlesPaymentDialog). Sans
        // ce filtre, ces commandes remonteraient à tort comme "à encaisser".
        if (unpaid == null &&
            status == 'DELIVERED' &&
            (o['paymentStatus'] as String? ?? '').toUpperCase() == 'PENDING' &&
            o['paymentMode'] != 'merchant') {
          unpaid = o;
        }
        if (status != 'DELIVERED' && status != 'PAYMENT_CONFIRMED') continue;
        final dt = DateTime.tryParse(
          o['createdAt'] as String? ?? '',
        )?.toLocal();
        if (dt == null) continue;
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
          courses++;
          gains += (o['price'] as num?)?.toInt() ?? 0;
        }
      }

      // Détecte une tournée batch active via batchOrderId sur la commande active
      Map<String, dynamic>? activeBatch;
      if (active != null && active['batchOrderId'] != null) {
        activeBatch = await ref.read(ordersRepositoryProvider).getActiveBatch();
        active =
            null; // la tournée prend la priorité, on masque la commande individuelle
      }

      if (activeBatch != null) {
        final stopCount = (activeBatch['orders'] as List?)?.length ?? 0;
        NotificationService.showOngoingNotification(
          id: 9999,
          title: 'Tournée en cours',
          body: '$stopCount arrêts à livrer',
        );
      } else if (active != null) {
        final delivery = active['deliveryAddress'] as String? ?? 'client';
        NotificationService.showOngoingNotification(
          id: 9999,
          title: 'Course en cours',
          body: 'En route pour : $delivery',
        );
      } else {
        NotificationService.cancelNotification(9999);
      }

      if (mounted) {
        setState(() {
          _todayCourses = courses;
          _todayGains = gains;
          _activeOrder = active;
          _activeBatch = activeBatch;
          _unpaidOrder = unpaid;
        });
      }
    } catch (_) {}
  }

  // ── Map style ─────────────────────────────────────────────────────────────
  Future<void> _loadMapStyle() async {
    final bool isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleMapTheme() async {
    await ref.read(mapNightProvider.notifier).toggle();
    await _loadMapStyle();
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> _startGPS() async {
    // Étape 1 : affichage instantané depuis le cache app (toujours GPS, jamais antenne réseau)
    final cached = await NavigationService.getCachedPosition();
    if (cached != null && mounted) {
      setState(() => _driverPosition = cached);
      _centerOn(cached);
    }

    final fresh = await NavigationService.requestAndGetPosition();
    if (!mounted) return;
    if (fresh != null) {
      setState(() => _driverPosition = fresh);
      _centerOn(fresh);
      NavigationService.savePosition(fresh);
    } else {
      NavigationService.promptOpenSettingsIfPermanentlyDenied(context);
    }

    // Étape 3 : stream continu
    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  bool _firstPositionSent = false;

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _driverPosition = position);
    if (_autoFollow) _centerOn(position);
    _updateDriverScreenPos();
    _trySendFirstPosition(position);

    // Émission position au backend toutes les 10s pour le dispatch —
    // socket ping (temps réel) + file REST résiliente (survit aux coupures
    // réseau : la dernière position connue est retentée au tick suivant).
    final now = DateTime.now();
    if (_lastLocationEmit == null ||
        now.difference(_lastLocationEmit!).inSeconds >= 10) {
      _lastLocationEmit = now;
      SocketService.instance.ping(
        lat: position.latitude,
        lng: position.longitude,
      );
      _locationQueue.emit(position.latitude, position.longitude);
    }
  }

  void _trySendFirstPosition(Position position) {
    if (_firstPositionSent) return;
    _firstPositionSent = true;
    if (SocketService.instance.isConnected) {
      SocketService.instance.ping(
        lat: position.latitude,
        lng: position.longitude,
      );
    }
  }

  Future<void> _updateDriverScreenPos() async {
    if (_driverPosition == null || _mapController == null) return;
    final coord = await _mapController!.getScreenCoordinate(
      LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
    );
    if (mounted) setState(() => _driverScreenPos = coord);
  }

  void _centerOn(Position position) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 15.5, // vue rue détaillée style Waze
          bearing: 0, // nord fixe — pas de rotation sur l'écran d'accueil
          tilt: 0, // plat = labels quartiers + POI visibles
        ),
      ),
    );
  }

  void _recenter() {
    if (_driverPosition == null) return;
    setState(() => _autoFollow = true);
    _centerOn(_driverPosition!);
  }

  // ── Route vers pickup à la réception d'une offre ──────────────────────────
  Future<void> _loadPendingRoute(Map<String, dynamic> order) async {
    if (_driverPosition == null) return;
    final pickup = LatLng(
      (order['pickupLatitude'] as num).toDouble(),
      (order['pickupLongitude'] as num).toDouble(),
    );
    final origin = LatLng(
      _driverPosition!.latitude,
      _driverPosition!.longitude,
    );
    // Affiche le repère de récupération immédiatement — pas besoin d'attendre
    // la réponse de l'API Directions pour donner un premier repère visuel.
    setState(() => _pendingPickup = pickup);
    _fitBoundsDriverToPickup(origin, pickup);

    final result = await DirectionsService.getRoute(
      origin: origin,
      destination: pickup,
      apiKey: AppConfig.mapsApiKey,
    );
    if (!mounted) return;
    setState(() {
      _pendingRoutePoints = result.points;
      _pendingEtaSeconds = result.durationSeconds;
      _pendingDistanceMeters = result.distanceMeters;
    });
  }

  void _fitBoundsDriverToPickup(LatLng driver, LatLng pickup) {
    setState(() => _autoFollow = false);

    // Livreur déjà quasiment sur le point de récupération : un cadrage sur
    // les deux points produirait une boîte quasi nulle, donc un zoom extrême
    // sur un fragment de rue sans aucun repère visuel (voir capture — c'est
    // exactement ce qui arrivait). On centre plutôt à un niveau de zoom fixe
    // "quartier", qui garde toujours assez de contexte de rue autour.
    final latSpan = (driver.latitude - pickup.latitude).abs();
    final lngSpan = (driver.longitude - pickup.longitude).abs();
    if (latSpan < 0.0015 && lngSpan < 0.0015) {
      final mid = LatLng(
        (driver.latitude + pickup.latitude) / 2,
        (driver.longitude + pickup.longitude) / 2,
      );
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: mid, zoom: 16.5)),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        driver.latitude < pickup.latitude ? driver.latitude : pickup.latitude,
        driver.longitude < pickup.longitude
            ? driver.longitude
            : pickup.longitude,
      ),
      northeast: LatLng(
        driver.latitude > pickup.latitude ? driver.latitude : pickup.latitude,
        driver.longitude > pickup.longitude
            ? driver.longitude
            : pickup.longitude,
      ),
    );
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _clearPendingRoute() {
    if (!mounted) return;
    setState(() {
      _pendingRoutePoints = [];
      _pendingPickup = null;
      _pendingEtaSeconds = null;
      _pendingDistanceMeters = null;
    });
  }

  Set<Polyline> get _pendingPolylines {
    if (_pendingRoutePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('pending'),
        points: _pendingRoutePoints,
        color: AppColors.primary,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  // ── Marker driver triangle Waze ───────────────────────────────────────────
  Set<Marker> get _driverMarkers {
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
    if (_pendingPickup != null) {
      // Même couleur que le marqueur de récupération une fois la course
      // acceptée (active_order_screen.dart) — repère visuel cohérent tout au
      // long du parcours, de l'offre jusqu'à la récupération réelle.
      markers.add(
        Marker(
          markerId: const MarkerId('pending_pickup'),
          position: _pendingPickup!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          zIndexInt: 1,
        ),
      );
    }
    if (_poiIconSet != null && _pois != null) {
      markers.addAll(
        buildPoiMarkersForZoom(_poiIconSet!, _currentZoom, _pois!),
      );
    }
    return markers;
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> _toggleAvailability() async {
    try {
      await ref.read(profileProvider.notifier).toggleAvailability();
      final isAvailable = ref.read(profileProvider).isAvailable;
      if (isAvailable) ref.read(availableOrdersProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      // Passe journalière non payée (blocage désactivé par défaut — voir
      // forfait.service.js côté backend) : raccourci direct vers le wallet
      // plutôt qu'un simple toast, pour ne pas laisser le driver deviner quoi
      // faire.
      if (e is AppException && e.statusCode == 402) {
        _showForfaitRequiredSheet();
      } else {
        showDemToast(context, friendlyError(e), isError: true);
      }
    }
  }

  void _openUnpaidOrderDialog() {
    final order = _unpaidOrder;
    final orderId = order?['id'] as String?;
    if (order == null || orderId == null) return;
    showPaymentCollectionDialog(
      context,
      ref,
      orderId: orderId,
      price: clientChargeFor(order),
      isSplitInApp: order['proPaymentMode'] == 'SPLIT_IN_APP',
      onPaid: () {
        if (mounted) setState(() => _unpaidOrder = null);
      },
    );
  }

  Future<void> _showForfaitRequiredSheet() {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          gradient: AppColors.gradientDialog,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(sheetContext).viewPadding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.confirmation_number_outlined,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Passe journalière requise',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Activez votre passe du jour depuis votre portefeuille pour pouvoir passer en ligne et recevoir des courses.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverWalletScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Payer ma passe maintenant',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(
                'Plus tard',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.60)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _declineOrder(String orderId) async {
    if (_orderActionLoading) return;
    setState(() => _orderActionLoading = true);
    // Mode DEV — pas d'appel API, on vide juste la liste locale
    if (orderId.startsWith('dev-')) {
      ref.read(availableOrdersProvider.notifier).removeOrder(orderId);
      if (mounted) setState(() => _orderActionLoading = false);
      return;
    }
    // Appel API — informe le backend que ce driver refuse.
    // Le backend ajoute le driver dans rejectedDriverIds et dispatche au suivant.
    try {
      await ref.read(ordersRepositoryProvider).declineOrder(orderId);
    } catch (_) {
      // Même en cas d'erreur réseau, on retire la modale localement.
      // Le backend déclenchera un re-dispatch après expiration des 30s.
    }
    ref.read(availableOrdersProvider.notifier).removeOrder(orderId);
    if (mounted) setState(() => _orderActionLoading = false);
  }

  Future<void> _acceptOrder(String orderId) async {
    if (_orderActionLoading) return;
    // GPS obligatoire — sans position le tracking client sera vide
    if (_driverPosition == null && !orderId.startsWith('dev-')) {
      if (mounted) {
        setState(() => _orderSwipeTick++);
        showDemToast(
          context,
          'GPS indisponible — activez la localisation pour accepter une course.',
          isError: true,
        );
      }
      return;
    }
    setState(() => _orderActionLoading = true);

    // Mode DEV — commande simulée, pas d'appel API
    if (orderId.startsWith('dev-')) {
      final devOrder =
          ref
              .read(availableOrdersProvider)
              .value
              ?.firstWhere((o) => o['id'] == orderId, orElse: () => {}) ??
          {};
      if (mounted) {
        setState(() => _orderActionLoading = false);
        context.push('/driver/order/active', extra: devOrder);
      }
      return;
    }
    try {
      // Sauvegarde la notification originale (contient client.phone depuis le backend)
      // avant qu'elle soit effacée par le provider après acceptation
      final notifOrder = (ref.read(availableOrdersProvider).value ?? [])
          .firstWhere((o) => o['id'] == orderId, orElse: () => {});
      final acceptedOrder = await ref
          .read(ordersRepositoryProvider)
          .acceptOrder(orderId);
      // Fusionne : notifOrder (infos client) + acceptedOrder (statut ACCEPTED)
      // acceptedOrder écrase les champs en double (status, etc.)
      final merged = {...notifOrder, ...acceptedOrder};
      // Vide le provider avant de naviguer → évite la réapparition au retour home
      ref.read(availableOrdersProvider.notifier).clear();

      if (mounted) {
        final pickup = merged['pickupAddress'] ?? '';

        // Affiche une vraie notification système
        NotificationService.showSystemNotification(
          title: 'Course acceptée !',
          body: 'Dirigez-vous vers : $pickup',
        );

        context.push('/driver/order/active', extra: merged);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _orderSwipeTick++);
        showDemToast(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _orderActionLoading = false);
    }
  }

  void _startBatchCountdown() {
    _batchCountdownTimer?.cancel();
    _batchCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _batchCountdown--);
      if (_batchCountdown <= 0) {
        t.cancel();
        setState(() => _currentBatch = null);
      }
    });
  }

  void _cancelBatchCountdown() {
    _batchCountdownTimer?.cancel();
    if (mounted) setState(() => _batchCountdown = 25);
  }

  Future<void> _declineBatch(String batchId) async {
    if (_batchActionLoading) return;
    _cancelBatchCountdown();
    setState(() => _batchActionLoading = true);
    try {
      await ref.read(ordersRepositoryProvider).declineBatch(batchId);
    } catch (_) {}
    if (mounted)
      setState(() {
        _currentBatch = null;
        _batchActionLoading = false;
      });
  }

  Future<void> _acceptBatch(String batchId) async {
    if (_batchActionLoading) return;
    _cancelBatchCountdown();
    final notifBatch = _currentBatch;
    setState(() => _batchActionLoading = true);
    try {
      final acceptedBatch = await ref
          .read(ordersRepositoryProvider)
          .acceptBatch(batchId);
      final merged = {...?notifBatch, ...acceptedBatch};
      if (mounted) {
        setState(() {
          _currentBatch = null;
          _batchActionLoading = false;
        });
        context.push('/driver/batch/active', extra: merged);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _batchActionLoading = false;
          _batchSwipeTick++;
        });
        showDemToast(context, friendlyError(e), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final isAvailable = profile.isAvailable;
    final ordersAsync = ref.watch(availableOrdersProvider);
    // En cas d'erreur API, on traite comme liste vide (pas d'affichage d'erreur)
    final orders = ordersAsync.value ?? [];
    // Heatmap visible seulement pendant les temps morts — en ligne, sans
    // course/tournée active ni notification en cours.
    final showHeatmap = isAvailable && _currentBatch == null && orders.isEmpty;

    // Mise en ligne auto → charge les commandes
    ref.listen<ProfileState>(profileProvider, (prev, next) {
      if (!(prev?.isAvailable ?? false) && next.isAvailable) {
        ref.read(availableOrdersProvider.notifier).refresh();
      }
      // Un échec de fetchProfile()/toggleAvailability() ne laissait jusqu'ici
      // aucune trace visible — l'écran restait figé sur son dernier état
      // connu sans que le livreur sache qu'une requête a échoué.
      if (next.error != null && next.error != prev?.error) {
        showDemToast(context, next.error!, isError: true);
      }
    });

    // Détecte l'arrivée d'une nouvelle course → route + fit bounds + countdown
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
      availableOrdersProvider,
      (prev, next) {
        final prevList = prev?.value ?? [];
        final nextList = next.value ?? [];
        if (nextList.isNotEmpty && prevList.isEmpty && isAvailable) {
          _startCountdown();
          _loadPendingRoute(nextList.first);
        } else if (nextList.isEmpty) {
          _cancelCountdown();
          _clearPendingRoute();
        }
      },
    );

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte plein écran style Waze sombre ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _dakar,
                zoom: 14,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_driverPosition != null) _centerOn(_driverPosition!);
              },
              style: _mapStyle,
              onCameraMove: (pos) {
                if (_autoFollow) setState(() => _autoFollow = false);
                if ((pos.zoom - _currentZoom).abs() > 0.5) {
                  setState(() => _currentZoom = pos.zoom);
                }
              },
              onCameraIdle: _updateDriverScreenPos,
              markers: _driverMarkers,
              polylines: _pendingPolylines,
              circles: showHeatmap ? _heatmapCircles : const {},
              trafficEnabled: false,
              buildingsEnabled: true,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Pulse animation sur le marqueur driver ──
          if (_driverScreenPos != null)
            Positioned(
              left: _driverScreenPos!.x.toDouble() - 30,
              top: _driverScreenPos!.y.toDouble() - 30,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, _) => Transform.scale(
                    scale: _pulseScale.value,
                    child: Opacity(
                      opacity: _pulseOpacity.value,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF33BCD4),
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Toggle disponibilité + profil (header) ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Toggle
                  _AvailabilityPill(
                    isAvailable: isAvailable,
                    isLoading: profile.isLoading,
                    onTap: _toggleAvailability,
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await context.push('/driver/notifications');
                      _loadUnreadNotifCount();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Center(
                            child: Icon(
                              Icons.notifications_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          if (_unreadNotifCount > 0)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  _unreadNotifCount > 9
                                      ? '9+'
                                      : '$_unreadNotifCount',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/driver/profile'),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.45),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Boutons flottants + sheet empilés en bas (comme côté client) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Flottants juste au-dessus du sheet ──
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // GAUCHE : Jour/Nuit — widget partagé avec l'écran client
                      MapThemeToggleButton(onTap: _toggleMapTheme),

                      // DROITE : Badge course active + Recenter
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_activeBatch != null) ...[
                            GestureDetector(
                              onTap: () => context.push(
                                '/driver/batch/active',
                                extra: _activeBatch,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentIndigo,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.accentIndigo.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.route,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Tournée · ${(_activeBatch!['orders'] as List?)?.length ?? 0} arrêts',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_activeOrder != null) ...[
                            GestureDetector(
                              onTap: () => context.push(
                                '/driver/order/active',
                                extra: _activeOrder,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentMint,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.accentMint.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.delivery_dining,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Course en cours',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (!_autoFollow)
                            Semantics(
                              label: 'Recentrer sur ma position',
                              button: true,
                              child: GestureDetector(
                                onTap: _recenter,
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.card,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 12,
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
                            )
                          else
                            const SizedBox(width: 52),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Bottom sheet — 3 états (toujours visible) ──
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(anim);
                    return SlideTransition(
                      position: slide,
                      child: FadeTransition(opacity: anim, child: child),
                    );
                  },
                  child: _currentBatch != null
                      // ── État 4 : nouvelle tournée batch ──
                      ? _BatchNotificationSheet(
                          key: const ValueKey('batch'),
                          batch: _currentBatch!,
                          countdown: _batchCountdown,
                          loading: _batchActionLoading,
                          swipeResetTick: _batchSwipeTick,
                          onAccept: () =>
                              _acceptBatch(_currentBatch!['id'] as String),
                          onDecline: () =>
                              _declineBatch(_currentBatch!['id'] as String),
                        )
                      : isAvailable && orders.isNotEmpty
                      // ── État 3 : nouvelle course ──
                      ? _OrderNotificationSheet(
                          key: const ValueKey('order'),
                          order: orders.first,
                          countdown: _countdown,
                          etaSeconds: _pendingEtaSeconds,
                          distanceMeters: _pendingDistanceMeters,
                          loading: _orderActionLoading,
                          swipeResetTick: _orderSwipeTick,
                          onAccept: () {
                            _cancelCountdown();
                            _clearPendingRoute();
                            _acceptOrder(orders.first['id']);
                          },
                          onDecline: () {
                            _cancelCountdown();
                            _clearPendingRoute();
                            _declineOrder(orders.first['id']);
                          },
                        )
                      // ── État 1 : accueil normal ──
                      : _NormalSheet(
                          key: const ValueKey('normal'),
                          profile: profile,
                          isAvailable: isAvailable,
                          ordersLoading: ordersAsync.isLoading,
                          hasActiveOrder:
                              _activeOrder != null || _activeBatch != null,
                          todayCourses: _todayCourses,
                          todayGains: _todayGains,
                          walletBalance:
                              (profile.user?['balance'] as num?)?.round() ?? 0,
                          forfaitStatus: _forfaitStatus,
                          unpaidOrder: _unpaidOrder,
                          onTapUnpaid: _openUnpaidOrderDialog,
                          onToggle: _toggleAvailability,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── État 1 : accueil normal ───────────────────────────────────────────────────
class _NormalSheet extends StatelessWidget {
  final dynamic profile;
  final bool isAvailable;
  final bool ordersLoading;
  final bool hasActiveOrder;
  final int todayCourses;
  final int todayGains;
  final int walletBalance;
  final Map<String, dynamic>? forfaitStatus;
  final Map<String, dynamic>? unpaidOrder;
  final VoidCallback? onTapUnpaid;
  final VoidCallback onToggle;

  const _NormalSheet({
    super.key,
    required this.profile,
    required this.isAvailable,
    required this.ordersLoading,
    required this.hasActiveOrder,
    required this.todayCourses,
    required this.todayGains,
    required this.walletBalance,
    this.forfaitStatus,
    this.unpaidOrder,
    this.onTapUnpaid,
    required this.onToggle,
  });

  // Bandeau lié à la passe — deux cas bien distincts :
  // - 'required' : le blocage dispatch est actif ET aucune passe valide en
  //   ce moment → réellement impossible de recevoir des courses sans agir.
  // - 'expiring' : une passe valide existe, mais expire dans moins de 3h
  //   (24h glissantes depuis son activation, PAS minuit — voir
  //   forfait.service.js) → rappel pour ne pas se faire couper brusquement
  //   en pleine course.
  // Si le blocage dispatch est désactivé (comportement actuel par défaut),
  // aucun bandeau n'a de sens : rien n'empêche réellement de recevoir des
  // courses, donc rien à signaler.
  // Compte à rebours de vérification documents (KYC) — le backend passe le
  // driver en 'PENDING_DOCUMENTS' avec un délai de 72h après 3 courses sans
  // dossier complet, puis suspend automatiquement le compte à l'échéance
  // (driver-verification.service.js). Ce délai était déjà renvoyé par
  // /users/me mais n'était affiché nulle part — le livreur ne découvrait la
  // suspension qu'après coup.
  DateTime? get _kycDeadline {
    if (profile.user?['driverStatus'] != 'PENDING_DOCUMENTS') return null;
    final raw = profile.user?['verificationDeadline'] as String?;
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  String? get _forfaitBannerKind {
    if (forfaitStatus?['dispatchGatingActive'] != true) return null;
    if (forfaitStatus?['todayCharged'] != true) return 'required';
    final expiresAtRaw = forfaitStatus?['passExpiresAt'] as String?;
    final expiresAt = expiresAtRaw != null
        ? DateTime.tryParse(expiresAtRaw)
        : null;
    if (expiresAt == null) return null;
    final hoursLeft = expiresAt.difference(DateTime.now()).inMinutes / 60;
    return hoursLeft <= 3 ? 'expiring' : null;
  }

  @override
  Widget build(BuildContext context) {
    const textPrimary = Colors.white;
    final textSecondary = Colors.white.withValues(alpha: 0.70);

    return GradientSheet(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).viewPadding.bottom + 24,
        ),
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isNotEmpty
                            ? 'Bonjour, ${profile.name} 👋'
                            : 'Bonjour 👋',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasActiveOrder
                            ? 'Course en cours'
                            : isAvailable
                            ? 'En attente de courses...'
                            : 'Activez pour recevoir des courses',
                        style: TextStyle(color: textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (ordersLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
            if (_kycDeadline != null) ...[
              const SizedBox(height: 14),
              _KycDeadlineBanner(deadline: _kycDeadline!),
            ],
            if (_forfaitBannerKind != null) ...[
              const SizedBox(height: 14),
              Builder(
                builder: (context) {
                  final expiring = _forfaitBannerKind == 'expiring';
                  final color = expiring ? AppColors.warning : AppColors.surge;
                  String message;
                  if (expiring) {
                    final expiresAt = DateTime.tryParse(
                      forfaitStatus?['passExpiresAt'] as String? ?? '',
                    );
                    final hoursLeft = expiresAt != null
                        ? (expiresAt.difference(DateTime.now()).inMinutes / 60)
                              .ceil()
                        : 0;
                    message =
                        'Votre passe expire dans ${hoursLeft}h — renouvelez-la pour ne pas être coupé';
                  } else {
                    message =
                        'Activez votre passe du jour pour recevoir des courses';
                  }
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverWalletScreen(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: color, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
            if (unpaidOrder != null) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onTapUnpaid,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.payments_outlined,
                        color: AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Une course livrée n\'a pas encore été encaissée '
                          '(${clientChargeFor(unpaidOrder!)} FCFA)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (isAvailable) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  _StatPill(
                    icon: Icons.route_outlined,
                    label:
                        '$todayCourses course${todayCourses != 1 ? 's' : ''}',
                    color: AppColors.primary,
                    onTap: () => _showStatModal(context, _StatType.courses),
                  ),
                  const SizedBox(width: 10),
                  _StatPill(
                    icon: Icons.monetization_on_outlined,
                    label: '$todayGains FCFA',
                    color: AppColors.primaryDark,
                    onTap: () => _showStatModal(context, _StatType.gains),
                  ),
                  const SizedBox(width: 10),
                  _StatPill(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '$walletBalance FCFA',
                    color: AppColors.accentMint,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverWalletScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Bandeau : délai de vérification documents (KYC) ────────────────────────
class _KycDeadlineBanner extends StatefulWidget {
  final DateTime deadline;
  const _KycDeadlineBanner({required this.deadline});

  @override
  State<_KycDeadlineBanner> createState() => _KycDeadlineBannerState();
}

class _KycDeadlineBannerState extends State<_KycDeadlineBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadline.difference(DateTime.now());
    final expired = remaining.isNegative;

    final Color color = expired
        ? AppColors.error
        : remaining.inHours < 12
        ? AppColors.error
        : remaining.inHours < 24
        ? AppColors.warning
        : AppColors.surge;

    final String timeLabel = expired
        ? 'Délai dépassé'
        : remaining.inHours > 0
        ? '${remaining.inHours}h restantes'
        : '${remaining.inMinutes} min restantes';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DocumentUploadScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Documents manquants — compte suspendu si non complété',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withValues(alpha: 0.6),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }
}

// ── État 3 : notification nouvelle course ─────────────────────────────────────
class _OrderNotificationSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final int countdown;
  final int? etaSeconds;
  final double? distanceMeters;
  final bool loading;
  final int swipeResetTick;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _OrderNotificationSheet({
    super.key,
    required this.order,
    required this.countdown,
    this.etaSeconds,
    this.distanceMeters,
    this.loading = false,
    required this.swipeResetTick,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final pickup = order['pickupAddress'] ?? '';
    final delivery = order['deliveryAddress'] ?? '';
    // Le prix EXPRESS inclut déjà le bonus livreur (+30%, voir
    // EXPRESS_DRIVER_EXTRA côté backend) mais rien ne le signalait — le
    // livreur voyait juste un chiffre plus élevé sans comprendre pourquoi.
    final isExpress = order['priority'] == 'EXPRESS';
    // Frais de mise en relation DEM (matrice zone, jamais cumulé avec
    // EXPRESS qui garde son propre modèle) — déjà déduits de `price`, sans
    // signalement le livreur voit juste un chiffre plus bas que le tarif
    // annoncé au client, sans comprendre pourquoi.
    final demFee = (order['demFee'] as num?)?.toInt() ?? 0;
    final hasCommission = !isExpress && demFee > 0;
    final accentColor = isExpress ? AppColors.warning : AppColors.primary;

    return GradientSheet(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).viewPadding.bottom + 24,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: accentColor, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),

            // Header : titre + countdown
            Row(
              children: [
                Icon(
                  isExpress ? Icons.bolt_rounded : Icons.inventory_2_outlined,
                  color: accentColor,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Text(
                  isExpress ? 'Livraison Express' : 'Nouvelle livraison',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: countdown / 60,
                        strokeWidth: 3,
                        backgroundColor: AppColors.card,
                        color: countdown > 24
                            ? AppColors.primary
                            : AppColors.surge,
                      ),
                      Text(
                        '$countdown',
                        style: TextStyle(
                          color: countdown > 24
                              ? AppColors.primary
                              : AppColors.surge,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (etaSeconds != null || distanceMeters != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (etaSeconds != null) ...[
                    const Icon(
                      Icons.access_time_outlined,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      NavigationService.formatDuration(etaSeconds!),
                      style: ClientText.body.copyWith(color: Colors.white),
                    ),
                  ],
                  if (etaSeconds != null && distanceMeters != null)
                    const SizedBox(width: 16),
                  if (distanceMeters != null) ...[
                    const Icon(
                      Icons.straighten_outlined,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      NavigationService.formatDistance(distanceMeters!),
                      style: ClientText.body.copyWith(color: Colors.white),
                    ),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Adresses sur carte blanche pour lisibilité
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  AddressRow(
                    icon: Icons.circle,
                    iconColor: Colors.black87,
                    label: 'Récupération',
                    address: pickup,
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
                    width: 1.5,
                    height: 12,
                    color: Colors.black12,
                  ),
                  AddressRow(
                    icon: Icons.location_on,
                    iconColor: Colors.black87,
                    label: 'Livraison',
                    address: delivery,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Prix — pour Express, le bonus livreur (+30%, déjà inclus dans
            // `price`) est signalé explicitement : sans ça le livreur ne
            // voit qu'un chiffre plus élevé, sans comprendre pourquoi ni
            // être motivé par le bonus.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '$price FCFA',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isExpress) ...[
                    const SizedBox(height: 2),
                    Text(
                      '⚡ dont bonus Express (+30%)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (hasCommission) ...[
                    const SizedBox(height: 2),
                    Text(
                      'dont $demFee FCFA de frais DEM (déjà déduits)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Boutons — refus en icône compacte (action secondaire), le
            // glissement d'acceptation occupe presque toute la largeur pour
            // ne jamais tronquer son libellé (voir SwipeToConfirm).
            Row(
              children: [
                GestureDetector(
                  onTap: loading ? null : onDecline,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: loading ? 0.3 : 0.55,
                      ),
                      border: Border.all(
                        color: AppColors.error.withValues(
                          alpha: loading ? 0.4 : 1,
                        ),
                        width: 1.5,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.error.withValues(
                        alpha: loading ? 0.4 : 1,
                      ),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwipeToConfirm(
                    key: ValueKey('accept-order-$swipeResetTick'),
                    label: 'Glissez pour accepter',
                    onConfirmed: onAccept,
                    loading: loading,
                    trackColor: AppColors.primary,
                    thumbColor: Colors.white,
                    iconColor: AppColors.primary,
                    labelColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── État 4 : notification nouvelle tournée batch ──────────────────────────────
class _BatchNotificationSheet extends StatelessWidget {
  final Map<String, dynamic> batch;
  final int countdown;
  final bool loading;
  final int swipeResetTick;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _BatchNotificationSheet({
    super.key,
    required this.batch,
    required this.countdown,
    this.loading = false,
    required this.swipeResetTick,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final orders =
        (batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // Le gain du livreur = somme du price de chaque arrêt (il touche 100% du
    // prix plein) — JAMAIS batch['totalPrice'], qui est le montant déjà
    // réduit (-20%) facturé au CLIENT (voir dispatch.service.js). driverTotal
    // est précalculé côté backend ; repli sur la somme des arrêts si absent
    // (compat avec un payload plus ancien).
    final total = (batch['driverTotal'] as num?)?.toInt() ??
        orders.fold<int>(0, (s, o) => s + ((o['price'] as num?)?.toInt() ?? 0));
    final pickup = batch['pickupAddress'] as String? ?? '';
    final stopCount = orders.length;

    return GradientSheet(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).viewPadding.bottom + 24,
        ),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.accentIndigo, width: 2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),

            // Header
            Row(
              children: [
                const Icon(
                  Icons.route_outlined,
                  color: AppColors.accentIndigo,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nouvelle tournée',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$stopCount arrêt${stopCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: countdown / 25,
                        strokeWidth: 3,
                        backgroundColor: AppColors.card,
                        color: countdown > 10
                            ? AppColors.accentIndigo
                            : AppColors.surge,
                      ),
                      Text(
                        '$countdown',
                        style: TextStyle(
                          color: countdown > 10
                              ? AppColors.accentIndigo
                              : AppColors.surge,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Stops list on white card
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  // Pickup row
                  AddressRow(
                    icon: Icons.circle,
                    iconColor: Colors.black87,
                    label: 'Récupération',
                    address: pickup,
                  ),
                  // Up to 3 stops
                  ...orders.take(3).toList().asMap().entries.map((e) {
                    final i = e.key;
                    final o = e.value;
                    return Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(
                            left: 10,
                            top: 4,
                            bottom: 4,
                          ),
                          width: 1.5,
                          height: 10,
                          color: Colors.black12,
                        ),
                        AddressRow(
                          icon: Icons.location_on,
                          iconColor: Colors.black87,
                          label: 'Arrêt ${i + 1}',
                          address: o['deliveryAddress'] as String? ?? '',
                        ),
                      ],
                    );
                  }),
                  if (stopCount > 3) ...[
                    const SizedBox(height: 6),
                    Text(
                      '+ ${stopCount - 3} autre${stopCount - 3 > 1 ? 's' : ''} arrêt${stopCount - 3 > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Total price
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accentIndigo.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$total FCFA',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Boutons — refus en icône compacte (action secondaire), le
            // glissement d'acceptation occupe presque toute la largeur pour
            // ne jamais tronquer son libellé (voir SwipeToConfirm).
            Row(
              children: [
                GestureDetector(
                  onTap: loading ? null : onDecline,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: loading ? 0.3 : 0.55,
                      ),
                      border: Border.all(
                        color: AppColors.error.withValues(
                          alpha: loading ? 0.4 : 1,
                        ),
                        width: 1.5,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.error.withValues(
                        alpha: loading ? 0.4 : 1,
                      ),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwipeToConfirm(
                    key: ValueKey('accept-batch-$swipeResetTick'),
                    label: 'Glissez pour accepter',
                    onConfirmed: onAccept,
                    loading: loading,
                    trackColor: AppColors.accentIndigo,
                    thumbColor: Colors.white,
                    iconColor: AppColors.accentIndigo,
                    labelColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: ClientText.caption.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Modal détail statistique ──────────────────────────────────────────────────
void _showStatModal(BuildContext context, _StatType type) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _StatDetailModal(type: type),
  );
}

enum _StatType { courses, rating, gains }

// ── Modal stats — données réelles depuis /orders/my ───────────────────────────
class _StatDetailModal extends StatefulWidget {
  final _StatType type;
  const _StatDetailModal({required this.type});

  @override
  State<_StatDetailModal> createState() => _StatDetailModalState();
}

class _StatDetailModalState extends State<_StatDetailModal> {
  late final Future<Map<String, int>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<Map<String, int>> _loadStats() async {
    final res = await ApiClient.dio.get('/orders/my');
    final raw = res.data;
    final List<dynamic> list = raw is List
        ? raw
        : (raw is Map && raw['orders'] != null ? raw['orders'] as List : []);
    final orders = List<Map<String, dynamic>>.from(list);

    final now = DateTime.now();
    final mon = DateTime(now.year, now.month, now.day - (now.weekday - 1));

    int cToday = 0, cWeek = 0, cTotal = 0, cCancelled = 0;
    int gToday = 0, gWeek = 0, gMonth = 0, gTotal = 0;

    for (final o in orders) {
      final status = (o['status'] as String? ?? '').toUpperCase();
      final price = (o['price'] as num?)?.toInt() ?? 0;
      final raw2 = o['createdAt'] as String?;
      final dt = raw2 != null ? DateTime.tryParse(raw2)?.toLocal() : null;

      if (status == 'CANCELLED') {
        cCancelled++;
        continue;
      }
      if (status != 'DELIVERED' && status != 'PAYMENT_CONFIRMED') continue;

      cTotal++;
      gTotal += price;
      if (dt != null) {
        final sameDay =
            dt.year == now.year && dt.month == now.month && dt.day == now.day;
        if (sameDay) {
          cToday++;
          gToday += price;
        }
        if (!dt.isBefore(mon)) {
          cWeek++;
          gWeek += price;
        }
        if (dt.year == now.year && dt.month == now.month) gMonth += price;
      }
    }

    final total = orders.length;
    final cancelRate = total == 0 ? 0 : ((cCancelled / total) * 100).round();

    return {
      'cToday': cToday,
      'cWeek': cWeek,
      'cTotal': cTotal,
      'cCancelled': cCancelled,
      'cancelRate': cancelRate,
      'gToday': gToday,
      'gWeek': gWeek,
      'gMonth': gMonth,
      'gTotal': gTotal,
    };
  }

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title) = switch (widget.type) {
      _StatType.courses => (Icons.route_outlined, 'Mes courses'),
      _StatType.rating => (Icons.star_outline_rounded, 'Ma note'),
      _StatType.gains => (Icons.monetization_on_outlined, 'Mes gains'),
    };

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryMid,
            AppColors.primaryDark,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewPadding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Note : pas de données réelles encore ──
          if (widget.type == _StatType.rating) ...[
            _StatRow(label: 'Note moyenne', value: '—', sub: 'sur 5 étoiles'),
            _StatRow(
              label: 'Avis reçus',
              value: '0',
              sub: 'clients satisfaits',
            ),
            _StatRow(label: 'Ponctualité', value: '—', sub: 'arrivée à temps'),
            _StatRow(
              label: 'Colis intact',
              value: '—',
              sub: 'taux de satisfaction',
            ),
          ] else
            FutureBuilder<Map<String, int>>(
              future: _statsFuture,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }
                if (snap.hasError || snap.data == null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Impossible de charger les données.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                  );
                }
                final s = snap.data!;
                if (widget.type == _StatType.courses) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatRow(
                        label: "Aujourd'hui",
                        value: '${s['cToday']}',
                        sub: 'courses effectuées',
                      ),
                      _StatRow(
                        label: 'Cette semaine',
                        value: '${s['cWeek']}',
                        sub: 'courses effectuées',
                      ),
                      _StatRow(
                        label: 'Total',
                        value: '${s['cTotal']}',
                        sub: 'depuis le début',
                      ),
                      _StatRow(
                        label: 'Annulées',
                        value: '${s['cCancelled']}',
                        sub: 'taux ${s['cancelRate']}%',
                      ),
                    ],
                  );
                } else {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatRow(
                        label: "Aujourd'hui",
                        value: '${s['gToday']} FCFA',
                        sub: 'revenus du jour',
                      ),
                      _StatRow(
                        label: 'Cette semaine',
                        value: '${s['gWeek']} FCFA',
                        sub: 'revenus 7 jours',
                      ),
                      _StatRow(
                        label: 'Ce mois',
                        value: '${s['gMonth']} FCFA',
                        sub: 'revenus 30 jours',
                      ),
                      _StatRow(
                        label: 'Total cumulé',
                        value: '${s['gTotal']} FCFA',
                        sub: 'depuis le début',
                      ),
                    ],
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _StatRow({required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: sub != null ? '$label : $value, $sub' : '$label : $value',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.80),
                fontSize: 14,
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: ClientText.subtitle.copyWith(color: Colors.white),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pill "En ligne / Hors ligne" du header — animation premium ──────────────
// Remplace l'ancien Switch.adaptive générique : gradient qui morphe, point
// qui pulse en radar quand en ligne, mini-switch custom avec rebond et
// retour haptique. Même esprit que le pulse du marqueur driver sur la carte.
class _AvailabilityPill extends StatefulWidget {
  final bool isAvailable;
  final bool isLoading;
  final VoidCallback onTap;

  const _AvailabilityPill({
    required this.isAvailable,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_AvailabilityPill> createState() => _AvailabilityPillState();
}

class _AvailabilityPillState extends State<_AvailabilityPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  bool _pressed = false;

  @override
  void dispose() {
    _radarCtrl.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.isAvailable;
    return GestureDetector(
      onTapDown: widget.isLoading ? null : (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.isLoading
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onTap();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          // Même hauteur que le bouton profil voisin (48px) — la pill
          // paraissait plus courte que les boutons ronds du header, pas
          // alignée avec eux. Largeur augmentée en cohérence (padding
          // horizontal plus généreux).
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: on
                  ? [AppColors.online, AppColors.primary]
                  : [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.black.withValues(alpha: 0.6),
                    ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (on ? AppColors.online : Colors.black).withValues(
                  alpha: on ? 0.45 : 0.35,
                ),
                blurRadius: on ? 16 : 8,
                spreadRadius: on ? 1 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Point radar — pulse en anneau tant que le livreur est en ligne.
              // La boîte fait 16×16 mais l'anneau grossit jusqu'à ~2.8× le
              // point (22px) — sans clipBehavior.none, le Stack le coupait
              // net à 16px (comportement par défaut hardEdge) et le pulse
              // était quasi invisible. La boîte de layout reste 16×16 (ne
              // pousse pas les voisins), seul le rendu déborde librement.
              SizedBox(
                width: 16,
                height: 16,
                child: AnimatedBuilder(
                  animation: _radarCtrl,
                  builder: (_, __) {
                    final t = _radarCtrl.value;
                    return Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (on)
                          Opacity(
                            opacity: (1 - t) * 0.6,
                            child: Transform.scale(
                              scale: 1 + t * 2.4,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: on ? Colors.white : AppColors.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    axis: Axis.horizontal,
                    // Sans ça, l'axe croisé (hauteur) reste sans contrainte
                    // et le widget s'étire pour remplir tout le Stack parent.
                    fixedCrossAxisSizeFactor: 1.0,
                    child: child,
                  ),
                ),
                child: Text(
                  on ? 'En ligne' : 'Hors ligne',
                  key: ValueKey(on),
                  style: ClientText.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.isLoading
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 28,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : _MiniSwitch(key: const ValueKey('switch'), value: on),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Mini-switch custom (remplace Switch.adaptive) — même teinte que la pill,
// thumb qui glisse avec un léger rebond (easeOutBack) plutôt qu'un slide plat.
class _MiniSwitch extends StatelessWidget {
  final bool value;

  const _MiniSwitch({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: 34,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: value ? 0.35 : 0.15),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
