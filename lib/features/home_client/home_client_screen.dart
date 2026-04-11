import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
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
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _pendingOrder;
  bool _loadingOrders = false;
  bool _cancelling = false;

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _clientIcon;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingOrder());
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _mapController?.dispose();
    _sheetAnim.dispose();
    super.dispose();
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
    final style = await rootBundle.loadString(MapTheme.styleAsset);
    if (mounted) setState(() => _mapStyle = style);
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
          zoom: 15.5,
          bearing: 0,
          tilt: 0,
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
      final pending = orders.firstWhere(
        (o) => o['status'] == 'PENDING',
        orElse: () => {},
      );
      if (mounted) {
        setState(() {
          _pendingOrder = pending.isNotEmpty ? pending : null;
          _loadingOrders = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  // ── Annule la commande en attente ──────────────────────────────────────────
  Future<void> _cancelPendingOrder() async {
    final orderId = _pendingOrder?['id'] as String?;
    if (orderId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Annuler la commande ?',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Voulez-vous vraiment annuler cette commande en attente ?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Oui, annuler',
              style: TextStyle(
                  color: Color(0xFFFF5252), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(ordersRepositoryProvider).cancelOrder(orderId);
      if (mounted) {
        setState(() {
          _pendingOrder = null;
          _cancelling = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commande annulée avec succès'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte plein écran Google Maps style Waze ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _dakar,
                zoom: 14,
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
            ),
          ),

          // ── Bouton re-centrer ──
          if (!_autoFollow)
            Positioned(
              left: 16,
              bottom: _navBarHeight + 80,
              child: GestureDetector(
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
                      color: AppColors.surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: AppColors.primary, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _user?['name'] ?? 'Mon compte',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
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
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.95),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person,
                          color: AppColors.primary, size: 20),
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
              children: [
                // ── Sheet rétractable ──
                _AnimatedSheet(
                  animation: _sheetSlide,
                  onToggle: _toggleSheet,
                  expanded: _sheetExpanded,
                  isPending: _pendingOrder != null && !_loadingOrders,
                  child: _loadingOrders
                      ? _buildLoadingContent()
                      : _pendingOrder != null
                          ? _PendingOrderSheetContent(
                              order: _pendingOrder!,
                              cancelling: _cancelling,
                              onCancel: _cancelPendingOrder,
                            )
                          : _buildServiceContent(),
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

  // ── Contenu chargement ─────────────────────────────────────────────────────
  Widget _buildLoadingContent() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }

  // ── Contenu choix du service ───────────────────────────────────────────────
  Widget _buildServiceContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Que voulez-vous faire ?',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _ServiceCard(
          icon: Icons.directions_car_outlined,
          label: 'Transport',
          subtitle: 'Thiak Thiak',
          color: const Color(0xFF1A6B7A),
          onTap: () => context.push('/orders/create?type=RIDE'),
        ),
        const SizedBox(height: 10),
        const Text(
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
              onTap: () => context.push('/orders/create?type=DELIVERY'),
            ),
            const SizedBox(width: 12),
            _ServiceCard(
              icon: Icons.restaurant_outlined,
              label: 'Repas',
              onTap: () => context.push('/orders/create?type=DELIVERY'),
            ),
            const SizedBox(width: 12),
            _ServiceCard(
              icon: Icons.more_horiz,
              label: 'Autre',
              onTap: () => context.push('/orders/create?type=DELIVERY'),
            ),
          ],
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
  final bool isPending;

  const _AnimatedSheet({
    required this.animation,
    required this.child,
    required this.onToggle,
    required this.expanded,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isPending ? const Color(0xFFFFB300) : Colors.transparent;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: borderColor, width: 2)),
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
                      color: AppColors.card,
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

// ── Contenu sheet commande en attente ─────────────────────────────────────────
class _PendingOrderSheetContent extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool cancelling;
  final VoidCallback onCancel;

  const _PendingOrderSheetContent({
    required this.order,
    required this.cancelling,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final type = order['type'] as String? ?? '';
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final pickup = order['pickupAddress'] as String? ?? '—';
    final delivery = order['deliveryAddress'] as String? ?? '—';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.access_time_rounded,
                  color: Color(0xFFFFB300), size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Commande en attente',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  _typeLabel(type),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '$price FCFA',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Adresses ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _AddressRow(
                  icon: Icons.circle,
                  color: const Color(0xFF4CAF50),
                  label: 'Récupération',
                  address: pickup),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                    width: 1.5,
                    height: 12,
                    color: AppColors.textSecondary.withValues(alpha: 0.3)),
              ),
              _AddressRow(
                  icon: Icons.location_on,
                  color: AppColors.primary,
                  label: 'Destination',
                  address: delivery),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Bouton annuler ──
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: cancelling ? null : onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.5),
                    width: 1.5),
              ),
              child: cancelling
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFFF5252)),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cancel_outlined,
                            color: Color(0xFFFF5252), size: 18),
                        SizedBox(width: 8),
                        Text('Annuler la commande',
                            style: TextStyle(
                                color: Color(0xFFFF5252),
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  String _typeLabel(String type) => switch (type) {
        'RIDE' => 'Thiak Thiak',
        'DELIVERY' => 'Livraison',
        _ => type,
      };
}

// ── Ligne adresse ─────────────────────────────────────────────────────────────
class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String address;

  const _AddressRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
              Text(address,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
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
    final accent = color ?? AppColors.primary;

    if (subtitle != null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 32),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: accent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Text(subtitle!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios, color: accent, size: 16),
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
