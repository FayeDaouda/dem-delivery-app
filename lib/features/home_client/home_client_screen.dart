import 'dart:async';
import 'dart:math';
import '../../../core/notifications/notification_service.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/map/poi_data.dart';
import '../../core/map/poi_service.dart';
import '../../core/router/app_router.dart';
import '../../core/services/location_reveal_controller.dart';
import '../../core/services/map_location_mode_controller.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/theme/map_theme_provider.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/map_location_mode_button.dart';
import '../../shared/widgets/map_theme_toggle_button.dart';
import '../../shared/widgets/nudging_chevron.dart';
import '../../shared/widgets/pressable.dart';
import '../deliveries/data/orders_repository.dart';
import '../deliveries/providers/orders_provider.dart';
import '../../shared/widgets/promo_highlight_popup.dart';
import '../home_driver/navigation/map_theme.dart';
import '../home_driver/navigation/navigation_service.dart';
import '../../core/utils/location_gate.dart';

// Centre par défaut : Dakar
const _dakar = LatLng(14.6937, -17.4441);

// Hauteur de la navbar
const double _navBarHeight = 64;

class HomeClientScreen extends ConsumerStatefulWidget {
  const HomeClientScreen({super.key});

  @override
  ConsumerState<HomeClientScreen> createState() => _HomeClientScreenState();
}

class _HomeClientScreenState extends ConsumerState<HomeClientScreen>
    with TickerProviderStateMixin, RouteAware {
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _pendingOrders = [];
  List<Map<String, dynamic>> _activeOrders = [];
  bool _isInitialLoad =
      true; // redirection auto tracking seulement au premier chargement
  static const _kDeliveredKey = 'dem_shown_delivered_ids';

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  double _currentZoom = 15;
  BitmapDescriptor? _locationDotIcon;

  // ── POI ───────────────────────────────────────────────────────────────────
  PoiIconSet? _poiIconSet;
  List<PoiPoint>? _pois;

  // ── WebSocket ─────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _orderAcceptedSub;
  // _driverLocationSub supprimé : géré par ClientOrderNotifier (tracking provider)

  // ── GPS + boussole ────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _clientPosition;
  double _travelHeading = 0;
  late final _locationModeCtrl = MapLocationModeController(
    onUpdate: _onLocationModeUpdate,
  );
  bool _programmaticMove = false;
  Timer? _programmaticMoveTimer;

  // Halo sonar une seule fois à l'acquisition de la position — pas de chute
  // (contrairement au point de départ figé de la création de commande, la
  // position GPS live du client n'a pas de "fausse position de départ"
  // pertinente d'où tomber).
  late final _positionReveal = LocationRevealController(
    vsync: this,
    onUpdate: () => setState(() {}),
  );

  // ── Sheet rétractable ──────────────────────────────────────────────────────
  bool _sheetExpanded = true;
  late AnimationController _sheetAnim;
  late Animation<double> _sheetSlide;

  // ── Polling timer pour s'assurer que le badge est à jour ───────────────────
  Timer? _pollTimer;
  bool _checkingOrders = false;

  @override
  void initState() {
    super.initState();
    _sheetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1.0,
    );
    _sheetSlide = CurvedAnimation(parent: _sheetAnim, curve: Curves.easeInOut);
    _loadMapStyle();
    _buildLocationDotIcon().then((icon) {
      if (mounted) setState(() => _locationDotIcon = icon);
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
    _loadUser();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingOrder();
      _connectSocket();
      // Polling de secours toutes les 10s pour être sûr d'avoir le badge à jour
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _checkPendingOrder();
      });
      // Popup "vous avez une réduction disponible" — une seule fois par
      // campagne (voir promo_highlight_popup.dart), silencieuse s'il n'y en
      // a aucune ou en cas d'échec réseau.
      maybeShowPromoHighlight(
        context,
        fetch: OrdersRepository().getHighlightPromo,
      );
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
    // Appelée lorsque l'écran courant redevient le premier plan (au dessus est poppé)
    _checkPendingOrder();
  }

  StreamSubscription<void>? _reconnectSub;

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _orderAcceptedSub?.cancel();
    _reconnectSub?.cancel();
    _locationSub?.cancel();
    _locationModeCtrl.dispose();
    _positionReveal.dispose();
    _programmaticMoveTimer?.cancel();
    _pollTimer?.cancel();
    _mapController?.dispose();
    _sheetAnim.dispose();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;

    SocketService.instance.connect(token);

    // Reconnexion socket (backend restart, app retour réseau) → resync immédiat
    _reconnectSub = SocketService.instance.onReconnect.listen((_) {
      if (mounted) _checkPendingOrder();
    });

    _orderAcceptedSub = SocketService.instance.onOrderAccepted.listen((data) {
      if (!mounted) return;
      final acceptedId = data['orderId'] as String?;
      final driverId = data['driverId'] as String?;
      setState(() {
        _pendingOrders.removeWhere((o) => o['id'] == acceptedId);
      });
      if (acceptedId != null && driverId != null) {
        final eta = data['etaPickupMin'] as int?;

        // Affiche une vraie notification système locale
        NotificationService.showSystemNotification(
          title: 'Course acceptée !',
          body: 'Un livreur est en route${eta != null ? ' (~$eta min)' : '.'}',
        );

        context.push(
          '/orders/tracking',
          extra: {
            'orderId': acceptedId,
            'driverId': driverId,
            'etaPickupMin': eta,
          },
        );
      }
    });

    // Notifications de position gérées par ClientOrderNotifier (tracking provider)
    // → pas de listener driverLocation ici pour éviter les doublons
  }

  void _toggleSheet() {
    if (_sheetExpanded) {
      _sheetAnim.reverse();
    } else {
      _sheetAnim.forward();
    }
    setState(() => _sheetExpanded = !_sheetExpanded);
  }

  void _onSheetDragUpdate(DragUpdateDetails d) {
    final newVal = (_sheetAnim.value - d.delta.dy / 200).clamp(0.0, 1.0);
    _sheetAnim.value = newVal;
  }

  void _onSheetDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v > 200 || _sheetAnim.value < 0.5) {
      _sheetAnim.reverse();
      setState(() => _sheetExpanded = false);
    } else {
      _sheetAnim.forward();
      setState(() => _sheetExpanded = true);
    }
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

  // ── Icône dot GPS (mode libre — marker natif, suit la carte sans lag) ──────
  static Future<BitmapDescriptor> _buildLocationDotIcon() async {
    const double size = 72;
    const double cx = size / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(cx, cx),
      28,
      Paint()..color = const Color(0x3300D4FF),
    );
    canvas.drawCircle(
      const Offset(cx, cx),
      11,
      Paint()..color = const Color(0xFF00D4FF),
    );
    canvas.drawCircle(
      const Offset(cx, cx),
      11,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final img = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: size / 2,
      height: size / 2,
    );
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> _startGPS() async {
    // Étape 1 : affichage instantané depuis le cache app (toujours GPS, jamais antenne réseau)
    final cached = await NavigationService.getCachedPosition();
    if (cached != null && mounted) {
      setState(() => _clientPosition = cached);
      _setCamera(position: cached);
      _positionReveal.reveal(withDrop: false);
    }

    // Étape 2 : position fraîche — requestLocation() sur iOS, jamais de cache
    final fresh = await NavigationService.requestAndGetPosition();
    if (fresh != null && mounted) {
      setState(() => _clientPosition = fresh);
      _setCamera(position: fresh);
      NavigationService.savePosition(fresh);
      _positionReveal.reveal(withDrop: false);
    }

    // Étape 3 : stream continu
    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() {
      _clientPosition = position;
      if (position.heading >= 0) _travelHeading = position.heading;
    });
    if (!_locationModeCtrl.isFree) _setCamera(position: position);
  }

  // ── Caméra GPS follow (animée, lisse) ─────────────────────────────────────
  void _setCamera({Position? position, double? bearing}) {
    final pos = position ?? _clientPosition;
    if (pos == null || _mapController == null) return;
    _programmaticMove = true;
    _programmaticMoveTimer?.cancel();
    _programmaticMoveTimer = Timer(const Duration(milliseconds: 600), () {
      _programmaticMove = false;
    });
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: _currentZoom < 13 ? 15 : _currentZoom,
          bearing: bearing ?? 0,
          tilt: 40,
        ),
      ),
    );
  }

  // ── Caméra boussole (instantanée, pas d'animation qui s'empile) ───────────
  void _compassCamera(double heading) {
    if (_clientPosition == null || _mapController == null) return;
    _programmaticMove = true;
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(_clientPosition!.latitude, _clientPosition!.longitude),
          zoom: _currentZoom < 13 ? 15 : _currentZoom,
          bearing: heading,
          tilt: 50,
        ),
      ),
    );
  }

  // Réagit à chaque changement de mode/cap venant du contrôleur partagé —
  // recalcule la caméra selon le nouveau mode et rebuild (bouton, dot overlay).
  void _onLocationModeUpdate() {
    if (!mounted) return;
    if (_locationModeCtrl.isFree) {
      _programmaticMove = false;
    } else if (_locationModeCtrl.isCompass) {
      _compassCamera(_locationModeCtrl.compassBearing);
    } else {
      _setCamera();
    }
    setState(() {});
  }

  // ── Marqueurs : GPS natif (free) + POI ────────────────────────────────────
  Set<Marker> get _clientMarkers {
    final markers = <Marker>{};
    // En mode libre : marker natif Google Maps (suit la carte sans lag)
    if (_locationModeCtrl.isFree && _clientPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('client'),
          position: LatLng(
            _clientPosition!.latitude,
            _clientPosition!.longitude,
          ),
          icon:
              _locationDotIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 10,
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

  // ── User ──────────────────────────────────────────────────────────────────
  Future<void> _loadUser() async {
    final cached = await AuthStorage.getUser();
    if (mounted) setState(() => _user = cached);
    try {
      final res = await ApiClient.dio.get('/users/me');
      final user = res.data as Map<String, dynamic>;
      await AuthStorage.saveUser(user);
      if (mounted) setState(() => _user = user);
    } catch (_) {}
  }

  // ── Vérifie l'état des commandes au retour/connexion ──────────────────────
  Future<void> _checkPendingOrder() async {
    if (!mounted || _checkingOrders) return;
    _checkingOrders = true;
    try {
      final orders = await ref.read(ordersRepositoryProvider).getMyOrders();

      // Priorité 1 : course active (driver en route)
      const activeStatuses = ['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'];
      final activeList = orders
          .where(
            (o) => activeStatuses.contains(
              (o['status'] as String? ?? '').toUpperCase(),
            ),
          )
          .toList();

      if (activeList.isNotEmpty) {
        final active = activeList.first;
        final orderId = active['id'] as String?;
        final driverId =
            (active['driver'] as Map?)?['id'] as String? ??
            active['driverId'] as String?;
        final delivery =
            active['deliveryAddress'] as String? ?? 'votre destination';

        NotificationService.showOngoingNotification(
          id: 8888,
          title: 'Course en cours',
          body: 'En route vers : $delivery',
        );

        final shouldRedirect =
            _isInitialLoad &&
            !ref.read(trackingMinimizedProvider) &&
            orderId != null &&
            driverId != null;
        _isInitialLoad = false;

        if (shouldRedirect && mounted) {
          setState(() => _activeOrders = activeList);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.push(
                '/orders/tracking',
                extra: {'orderId': orderId, 'driverId': driverId},
              );
            }
          });
          return;
        }

        if (mounted) setState(() => _activeOrders = activeList);
        return;
      } else {
        NotificationService.cancelNotification(8888);
      }

      if (ref.read(trackingMinimizedProvider)) {
        ref.read(trackingMinimizedProvider.notifier).state = false;
      }

      // Priorité 2 : commande récemment livrée → dialog (une seule fois)
      const doneStatuses = ['DELIVERED', 'PAYMENT_CONFIRMED'];
      final delivered = orders.firstWhere(
        (o) =>
            doneStatuses.contains((o['status'] as String? ?? '').toUpperCase()),
        orElse: () => {},
      );

      if (delivered.isNotEmpty && mounted) {
        final orderId = delivered['id'] as String? ?? '';
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final shownIds = prefs.getStringList(_kDeliveredKey) ?? [];
        if (!shownIds.contains(orderId)) {
          // Persiste immédiatement : si _checkPendingOrder est rappelé avant que
          // addPostFrameCallback s'exécute (socket, retour écran), l'ID est déjà marqué.
          shownIds.add(orderId);
          await prefs.setStringList(_kDeliveredKey, shownIds);
          if (!mounted) return;
          setState(() => _activeOrders = activeList);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showDeliveredDialog(delivered, prefs, shownIds);
          });
          return;
        }
      }

      // Priorité 3 : commandes PENDING → badge
      final pendingList = orders
          .where(
            (o) => (o['status'] as String? ?? '').toUpperCase() == 'PENDING',
          )
          .toList();

      if (mounted) {
        setState(() {
          _activeOrders = activeList;
          _pendingOrders = pendingList;
        });
      }
    } catch (_) {
    } finally {
      _checkingOrders = false;
    }
  }

  // ── Dialog commande livrée ─────────────────────────────────────────────────
  void _showDeliveredDialog(
    Map<String, dynamic> order,
    SharedPreferences prefs,
    List<String> shownIds,
  ) {
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final delivery = order['deliveryAddress'] as String? ?? '—';

    Timer? autoClose;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        // Auto-dismiss après 30 secondes
        autoClose = Timer(const Duration(seconds: 30), () {
          if (ctx.mounted) Navigator.of(ctx).pop();
        });

        void dismiss() {
          autoClose?.cancel();
          Navigator.of(ctx).pop();
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary,
                  AppColors.primaryMid,
                  AppColors.primaryDark,
                ],
              ),
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Commande livrée !',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  delivery,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  formatFcfa(price),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      dismiss();
                      context.push('/orders/my');
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
                      'Voir mes commandes',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: dismiss,
                  child: Text(
                    'Fermer',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.70),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) => autoClose?.cancel());
  }

  // ── Badge unique intelligent (priorité métier) ──────────────────────────
  Widget? _buildSmartBadge() {
    final allOrders = [..._activeOrders, ..._pendingOrders];
    if (allOrders.isEmpty) return null;

    // Couleur/icône selon la priorité la plus haute présente
    final hasEnRoute = _activeOrders.any((o) {
      final s = (o['status'] as String? ?? '').toUpperCase();
      return s == 'PICKED_UP' || s == 'IN_TRANSIT';
    });
    final hasAccepted = _activeOrders.any(
      (o) => (o['status'] as String? ?? '').toUpperCase() == 'ACCEPTED',
    );

    final Color color;
    final IconData icon;
    if (hasEnRoute) {
      color = AppColors.primary;
      icon = Icons.delivery_dining;
    } else if (hasAccepted) {
      color = AppColors.accentMint;
      icon = Icons.two_wheeler;
    } else {
      color = AppColors.warning;
      icon = Icons.timer;
    }

    final n = allOrders.length;
    final label = n == 1
        ? (hasEnRoute
              ? 'Livraison en cours'
              : hasAccepted
              ? 'Course en cours'
              : '1 en attente')
        : '$n livraisons actives';

    // Tap : direct si 1 seule commande, sheet de choix sinon
    final VoidCallback onTap;
    if (n == 1) {
      final single = allOrders.first;
      final sStatus = (single['status'] as String? ?? '').toUpperCase();
      onTap = sStatus == 'PENDING'
          ? () => context.push('/orders/confirmation', extra: single)
          : () => _goToTracking(single);
    } else {
      onTap = () => _showAllOrdersSheet(allOrders);
    }

    return _buildBadge(color: color, icon: icon, label: label, onTap: onTap);
  }

  Widget _buildBadge({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToTracking(Map<String, dynamic> order) {
    final driverId =
        (order['driver'] as Map?)?['id'] as String? ??
        order['driverId'] as String?;
    if (driverId == null) return;
    context.push(
      '/orders/tracking',
      extra: {
        'orderId': order['id'],
        'driverId': driverId,
        'initialOrder': order, // données pré-chargées → zéro latence
      },
    );
  }

  // ── Sheet unifiée : toutes les commandes actives + en attente ───────────
  void _showAllOrdersSheet(List<Map<String, dynamic>> orders) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          gradient: AppColors.gradientSplash,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(ctx).viewPadding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.delivery_dining,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Choisir une livraison (${orders.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...orders.map((o) {
              final status = (o['status'] as String? ?? '').toUpperCase();
              final delivery = o['deliveryAddress'] as String? ?? '—';
              final pickup = o['pickupAddress'] as String? ?? '—';
              final price = (o['price'] as num?)?.toInt() ?? 0;
              final isPending = status == 'PENDING';

              final String statusLabel = switch (status) {
                'PICKED_UP' || 'IN_TRANSIT' => 'En route vers vous',
                'ACCEPTED' => 'Livreur en route',
                'PENDING' => 'En attente de livreur',
                _ => 'En traitement',
              };
              final Color statusColor = switch (status) {
                'PICKED_UP' || 'IN_TRANSIT' => AppColors.success,
                'ACCEPTED' => AppColors.primary,
                'PENDING' => AppColors.warning,
                _ => Colors.white54,
              };

              return GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  if (isPending) {
                    context.push('/orders/confirmation', extra: o);
                  } else {
                    _goToTracking(o);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPending ? Icons.timer : Icons.two_wheeler,
                          color: statusColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              delivery,
                              style: ClientText.body.copyWith(
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              pickup,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                statusLabel,
                                style: ClientText.caption.copyWith(
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatFcfa(price),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isPending ? 'Voir →' : 'Suivre →',
                            style: ClientText.caption.copyWith(
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte plein écran Google Maps style Waze ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _dakar,
                zoom: 15,
                tilt: 40,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_clientPosition != null) _setCamera();
              },
              style: _mapStyle,
              onCameraMove: (pos) {
                if (!_programmaticMove && !_locationModeCtrl.isFree) {
                  _locationModeCtrl.notifyManualPan();
                }
                if ((pos.zoom - _currentZoom).abs() > 0.5) {
                  setState(() => _currentZoom = pos.zoom);
                }
              },
              onCameraIdle: () => _programmaticMove = false,
              markers: _clientMarkers,
              circles: _clientPosition != null
                  ? _positionReveal.haloCircles(
                      LatLng(
                        _clientPosition!.latitude,
                        _clientPosition!.longitude,
                      ),
                      color: AppColors.primary,
                      idPrefix: 'client-halo',
                    )
                  : const {},
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
            ),
          ),

          // ── Dot overlay (follow/compass uniquement — free utilise un Marker) ──
          if (_clientPosition != null && !_locationModeCtrl.isFree)
            Center(
              child: _PulsingLocationDot(
                heading: _locationModeCtrl.isCompass
                    ? _locationModeCtrl.compassBearing
                    : (_travelHeading > 0 ? _travelHeading : null),
              ),
            ),

          // ── Scrim en haut de carte : lisibilité de la status bar sur le
          // fond de carte clair/varié (pattern Uber/Yango), ignore les taps.
          IgnorePointer(
            child: Container(
              height: MediaQuery.of(context).padding.top + 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.55),
                    AppColors.background.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // ── Navbar + Sheet empilés en bas ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Flottants juste au dessus du bottom sheet ──
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
                      // ── GAUCHE : Nuit/Jour ────────────────────────────────
                      MapThemeToggleButton(onTap: _toggleMapTheme),

                      // ── DROITE : Badge + Recenter ────────────────────────
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Builder(
                            builder: (_) {
                              final badge = _buildSmartBadge();
                              return badge != null
                                  ? Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: badge,
                                    )
                                  : const SizedBox.shrink();
                            },
                          ),
                          MapLocationModeButton(
                            mode: _locationModeCtrl.mode,
                            compassBearing: _locationModeCtrl.compassBearing,
                            onTap: _locationModeCtrl.cycle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Sheet rétractable ──
                _AnimatedSheet(
                  animation: _sheetSlide,
                  onToggle: _toggleSheet,
                  expanded: _sheetExpanded,
                  onDragUpdate: _onSheetDragUpdate,
                  onDragEnd: _onSheetDragEnd,
                  child: _buildServiceContent(),
                ),

                // ── Navbar fixe ──
                _ClientNavBar(bottomInset: bottomInset),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Contenu choix du service ───────────────────────────────────────────────
  Widget _buildServiceContent() {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = 'Bonjour';
    } else if (hour >= 12 && hour < 18) {
      greeting = 'Bon après-midi';
    } else {
      greeting = 'Bonsoir';
    }

    final fullName = _user?['name'] as String? ?? 'user';
    final firstName = fullName.split(' ').first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (firstName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '$greeting $firstName 👋',
              style: ClientText.body.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Text(
          'Programmez une livraison en quelques clics.',
          style: ClientText.title.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.l),
        _ServiceCard(
          icon: Icons.inventory_2_outlined,
          label: 'Livraison simple',
          subtitle: 'Envoyez ou recevez un colis',
          color: AppColors.primary,
          onTap: () async {
            if (!await ensureLocationEnabled(context)) return;
            if (!mounted) return;
            await context.push('/orders/create?type=DELIVERY');
            _checkPendingOrder();
          },
        ),
        const SizedBox(height: AppSpacing.m),
        _ServiceCard(
          icon: Icons.route_outlined,
          label: 'Livraison groupée',
          subtitle: '1 collecte, plusieurs destinations',
          color: AppColors.primary,
          onTap: () async {
            if (!await ensureLocationEnabled(context)) return;
            if (!mounted) return;
            await context.push('/orders/batch/create');
            _checkPendingOrder();
          },
        ),
      ],
    );
  }
}

// ── Sheet animée wrappeuse ────────────────────────────────────────────────────
class _AnimatedSheet extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final VoidCallback onToggle;
  final bool expanded;
  final void Function(DragUpdateDetails) onDragUpdate;
  final void Function(DragEndDetails) onDragEnd;

  const _AnimatedSheet({
    required this.animation,
    required this.child,
    required this.onToggle,
    required this.expanded,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.gradientSplash,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──
          GestureDetector(
            onTap: onToggle,
            onVerticalDragUpdate: onDragUpdate,
            onVerticalDragEnd: onDragEnd,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu animé ──
          SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Navbar client ─────────────────────────────────────────────────────────────
class _ClientNavBar extends StatelessWidget {
  final double bottomInset;
  const _ClientNavBar({required this.bottomInset});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _navBarHeight + bottomInset,
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.home_rounded,
                label: 'Accueil',
                active: true,
                onTap: () {},
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.receipt_long_outlined,
                label: 'Commandes',
                active: false,
                onTap: () => context.push('/orders/my'),
              ),
            ),
            Expanded(
              child: _NavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profil',
                active: false,
                onTap: () => context.push('/client/profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              color: active ? AppColors.primary : AppColors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dot de position animé (overlay Flutter sur la carte) ─────────────────────
class _PulsingLocationDot extends StatefulWidget {
  final double? heading; // degrés depuis le nord, null = pas de direction
  const _PulsingLocationDot({this.heading});

  @override
  State<_PulsingLocationDot> createState() => _PulsingLocationDotState();
}

class _PulsingLocationDotState extends State<_PulsingLocationDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF00D4FF);
    final hasHeading = widget.heading != null;

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anneau pulsé
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => Opacity(
              opacity: (1.0 - _pulse.value).clamp(0.0, 1.0),
              child: Container(
                width: 14 + 42 * _pulse.value,
                height: 14 + 42 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cyan.withValues(alpha: 0.30),
                ),
              ),
            ),
          ),
          // Flèche directionnelle (tourne selon heading)
          if (hasHeading)
            Transform.rotate(
              angle: widget.heading! * pi / 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pointe de la flèche au-dessus du dot
                  Icon(
                    Icons.navigation,
                    color: Colors.white,
                    size: 22,
                    shadows: [
                      Shadow(
                        color: cyan.withValues(alpha: 0.9),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          // Dot central cyan
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cyan,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: cyan.withValues(alpha: 0.65),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chevron qui "invite" doucement au tap — sans être agressif ─────────────────
// ── Badge d'icône "respirant" — pulse doucement pour attirer l'œil sans être
// criard (même principe que l'anneau de proximité du bouton livreur) ──────────
class _BreathingBadge extends StatefulWidget {
  final IconData icon;
  final Color color;
  const _BreathingBadge({required this.icon, required this.color});

  @override
  State<_BreathingBadge> createState() => _BreathingBadgeState();
}

class _BreathingBadgeState extends State<_BreathingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Transform.scale(
          scale: 1.0 + t * 0.08,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              border: Border.all(color: widget.color.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.25 + t * 0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      // Léger dégradé sur l'icône (façon "duotone") plutôt qu'un aplat blanc
      // uni — plus riche visuellement sans dépendre d'assets SVG custom.
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xCCFFFFFF)],
        ).createShader(bounds),
        child: Icon(widget.icon, color: Colors.white, size: 24),
      ),
    );
  }
}

// Ombre large et diffuse plutôt que serrée — c'est ce qui distingue une
// carte "premium" d'un bloc plat, indépendamment de la couleur ou du texte.
const _kPremiumCardShadow = [
  BoxShadow(color: Color(0x40000000), blurRadius: 28, offset: Offset(0, 10)),
];
final _kPremiumCardRadius = BorderRadius.circular(18);

// ── Service card ──────────────────────────────────────────────────────────────
class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (subtitle != null) {
      final accent = color ?? AppColors.primary;
      return Pressable(
        onTap: onTap,
        darkenOnPress: true,
        darkenBorderRadius: _kPremiumCardRadius,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xl,
            horizontal: AppSpacing.xl,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: _kPremiumCardRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: _kPremiumCardShadow,
          ),
          child: Row(
            children: [
              _BreathingBadge(icon: icon, color: accent),
              const SizedBox(width: AppSpacing.m + 2),
              // `Expanded` : sans quoi le titre/sous-titre poussent le
              // chevron hors de la carte dès qu'ils dépassent l'espace
              // disponible (texte plus long, police système agrandie...) —
              // toujours prévoir la place, jamais supposer un texte court.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: ClientText.subtitle.copyWith(
                        color: Colors.white,
                        height: 1.25,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: ClientText.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NudgingChevron(color: accent.withValues(alpha: 0.85)),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
