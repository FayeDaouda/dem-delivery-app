import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _clientIcon;

  // ── WebSocket ─────────────────────────────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _orderAcceptedSub;

  // ── GPS ──────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _clientPosition;
  bool _autoFollow = true;

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
    _buildClientIcon().then((icon) {
      if (mounted) setState(() => _clientIcon = icon);
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

  // ── Marqueur client (point cyan + halo) ───────────────────────────────────
  static Future<BitmapDescriptor> _buildClientIcon() async {
    const double size = 96;
    const double cx = size / 2;
    const double cy = size / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Halo semi-transparent
    canvas.drawCircle(
      const Offset(cx, cy),
      38,
      Paint()..color = const Color(0x4033BCD4),
    );
    // Point plein
    canvas.drawCircle(
      const Offset(cx, cy),
      14,
      Paint()..color = const Color(0xFF33BCD4),
    );
    // Bordure blanche
    canvas.drawCircle(
      const Offset(cx, cy),
      14,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: size / 2,
      height: size / 2,
    );
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> _startGPS() async {
    final initial = await NavigationService.requestAndGetPosition();
    if (initial != null && mounted) {
      setState(() => _clientPosition = initial);
      _centerOn(initial);
    }
    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _clientPosition = position);
    if (_autoFollow) _centerOn(position);
  }

  void _centerOn(Position position) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 17,
          bearing: 0,
          tilt: 55,
        ),
      ),
    );
  }

  void _recenter() {
    if (_clientPosition == null) return;
    setState(() => _autoFollow = true);
    _centerOn(_clientPosition!);
  }

  // ── Marqueur client ───────────────────────────────────────────────────────
  Set<Marker> get _clientMarkers {
    if (_clientPosition == null) return {};
    return {
      Marker(
        markerId: const MarkerId('client'),
        position: LatLng(_clientPosition!.latitude, _clientPosition!.longitude),
        icon: _clientIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
      ),
    };
  }

  // ── User ──────────────────────────────────────────────────────────────────
  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _user = user);
  }

  // ── Vérifie si une commande PENDING existe ─────────────────────────────────
  Future<void> _checkPendingOrder() async {
    if (!mounted) return;
    setState(() => _loadingOrders = true);
    try {
      final orders = await ref.read(ordersRepositoryProvider).getMyOrders();
      final pendingList = orders.where((o) => o['status'] == 'PENDING').toList();
      
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
                zoom: 17,
                tilt: 55,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_clientPosition != null) _centerOn(_clientPosition!);
              },
              style: _mapStyle,
              onCameraMove: (_) {
                if (_autoFollow) setState(() => _autoFollow = false);
              },
              markers: _clientMarkers,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
            ),
          ),

          // ── Header ──
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _user?['name'] ?? 'Mon compte',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      // Bouton re-centrer
                      if (!_autoFollow)
                        GestureDetector(
                          onTap: _recenter,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.card, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
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
                        )
                      else
                        const SizedBox(width: 52),

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
          icon: Icons.bike_scooter_outlined,
          label: 'Transport',
          subtitle: 'Thiak Thiak',
          color: const Color(0xFF1A6B7A),
          onTap: () async {
            await context.push('/orders/create?type=RIDE');
            _checkPendingOrder();
          },
        ),
        const SizedBox(height: 16),
        _ServiceCard(
          icon: Icons.inventory_2_outlined,
          label: 'Coursier',
          subtitle: 'Colis',
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
