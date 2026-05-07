import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/map/poi_data.dart';
import '../../core/router/app_router.dart';
import '../../core/services/socket_service.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/map_theme_provider.dart';
import '../deliveries/providers/orders_provider.dart';
import '../home_driver/navigation/map_theme.dart';
import '../home_driver/navigation/navigation_service.dart';

// Centre par défaut : Dakar
const _dakar = LatLng(14.6937, -17.4441);

enum _LocationMode { free, follow, compass }

// Hauteur de la navbar
const double _navBarHeight = 64;

class HomeClientScreen extends ConsumerStatefulWidget {
  const HomeClientScreen({super.key});

  @override
  ConsumerState<HomeClientScreen> createState() => _HomeClientScreenState();
}

class _HomeClientScreenState extends ConsumerState<HomeClientScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _pendingOrders = [];
  bool _loadingOrders = false;
  static const _kDeliveredKey = 'dem_shown_delivered_ids';

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  double _currentZoom = 15;
  BitmapDescriptor? _locationDotIcon;

  // ── POI ───────────────────────────────────────────────────────────────────
  PoiIconSet? _poiIconSet;

  // ── WebSocket ─────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _orderAcceptedSub;

  // ── GPS + boussole ────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<CompassEvent>? _compassSub;
  Position? _clientPosition;
  double _travelHeading = 0;
  _LocationMode _locationMode = _LocationMode.follow;
  double _compassBearing = 0;
  bool _programmaticMove = false;
  Timer? _programmaticMoveTimer;

  // ── Sheet rétractable ──────────────────────────────────────────────────────
  bool _sheetExpanded = true;
  late AnimationController _sheetAnim;
  late Animation<double> _sheetSlide;

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
    buildPoiIconSet().then((set) {
      if (mounted) setState(() => _poiIconSet = set);
    });
    _startGPS();
    _loadUser();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingOrder();
      _connectSocket();
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

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _orderAcceptedSub?.cancel();
    _locationSub?.cancel();
    _compassSub?.cancel();
    _programmaticMoveTimer?.cancel();
    _mapController?.dispose();
    _sheetAnim.dispose();
    super.dispose();
  }

  Future<void> _connectSocket() async {
    final token = await AuthStorage.getToken();
    if (token == null) return;

    SocketService.instance.connect(token);

    _orderAcceptedSub = SocketService.instance.onOrderAccepted.listen((data) {
      if (!mounted) return;
      final acceptedId = data['orderId'] as String?;
      final driverId = data['driverId'] as String?;
      setState(() {
        _pendingOrders.removeWhere((o) => o['id'] == acceptedId);
      });
      if (acceptedId != null && driverId != null) {
        context.push('/orders/tracking', extra: {
          'orderId': acceptedId,
          'driverId': driverId,
          'etaPickupMin': data['etaPickupMin'] as int?,
        });
      }
    });
  }

  void _toggleSheet() {
    if (_sheetExpanded) {
      _sheetAnim.reverse();
    } else {
      _sheetAnim.forward();
    }
    setState(() => _sheetExpanded = !_sheetExpanded);
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
    canvas.drawCircle(const Offset(cx, cx), 28,
        Paint()..color = const Color(0x3300D4FF));
    canvas.drawCircle(const Offset(cx, cx), 11,
        Paint()..color = const Color(0xFF00D4FF));
    canvas.drawCircle(
        const Offset(cx, cx), 11,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    final img = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        width: size / 2, height: size / 2);
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> _startGPS() async {
    final initial = await NavigationService.requestAndGetPosition();
    if (initial != null && mounted) {
      setState(() => _clientPosition = initial);
      _setCamera(position: initial);
    }
    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() {
      _clientPosition = position;
      if (position.heading >= 0) _travelHeading = position.heading;
    });
    if (_locationMode != _LocationMode.free) _setCamera(position: position);
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
      CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(pos.latitude, pos.longitude),
        zoom: _currentZoom < 13 ? 15 : _currentZoom,
        bearing: bearing ?? 0,
        tilt: 40,
      )),
    );
  }

  // ── Caméra boussole (instantanée, pas d'animation qui s'empile) ───────────
  void _compassCamera(double heading) {
    if (_clientPosition == null || _mapController == null) return;
    _programmaticMove = true;
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(_clientPosition!.latitude, _clientPosition!.longitude),
        zoom: _currentZoom < 13 ? 15 : _currentZoom,
        bearing: heading,
        tilt: 50,
      )),
    );
  }

  // ── Cycle : libre → suivi → boussole → libre ──────────────────────────────
  void _cycleLocationMode() {
    switch (_locationMode) {
      case _LocationMode.free:
        setState(() => _locationMode = _LocationMode.follow);
        _setCamera();
      case _LocationMode.follow:
        setState(() => _locationMode = _LocationMode.compass);
        _startCompassMode();
        _setCamera();
      case _LocationMode.compass:
        _stopCompassMode();
        setState(() => _locationMode = _LocationMode.free);
    }
  }

  void _startCompassMode() {
    _compassSub ??= FlutterCompass.events?.listen(_onCompassEvent);
  }

  void _stopCompassMode() {
    _compassSub?.cancel();
    _compassSub = null;
    _programmaticMove = false;
  }

  void _onCompassEvent(CompassEvent event) {
    final heading = event.heading;
    if (heading == null || !mounted || _locationMode != _LocationMode.compass) return;
    // Filtre : ignorer si changement < 2° pour éviter le tremblement
    if ((_compassBearing - heading).abs() < 2.0) return;
    setState(() => _compassBearing = heading);
    _compassCamera(heading);
  }

  // ── Marqueurs : GPS natif (free) + POI ────────────────────────────────────
  Set<Marker> get _clientMarkers {
    final markers = <Marker>{};
    // En mode libre : marker natif Google Maps (suit la carte sans lag)
    if (_locationMode == _LocationMode.free && _clientPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('client'),
        position: LatLng(_clientPosition!.latitude, _clientPosition!.longitude),
        icon: _locationDotIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 10,
      ));
    }
    if (_poiIconSet != null) {
      markers.addAll(buildPoiMarkersForZoom(_poiIconSet!, _currentZoom));
    }
    return markers;
  }

  // ── User ──────────────────────────────────────────────────────────────────
  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _user = user);
  }

  // ── Vérifie l'état des commandes au retour/connexion ──────────────────────
  Future<void> _checkPendingOrder() async {
    if (!mounted) return;
    setState(() => _loadingOrders = true);
    try {
      final orders = await ref.read(ordersRepositoryProvider).getMyOrders();

      // Priorité 1 : course active (driver en route) → redirect tracking
      const activeStatuses = ['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'];
      final active = orders.firstWhere(
        (o) => activeStatuses.contains((o['status'] as String? ?? '').toUpperCase()),
        orElse: () => {},
      );

      if (active.isNotEmpty && mounted) {
        final orderId = active['id'] as String?;
        final driverId = (active['driver'] as Map?)?['id'] as String?
            ?? active['driverId'] as String?;
        if (orderId != null && driverId != null) {
          if (mounted) setState(() => _loadingOrders = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.push('/orders/tracking', extra: {
                'orderId': orderId,
                'driverId': driverId,
              });
            }
          });
          return;
        }
      }

      // Priorité 2 : commande récemment livrée → dialog confirmation (une seule fois)
      const doneStatuses = ['DELIVERED', 'PAYMENT_CONFIRMED'];
      final delivered = orders.firstWhere(
        (o) => doneStatuses.contains((o['status'] as String? ?? '').toUpperCase()),
        orElse: () => {},
      );

      if (delivered.isNotEmpty && mounted) {
        final orderId = delivered['id'] as String? ?? '';
        final prefs = await SharedPreferences.getInstance();
        final shownIds = prefs.getStringList(_kDeliveredKey) ?? [];
        if (!shownIds.contains(orderId)) {
          setState(() => _loadingOrders = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showDeliveredDialog(delivered, prefs, shownIds);
          });
          return;
        }
      }

      // Priorité 3 : commandes PENDING → badge
      final pendingList = orders
          .where((o) => (o['status'] as String? ?? '').toUpperCase() == 'PENDING')
          .toList();

      if (mounted) {
        setState(() {
          _pendingOrders = pendingList;
          _loadingOrders = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  // ── Dialog commande livrée ─────────────────────────────────────────────────
  void _showDeliveredDialog(
    Map<String, dynamic> order,
    SharedPreferences prefs,
    List<String> shownIds,
  ) {
    final orderId  = order['id'] as String? ?? '';
    final price    = (order['price'] as num?)?.toInt() ?? 0;
    final delivery = order['deliveryAddress'] as String? ?? '—';

    // Persiste immédiatement l'ID pour ne plus jamais afficher ce dialog
    shownIds.add(orderId);
    prefs.setStringList(_kDeliveredKey, shownIds);

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
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
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
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
                      color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$price FCFA',
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
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Voir mes commandes',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: dismiss,
                  child: Text('Fermer',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.70))),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) => autoClose?.cancel());
  }

  // ── Affiche un sélecteur s'il y a plusieurs commandes en attente ─────────
  void _showPendingOrdersSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
             padding: const EdgeInsets.all(16),
             child: Column(
               mainAxisSize: MainAxisSize.min,
               crossAxisAlignment: CrossAxisAlignment.stretch,
               children: [
                 // Handle drag
                 Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(2)))),
                 const SizedBox(height: 20),
                 const Text('Vos commandes en attente', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                 const SizedBox(height: 16),
                 ..._pendingOrders.map((o) {
                    final type = o['orderType'] ?? o['type'] ?? '';
                    final price = (o['price'] as num?)?.toInt() ?? 0;
                    final pickup = o['pickupAddress'] as String? ?? 'Départ';
                    final delivery = o['deliveryAddress'] as String? ?? 'Arrivée';
                    return GestureDetector(
                       onTap: () {
                         Navigator.pop(ctx);
                         context.push('/orders/confirmation', extra: o);
                       },
                       child: Container(
                         margin: const EdgeInsets.only(bottom: 12),
                         padding: const EdgeInsets.all(16),
                         decoration: BoxDecoration(
                           color: AppColors.card,
                           borderRadius: BorderRadius.circular(16),
                           border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.3)),
                         ),
                         child: Row(
                           children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: const Color(0xFFFFB300).withValues(alpha: 0.15), shape: BoxShape.circle),
                                child: const Icon(Icons.timer, color: Color(0xFFFFB300), size: 22)
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(type == 'RIDE' ? 'Transport (Thiak Thiak)' : 'Livraison', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('$pickup  ➔  $delivery', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ]
                                )
                              ),
                              const SizedBox(width: 10),
                              Text('$price CFA', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary)),
                           ]
                         )
                       )
                    );
                 })
               ]
             )
          )
        );
      }
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
                if (!_programmaticMove && _locationMode != _LocationMode.free) {
                  _stopCompassMode();
                  setState(() => _locationMode = _LocationMode.free);
                }
                if ((pos.zoom - _currentZoom).abs() > 0.5) {
                  setState(() => _currentZoom = pos.zoom);
                }
              },
              onCameraIdle: () => _programmaticMove = false,
              markers: _clientMarkers,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
            ),
          ),

          // ── Dot overlay (follow/compass uniquement — free utilise un Marker) ──
          if (_clientPosition != null && _locationMode != _LocationMode.free)
            Center(
              child: _PulsingLocationDot(
                heading: _locationMode == _LocationMode.compass
                    ? _compassBearing
                    : (_travelHeading > 0 ? _travelHeading : null),
              ),
            ),

          // ── Header ──
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.go('/client/profile'),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
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
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // ── Bouton localisation 3 états (style Google Maps) ──
                      GestureDetector(
                        onTap: _cycleLocationMode,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: _locationMode == _LocationMode.free
                                ? AppColors.surface
                                : AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _locationMode == _LocationMode.free
                                  ? AppColors.card
                                  : AppColors.primary,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _locationMode == _LocationMode.free
                                    ? Colors.black.withValues(alpha: 0.25)
                                    : AppColors.primary.withValues(alpha: 0.45),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: _locationMode == _LocationMode.compass
                              ? Transform.rotate(
                                  angle: -_compassBearing * pi / 180,
                                  child: const Icon(Icons.navigation,
                                      color: Colors.white, size: 22),
                                )
                              : Icon(
                                  _locationMode == _LocationMode.follow
                                      ? Icons.navigation
                                      : Icons.navigation_outlined,
                                  color: _locationMode == _LocationMode.free
                                      ? AppColors.primary
                                      : Colors.white,
                                  size: 22,
                                ),
                        ),
                      ),

                      // Bouton toggle jour/nuit
                      GestureDetector(
                        onTap: _toggleMapTheme,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.card, width: 1.5),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12)],
                          ),
                          child: Icon(
                            ref.watch(mapNightProvider) ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                            color: ref.watch(mapNightProvider) ? const Color(0xFFFFB300) : AppColors.primary,
                            size: 22,
                          ),
                        ),
                      ),

                      // Badge Commandes en attente
                      if (_pendingOrders.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            if (_pendingOrders.length == 1) {
                              context.push('/orders/confirmation', extra: _pendingOrders.first);
                            } else {
                              _showPendingOrdersSelection();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB300),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFB300).withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _pendingOrders.length == 1 ? '1 commande en cours' : '${_pendingOrders.length} commandes en cours',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // ── Sheet rétractable ──
                _AnimatedSheet(
                  animation: _sheetSlide,
                  onToggle: _toggleSheet,
                  expanded: _sheetExpanded,
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
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '$greeting $firstName 👋',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        const Text(
          'Que voulez-vous faire ?',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _ServiceCard(
          icon: Icons.inventory_2_outlined,
          label: 'Livraison',
          subtitle: 'Envoyez ou recevez des colis',
          color: const Color(0xFF1A6B7A),
          onTap: () async {
            await context.push('/orders/create?type=DELIVERY');
            _checkPendingOrder();
          },
        ),
        /*const Text(
          'Livraison',
          style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _ServiceCard(
              icon: Icons.inventory_2_outlined,
              label: 'Colis',
              onTap: () async {
                await context.push('/orders/create?type=DELIVERY');
                _checkPendingOrder();
              },
            ),
            const SizedBox(width: 12),
            _ServiceCard(
              icon: Icons.restaurant_outlined,
              label: 'Repas',
              onTap: () async {
                await context.push('/orders/create?type=DELIVERY');
                _checkPendingOrder();
              },
            ),
            const SizedBox(width: 12),
            _ServiceCard(
              icon: Icons.more_horiz,
              label: 'Autre',
              onTap: () async {
                await context.push('/orders/create?type=DELIVERY');
                _checkPendingOrder();
              },
            ),
          ],
        ),*/
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

  const _AnimatedSheet({
    required this.animation,
    required this.child,
    required this.onToggle,
    required this.expanded,
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
          // ── Drag handle — tap pour rétracter/déployer ──
          GestureDetector(
            onTap: onToggle,
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
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Accueil',
              active: true,
              onTap: () {},
            ),
            _NavItem(
              icon: Icons.receipt_long_outlined,
              label: 'Commandes',
              active: false,
              onTap: () => context.push('/orders/my'),
            ),
            _NavItem(
              icon: Icons.person_outline_rounded,
              label: 'Profil',
              active: false,
              onTap: () => context.go('/client/profile'),
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
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: active ? AppColors.primary : AppColors.textSecondary,
              size: 26,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
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
                  Icon(Icons.navigation,
                      color: Colors.white,
                      size: 22,
                      shadows: [
                        Shadow(
                            color: cyan.withValues(alpha: 0.9),
                            blurRadius: 10)
                      ]),
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
                    spreadRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Text(subtitle!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                ],
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.65), size: 16),
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
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
