import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/map/map_style_service.dart';
import '../../core/map/poi_data.dart';
import '../../core/map/poi_service.dart';
import '../../core/router/app_router.dart';
import '../../core/services/location_reveal_controller.dart';
import '../../core/services/map_location_mode_controller.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/location_gate.dart';
import '../../core/utils/price_format.dart';
import '../../core/notifications/notification_service.dart';
import '../../shared/widgets/colored_address_field.dart';
import '../../shared/widgets/favorite_address_chips.dart';
import '../../shared/widgets/floating_back_button.dart';
import '../../shared/widgets/floating_map_button.dart';
import '../../shared/widgets/map_location_mode_button.dart';
import '../../shared/widgets/map_placement_pin.dart';
import '../../shared/widgets/place_suggestions_list.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/promo_highlight_popup.dart';
import '../../shared/widgets/screen_pulse_ring.dart';
import '../../shared/widgets/staggered_entrance.dart';
import '../../shared/widgets/wizard_top_bar.dart';
import '../deliveries/data/orders_repository.dart';
import '../deliveries/providers/orders_provider.dart';
import '../home_driver/navigation/navigation_service.dart';
import '../notifications/data/notifications_repository.dart';
import 'home_client_sheet_scaffold.dart';
import 'map_host.dart';
import 'order_wizard/order_wizard_controller.dart';

const _dakar = LatLng(14.6937, -17.4441);
const double _navBarHeight = 64;

enum ClientHomeMode { home, expressSimpleWizard, batchWizard }

/// Écran unique de l'accueil client + des 3 parcours de création de
/// livraison (Express, Simple, Groupée) — une seule carte persistante,
/// seule la feuille du bas change de contenu selon [ClientHomeMode] (voir
/// le plan de fusion, chantier pré-production). Remplace l'ancien trio
/// home_client_screen.dart / order_create_screen.dart / batch_create_screen.dart
/// pour Express/Simple (Groupée arrive à l'étape B, encore sur son ancienne
/// route séparée pour l'instant).
class ClientHomeShellScreen extends ConsumerStatefulWidget {
  const ClientHomeShellScreen({super.key});

  @override
  ConsumerState<ClientHomeShellScreen> createState() =>
      _ClientHomeShellScreenState();
}

class _ClientHomeShellScreenState extends ConsumerState<ClientHomeShellScreen>
    with TickerProviderStateMixin, RouteAware
    implements MapHost {
  // ── Mode ─────────────────────────────────────────────────────────────────
  ClientHomeMode _mode = ClientHomeMode.home;
  OrderWizardController? _orderWizard;

  // ── Accueil : commandes / notifications ────────────────────────────────
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _pendingOrders = [];
  List<Map<String, dynamic>> _activeOrders = [];
  bool _isInitialLoad = true;
  static const _kDeliveredKey = 'dem_shown_delivered_ids';

  /// Course acceptée pendant que le client est en train de remplir un
  /// formulaire (Express/Simple/Groupée) — bandeau discret au lieu d'une
  /// redirection qui écraserait sa saisie en cours (décision produit).
  Map<String, dynamic>? _pendingAcceptedBanner;

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  double _currentZoom = 15;
  BitmapDescriptor? _locationDotIcon;
  bool _isMapMoving = false;
  LatLng _currentCameraPos = _dakar;

  // ── POI ───────────────────────────────────────────────────────────────────
  PoiIconSet? _poiIconSet;
  List<PoiPoint>? _pois;

  // ── WebSocket ─────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _orderAcceptedSub;
  StreamSubscription<void>? _reconnectSub;

  // ── GPS + boussole ────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _clientPosition;
  double _travelHeading = 0;
  late final _locationModeCtrl = MapLocationModeController(
    onUpdate: _onLocationModeUpdate,
  );
  bool _programmaticMove = false;
  Timer? _programmaticMoveTimer;

  late final _positionReveal = LocationRevealController(
    vsync: this,
    onUpdate: () => setState(() {}),
  );

  // ── Feuille du bas (partagée par les 3 modes) ──────────────────────────
  final _sheetKey = GlobalKey();
  double? _sheetHeight;
  double _dragOffset = 0.0;
  bool _isDragging = false;
  static const _kMinPanelContent = 66.0;

  void _measureSheetHeight({int framesLeft = 24}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = _sheetKey.currentContext?.size?.height;
      if (h != null &&
          (_sheetHeight == null || (h - _sheetHeight!).abs() > 0.5)) {
        setState(() => _sheetHeight = h);
      }
      if (framesLeft > 0) _measureSheetHeight(framesLeft: framesLeft - 1);
    });
  }

  double get _panelHeight =>
      _sheetHeight ?? MediaQuery.of(context).size.height * 0.62;

  // ── Polling de secours ──────────────────────────────────────────────────
  Timer? _pollTimer;
  bool _checkingOrders = false;
  bool _isOffline = false;

  // ── Notifications ─────────────────────────────────────────────────────────
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
    _loadUnreadNotifCount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingOrder();
      _connectSocket();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _checkPendingOrder(),
      );
      maybeShowPromoHighlight(
        context,
        fetch: OrdersRepository().getHighlightPromo,
        accentColor: AppColors.primaryMid,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) routeObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // Fermeture d'une route poussée par-dessus ce socle (suivi, confirmation,
    // notifications, favoris, profil, mes commandes) — inchangé par rapport
    // à l'ancien home_client_screen.dart. Ne touche pas au mode en cours :
    // si l'utilisateur était en plein assistant avant de consulter une
    // notification, il le retrouve tel quel au retour.
    _checkPendingOrder();
    _loadUnreadNotifCount();
  }

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
    _orderWizard?.dispose();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;
    SocketService.instance.connect(token);

    _reconnectSub = SocketService.instance.onReconnect.listen((_) {
      if (mounted) _checkPendingOrder();
    });

    _orderAcceptedSub = SocketService.instance.onOrderAccepted.listen((data) {
      if (!mounted) return;
      final acceptedId = data['orderId'] as String?;
      final driverId = data['driverId'] as String?;
      setState(() => _pendingOrders.removeWhere((o) => o['id'] == acceptedId));
      if (acceptedId == null || driverId == null) return;
      final eta = data['etaPickupMin'] as int?;

      NotificationService.showSystemNotification(
        title: 'Course acceptée !',
        body: 'Un livreur est en route${eta != null ? ' (~$eta min)' : '.'}',
      );

      final extra = {
        'orderId': acceptedId,
        'driverId': driverId,
        'etaPickupMin': eta,
      };
      if (_mode == ClientHomeMode.home) {
        context.push('/orders/tracking', extra: extra);
      } else {
        // Formulaire en cours — bandeau discret plutôt qu'une redirection
        // qui écraserait la saisie (décision produit validée).
        setState(() => _pendingAcceptedBanner = extra);
      }
    });
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
    final cached = await NavigationService.getCachedPosition();
    if (cached != null && mounted) {
      setState(() => _clientPosition = cached);
      _setCamera(position: cached);
      _positionReveal.reveal(withDrop: false);
    }
    final fresh = await NavigationService.requestAndGetPosition();
    if (fresh != null && mounted) {
      setState(() => _clientPosition = fresh);
      _setCamera(position: fresh);
      NavigationService.savePosition(fresh);
      _positionReveal.reveal(withDrop: false);
    }
    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() {
      _clientPosition = position;
      if (position.heading >= 0) _travelHeading = position.heading;
    });
    if (!_locationModeCtrl.isFree && _mode == ClientHomeMode.home)
      _setCamera(position: position);
  }

  void _setCamera({Position? position, double? bearing}) {
    final pos = position ?? _clientPosition;
    if (pos == null || _mapController == null) return;
    _programmaticMove = true;
    _programmaticMoveTimer?.cancel();
    _programmaticMoveTimer = Timer(
      const Duration(milliseconds: 600),
      () => _programmaticMove = false,
    );
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

  void _onLocationModeUpdate() {
    if (!mounted || _mode != ClientHomeMode.home) return;
    if (_locationModeCtrl.isFree) {
      _programmaticMove = false;
    } else if (_locationModeCtrl.isCompass) {
      _compassCamera(_locationModeCtrl.compassBearing);
    } else {
      _setCamera();
    }
    setState(() {});
  }

  // ── MapHost ──────────────────────────────────────────────────────────────
  @override
  GoogleMapController? get mapController => _mapController;

  @override
  LatLng? get currentPosition => _clientPosition != null
      ? LatLng(_clientPosition!.latitude, _clientPosition!.longitude)
      : null;

  @override
  LatLng get currentCameraPosition => _currentCameraPos;

  @override
  bool get isMapMoving => _isMapMoving;

  @override
  void centerOn(LatLng pos, {double zoom = 14, double tilt = 30}) {
    final panelH = _panelHeight;
    final metersPerPixel =
        156543.03392 * cos(pos.latitude * pi / 180) / pow(2, zoom);
    final latShift = (panelH / 2) * metersPerPixel / 111320.0;
    final adjusted = LatLng(pos.latitude - latShift, pos.longitude);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: adjusted, zoom: zoom, tilt: tilt),
      ),
    );
  }

  @override
  void fitPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      centerOn(points.first);
      return;
    }
    var south = points.first.latitude, north = points.first.latitude;
    var west = points.first.longitude, east = points.first.longitude;
    for (final p in points.skip(1)) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    final screenH = MediaQuery.of(context).size.height;
    final panelH = _panelHeight;
    final hiddenFrac = (panelH / screenH).clamp(0.05, 0.85);
    final visibleFrac = (1 - hiddenFrac).clamp(0.15, 0.95);
    final latSpan = (north - south).clamp(0.0015, 1.0);
    final extraSouth = latSpan * (hiddenFrac / visibleFrac);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south - extraSouth, west),
          northeast: LatLng(north, east),
        ),
        56,
      ),
    );
  }

  @override
  void requestSheetRemeasure() {
    setState(() => _sheetHeight = null);
    _measureSheetHeight();
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
      if (_isOffline && mounted) {
        setState(() => _isOffline = false);
        showDemToast(context, 'Connexion rétablie.');
      }

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
            if (!mounted) return;
            final extra = {'orderId': orderId, 'driverId': driverId};
            if (_mode == ClientHomeMode.home) {
              context.push('/orders/tracking', extra: extra);
            } else {
              setState(() => _pendingAcceptedBanner = extra);
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
      if (!_isOffline && mounted) {
        setState(() => _isOffline = true);
        showDemToast(
          context,
          'Connexion perdue — nouvelle tentative en cours…',
          isError: true,
        );
      }
    } finally {
      _checkingOrders = false;
    }
  }

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

  Widget? _buildSmartBadge() {
    final allOrders = [..._activeOrders, ..._pendingOrders];
    if (allOrders.isEmpty) return null;
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
    if (driverId == null) {
      showDemToast(
        context,
        'Impossible d\'ouvrir le suivi pour le moment — réessayez dans un instant.',
        isError: true,
      );
      return;
    }
    context.push(
      '/orders/tracking',
      extra: {
        'orderId': order['id'],
        'driverId': driverId,
        'initialOrder': order,
      },
    );
  }

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

  // ── Entrée/sortie des modes ────────────────────────────────────────────────
  Future<void> _enterExpressSimple({required String priority}) async {
    if (!await ensureLocationEnabled(context)) return;
    if (!mounted) return;
    setState(() {
      _orderWizard ??= OrderWizardController(
        orderType: 'DELIVERY',
        priority: priority,
        mapHost: this,
        onChanged: () => setState(() {}),
        onSubmitSuccess: () {
          setState(() {
            _orderWizard?.dispose();
            _orderWizard = null;
            _mode = ClientHomeMode.home;
          });
        },
        vsync: this,
      );
      _mode = ClientHomeMode.expressSimpleWizard;
      _dragOffset = 0;
      _isDragging = false;
    });
    requestSheetRemeasure();
  }

  void _exitWizardToHome() {
    setState(() {
      _mode = ClientHomeMode.home;
      _dragOffset = 0;
      _isDragging = false;
    });
    requestSheetRemeasure();
    _checkPendingOrder();
  }

  void _handleBack() {
    if (_mode == ClientHomeMode.expressSimpleWizard) {
      final wizard = _orderWizard!;
      if (wizard.isMapPlacementMode) {
        wizard.isMapPlacementMode = false;
        setState(() {});
        return;
      }
      if (wizard.step > 0) {
        wizard.goStep(wizard.step - 1, context);
      } else {
        _exitWizardToHome();
      }
    }
  }

  // ── Contenu accueil (choix du service) ─────────────────────────────────────
  Widget _buildHomeSheet() {
    final hour = DateTime.now().hour;
    final greeting = hour >= 5 && hour < 12
        ? 'Bonjour'
        : (hour >= 12 && hour < 18 ? 'Bon après-midi' : 'Bonsoir');
    final fullName = _user?['name'] as String? ?? 'user';
    final firstName = fullName.split(' ').first;

    return KeyedSubtree(
      key: const ValueKey('home'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
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
            Row(
              children: [
                Expanded(
                  child: StaggeredEntrance(
                    index: 0,
                    child: _ServiceTile(
                      icon: Icons.bolt_rounded,
                      label: 'Express',
                      valueLabel: 'Rapide',
                      color: AppColors.warning,
                      onTap: () => _enterExpressSimple(priority: 'EXPRESS'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: StaggeredEntrance(
                    index: 1,
                    child: _ServiceTile(
                      icon: Icons.inventory_2_outlined,
                      label: 'Simple',
                      valueLabel: 'Standard',
                      color: AppColors.primary,
                      onTap: () => _enterExpressSimple(priority: 'NORMAL'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: StaggeredEntrance(
                    index: 2,
                    child: _ServiceTile(
                      icon: Icons.route_outlined,
                      label: 'Groupée',
                      valueLabel: 'Économique',
                      color: AppColors.accentIndigo,
                      onTap: () async {
                        // Étape B — encore l'ancienne route séparée pour l'instant.
                        if (!await ensureLocationEnabled(context)) return;
                        if (!mounted) return;
                        await context.push('/orders/batch/create');
                        _checkPendingOrder();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetContent() {
    switch (_mode) {
      case ClientHomeMode.home:
        return _buildHomeSheet();
      case ClientHomeMode.expressSimpleWizard:
        return _orderWizard!.buildStep(context);
      case ClientHomeMode.batchWizard:
        return _buildHomeSheet();
    }
  }

  Set<Marker> get _markers {
    final result = <Marker>{};
    if (_mode == ClientHomeMode.home) {
      if (_locationModeCtrl.isFree && _clientPosition != null) {
        result.add(
          Marker(
            markerId: const MarkerId('client'),
            position: LatLng(
              _clientPosition!.latitude,
              _clientPosition!.longitude,
            ),
            icon:
                _locationDotIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
            flat: true,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 10,
          ),
        );
      }
      if (_poiIconSet != null && _pois != null) {
        result.addAll(
          buildPoiMarkersForZoom(_poiIconSet!, _currentZoom, _pois!),
        );
      }
    } else if (_mode == ClientHomeMode.expressSimpleWizard) {
      result.addAll(_orderWizard!.markers);
    }
    return result;
  }

  Set<Polyline> get _polylines {
    if (_mode == ClientHomeMode.expressSimpleWizard)
      return _orderWizard!.polylines;
    return {};
  }

  @override
  Widget build(BuildContext context) {
    _measureSheetHeight();
    MapStyleService.listen(ref, (style) => setState(() => _mapStyle = style));
    if (_mapStyle == null) {
      MapStyleService.load(ref).then((s) {
        if (mounted) setState(() => _mapStyle = s);
      });
    }

    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final isWizard = _mode != ClientHomeMode.home;
    final isPlacement =
        isWizard &&
        _mode == ClientHomeMode.expressSimpleWizard &&
        _orderWizard!.isMapPlacementMode;

    if (_mode == ClientHomeMode.expressSimpleWizard &&
        _orderWizard!.pickupLat != null &&
        !isPlacement) {
      _orderWizard!.maybeUpdatePickupScreenPos(
        LatLng(_orderWizard!.pickupLat!, _orderWizard!.pickupLng!),
      );
    }

    return PopScope(
      canPop: _mode == ClientHomeMode.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            SizedBox.expand(
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _dakar,
                  zoom: 15,
                  tilt: 40,
                ),
                onMapCreated: (c) {
                  _mapController = c;
                  if (_clientPosition != null) _setCamera();
                },
                style: _mapStyle,
                onTap: isWizard
                    ? (_) => FocusScope.of(context).unfocus()
                    : null,
                onCameraMoveStarted: () => setState(() => _isMapMoving = true),
                onCameraMove: (pos) {
                  _currentCameraPos = pos.target;
                  if (_mode == ClientHomeMode.home) {
                    if (!_programmaticMove && !_locationModeCtrl.isFree)
                      _locationModeCtrl.notifyManualPan();
                    if ((pos.zoom - _currentZoom).abs() > 0.5)
                      setState(() => _currentZoom = pos.zoom);
                  }
                },
                onCameraIdle: () {
                  setState(() => _isMapMoving = false);
                  _programmaticMove = false;
                  if (_mode == ClientHomeMode.expressSimpleWizard &&
                      _orderWizard!.pickupLat != null) {
                    // Sans condition (pas la variante "maybe") — le point
                    // suivi n'a pas forcément changé, mais après un
                    // pan/zoom/animation de caméra, sa position à l'écran
                    // si. Bug d'anneau de pulsation mal positionné repéré en
                    // test, corrigé ici.
                    _orderWizard!.forceUpdatePickupScreenPos(
                      LatLng(
                        _orderWizard!.pickupLat!,
                        _orderWizard!.pickupLng!,
                      ),
                    );
                  }
                },
                markers: _markers,
                polylines: _polylines,
                circles:
                    (_mode == ClientHomeMode.home && _clientPosition != null)
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

            // ── Overlays de position ────────────────────────────────────────
            if (_mode == ClientHomeMode.home &&
                _clientPosition != null &&
                !_locationModeCtrl.isFree)
              Center(
                child: _PulsingLocationDot(
                  heading: _locationModeCtrl.isCompass
                      ? _locationModeCtrl.compassBearing
                      : (_travelHeading > 0 ? _travelHeading : null),
                ),
              ),
            if (_mode == ClientHomeMode.expressSimpleWizard &&
                _orderWizard!.pickupLat != null &&
                (!_orderWizard!.isSelectingPickup ||
                    !_orderWizard!.isMapPlacementMode))
              ScreenPulseRing(
                position: _orderWizard!.pickupScreenPos,
                color: AppColors.success,
                size: 66,
              ),

            if (isPlacement)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 35),
                  child: AnimatedScale(
                    scale: _isMapMoving ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: MapPlacementPin(
                      color: _orderWizard!.isSelectingPickup
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ),
              ),

            // ── Voile dégradé en haut ───────────────────────────────────────
            IgnorePointer(
              child: Container(
                height: isWizard
                    ? 260
                    : (MediaQuery.of(context).padding.top + 56),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      (isWizard ? Colors.black : AppColors.background)
                          .withValues(alpha: isWizard ? 0.30 : 0.55),
                      (isWizard ? Colors.black : AppColors.background)
                          .withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),

            // ── Cloche notifications (accueil uniquement) ──────────────────
            if (!isWizard)
              Positioned(
                top: 0,
                right: 12,
                child: SafeArea(
                  bottom: false,
                  child: GestureDetector(
                    onTap: () async {
                      await context.push('/client/notifications');
                      _loadUnreadNotifCount();
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
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
                              color: AppColors.primary,
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
                ),
              ),

            // ── Barre assistant (Express/Simple) ────────────────────────────
            if (_mode == ClientHomeMode.expressSimpleWizard)
              ..._buildOrderWizardTopBar(),

            // ── Bandeau "course acceptée" pendant la saisie ─────────────────
            if (_pendingAcceptedBanner != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                child: SafeArea(
                  bottom: false,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        final extra = _pendingAcceptedBanner!;
                        setState(() => _pendingAcceptedBanner = null);
                        context.push('/orders/tracking', extra: extra);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.two_wheeler,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Course acceptée — voir',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _pendingAcceptedBanner = null),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Recentrer / favoris / badge (accueil) ou recentrer seul (assistant) ──
            if (!isWizard)
              Positioned(
                left: 0,
                right: 0,
                // - _dragOffset : sans lui, ces boutons restaient à la
                // hauteur de la feuille PLEINE même quand elle est
                // rétractée au glissé, laissant un grand vide entre eux et
                // la feuille repliée (repéré en test).
                bottom:
                    max(_kMinPanelContent, _panelHeight - _dragOffset) +
                    _navBarHeight +
                    bottomInset,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Pressable(
                        onTap: () => context.push('/client/favorite-addresses'),
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
                            boxShadow: AppShadows.floating,
                          ),
                          child: const Icon(
                            Icons.bookmark_outline_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                      ),
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
              )
            else
              Positioned(
                right: 16,
                bottom:
                    max(_kMinPanelContent + 22.0, _panelHeight - _dragOffset) +
                    60 +
                    keyboardH,
                child: FloatingMapButton(
                  icon: _orderWizard!.loadingGps ? null : Icons.my_location,
                  loading: _orderWizard!.loadingGps,
                  onTap: _orderWizard!.refreshGps,
                ),
              ),

            // ── Feuille du bas ───────────────────────────────────────────────
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: isWizard ? 0 : (_navBarHeight + bottomInset),
                ),
                child: HomeClientSheetScaffold(
                  sheetKey: _sheetKey,
                  panelHeight: _panelHeight,
                  dragOffset: _dragOffset,
                  isDragging: _isDragging,
                  keyboardHeight: keyboardH,
                  minPanelContent: _kMinPanelContent,
                  onDraggingChanged: (v) => setState(() => _isDragging = v),
                  onDragOffsetChanged: (v) => setState(() => _dragOffset = v),
                  onTapDismissKeyboard: () => FocusScope.of(context).unfocus(),
                  child: _buildSheetContent(),
                ),
              ),
            ),

            // ── Bouton retour flottant (assistant uniquement) ───────────────
            if (isWizard)
              Positioned(
                left: 16,
                bottom:
                    max(_kMinPanelContent + 22.0, _panelHeight - _dragOffset) +
                    60 +
                    keyboardH,
                child: FloatingBackButton(onTap: _handleBack),
              ),

            // ── Navbar fixe (accueil uniquement) ────────────────────────────
            if (!isWizard)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ClientNavBar(bottomInset: bottomInset),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOrderWizardTopBar() {
    final wizard = _orderWizard!;
    return [
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WizardTopBar(
                title: wizard.priority == 'EXPRESS'
                    ? 'Livraison Express ⚡'
                    : 'Livraison Simple',
                step: wizard.step,
                onReset: () {
                  if (wizard.step == 0) return;
                  FocusScope.of(context).unfocus();
                  wizard.goStep(0, context);
                },
              ),
              const SizedBox(height: 8),
              if (wizard.step == 0) ..._buildOrderAddressFields(wizard),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildOrderAddressFields(OrderWizardController wizard) {
    return [
      AddressField(
        controller: wizard.pickupCtrl,
        focusNode: wizard.pickupFocus,
        hint: 'Localisation actuelle',
        dotColor: AppColors.success,
        active: wizard.isSelectingPickup && !wizard.isMapPlacementMode,
        confirmed: wizard.pickupLat != null,
        readOnly: !wizard.pickupManualEntry,
        onTap: () {
          if (!wizard.pickupManualEntry) {
            wizard.showAddressMenu(forPickup: true, context: context);
            return;
          }
          wizard.isSelectingPickup = true;
          wizard.isMapPlacementMode = false;
          setState(() {});
          wizard.pickupFocus.requestFocus();
        },
        onChanged: (v) => wizard.onAddressChanged(v, forPickup: true),
        onClear: () {
          wizard.pickupCtrl.clear();
          wizard.pickupLat = null;
          wizard.pickupLng = null;
          wizard.estimatedPrice = null;
          wizard.routeDistanceKm = null;
          wizard.routeDurationMin = null;
          wizard.suggestions = [];
          wizard.isSelectingPickup = true;
          wizard.isMapPlacementMode = false;
          wizard.pickupManualEntry = false;
          setState(() {});
        },
        onMapTap: () {
          FocusScope.of(context).unfocus();
          wizard.isSelectingPickup = true;
          wizard.isMapPlacementMode = true;
          setState(() {});
        },
        onDotLongPress: () {
          FocusScope.of(context).unfocus();
          wizard.isSelectingPickup = true;
          wizard.isMapPlacementMode = true;
          setState(() {});
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(
          children: [
            const SizedBox(width: 7.5),
            SizedBox(
              width: 3,
              height: 20,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  3,
                  (_) => Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Pressable(
              onTap: () {
                wizard.swapAddresses();
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.40),
                  ),
                  boxShadow: AppShadows.floating,
                ),
                child: const Icon(
                  Icons.swap_vert,
                  color: AppColors.primary,
                  size: 17,
                ),
              ),
            ),
          ],
        ),
      ),
      AddressField(
        controller: wizard.deliveryCtrl,
        focusNode: wizard.deliveryFocus,
        hint: "Choisir l'adresse de destination",
        dotColor: AppColors.error,
        active: !wizard.isSelectingPickup && !wizard.isMapPlacementMode,
        confirmed: wizard.deliveryLat != null,
        readOnly: !wizard.deliveryManualEntry,
        onTap: () {
          if (!wizard.deliveryManualEntry) {
            wizard.showAddressMenu(forPickup: false, context: context);
            return;
          }
          wizard.isSelectingPickup = false;
          wizard.isMapPlacementMode = false;
          setState(() {});
          wizard.deliveryFocus.requestFocus();
        },
        onChanged: (v) => wizard.onAddressChanged(v, forPickup: false),
        onClear: () {
          wizard.deliveryCtrl.clear();
          wizard.deliveryLat = null;
          wizard.deliveryLng = null;
          wizard.estimatedPrice = null;
          wizard.routeDistanceKm = null;
          wizard.routeDurationMin = null;
          wizard.suggestions = [];
          wizard.isSelectingPickup = false;
          wizard.isMapPlacementMode = false;
          wizard.deliveryManualEntry = false;
          setState(() {});
        },
        onMapTap: () {
          FocusScope.of(context).unfocus();
          wizard.isSelectingPickup = false;
          wizard.isMapPlacementMode = true;
          setState(() {});
        },
        onDotLongPress: () {
          FocusScope.of(context).unfocus();
          wizard.isSelectingPickup = false;
          wizard.isMapPlacementMode = true;
          setState(() {});
        },
      ),
      if (wizard.favorites.isNotEmpty && !wizard.isMapPlacementMode) ...[
        const SizedBox(height: 6),
        FavoriteAddressChips(
          favorites: wizard.favorites,
          onSelect: wizard.applyFavorite,
        ),
      ],
      if (wizard.isSearching ||
          wizard.suggestions.isNotEmpty ||
          wizard.searchError != null) ...[
        const SizedBox(height: 6),
        PlaceSuggestionsList(
          suggestions: wizard.suggestions,
          loading: wizard.isSearching,
          error: wizard.searchError,
          onRetry: wizard.retryAddressSearch,
          onSelect: (place) => wizard.selectSuggestion(place, context),
          colors: _orderPlaceSuggestionsColors,
          maxHeight:
              (MediaQuery.of(context).size.height -
                      MediaQuery.of(context).viewInsets.bottom -
                      MediaQuery.of(context).padding.top -
                      160)
                  .clamp(100.0, 320.0),
        ),
      ],
    ];
  }
}

const _orderPlaceSuggestionsColors = PlaceSuggestionsColors(
  background: AppColors.card,
  border: Colors.white24,
  divider: AppColors.primary,
  iconBg: AppColors.primary,
  icon: Colors.white,
  mainText: Colors.white,
  secondaryText: AppColors.primary,
  accent: AppColors.primary,
);

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

class _PulsingLocationDot extends StatefulWidget {
  final double? heading;
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
          if (hasHeading)
            Transform.rotate(
              angle: widget.heading! * pi / 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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

class _BreathingBadge extends StatefulWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color color;
  const _BreathingBadge({
    required this.icon,
    this.size = 48,
    this.iconSize = 24,
    this.color = AppColors.primary,
  });

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
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
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
      child: Icon(widget.icon, color: widget.color, size: widget.iconSize),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final Color color;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BreathingBadge(
                  icon: icon,
                  size: 36,
                  iconSize: 18,
                  color: color,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: ClientText.label.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  valueLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
