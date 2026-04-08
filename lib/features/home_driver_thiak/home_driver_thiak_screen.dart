import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../features/deliveries/providers/orders_provider.dart';
import '../../features/profile/providers/profile_provider.dart';
import '../home_driver/navigation/map_theme.dart';
import '../home_driver/navigation/navigation_service.dart';

const _dakar = LatLng(14.6937, -17.4441);

class HomeDriverThiakScreen extends ConsumerStatefulWidget {
  const HomeDriverThiakScreen({super.key});

  @override
  ConsumerState<HomeDriverThiakScreen> createState() =>
      _HomeDriverThiakScreenState();
}

class _HomeDriverThiakScreenState
    extends ConsumerState<HomeDriverThiakScreen> {
  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _driverIcon;

  // ── GPS ──────────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  Position? _driverPosition;
  bool _autoFollow = true;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _buildDriverIcon().then((icon) {
      if (mounted) setState(() => _driverIcon = icon);
    });
    _startGPS();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).fetchProfile(goOnlineIfOffline: true);
    });
  }

  static Future<BitmapDescriptor> _buildDriverIcon() async {
    const double size = 96;
    const double cx = size / 2;
    const double cy = size / 2;
    const double haloR = 40;
    const double arrowR = 18;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      const Offset(cx, cy),
      haloR,
      Paint()..color = const Color(0x4033BCD4),
    );

    final path = Path()
      ..moveTo(cx, cy - arrowR)
      ..lineTo(cx + arrowR * 0.8, cy + arrowR * 0.6)
      ..lineTo(cx - arrowR * 0.8, cy + arrowR * 0.6)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF33BCD4));

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: size / 2,
      height: size / 2,
    );
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString(MapTheme.styleAsset);
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _startGPS() async {
    final initial = await NavigationService.requestAndGetPosition();
    if (initial != null && mounted) {
      setState(() => _driverPosition = initial);
      _centerOn(initial);
    }
    _locationSub = NavigationService.positionStream.listen(_onPosition);
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _driverPosition = position);
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
    if (_driverPosition == null) return;
    setState(() => _autoFollow = true);
    _centerOn(_driverPosition!);
  }

  Set<Marker> get _driverMarkers {
    if (_driverPosition == null) return {};
    return {
      Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(_driverPosition!.latitude, _driverPosition!.longitude),
        icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        flat: true,
        rotation: _driverPosition!.heading,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
      ),
    };
  }

  // ── Countdown ─────────────────────────────────────────────────────────────
  int _countdown = 20;
  Timer? _countdownTimer;

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 20);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    if (mounted) setState(() => _countdown = 20);
  }

  Future<void> _toggleAvailability(bool val) async {
    try {
      await ref.read(profileProvider.notifier).toggleAvailability();
      final isAvailable = ref.read(profileProvider).isAvailable;
      if (isAvailable) ref.read(availableOrdersProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      _cancelCountdown();
      final order = await ref.read(ordersRepositoryProvider).acceptOrder(orderId);
      if (mounted) context.push('/driver/order/active', extra: order);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final isAvailable = profile.isAvailable;
    final ordersAsync = ref.watch(availableOrdersProvider);
    final orders = ordersAsync.value ?? [];

    // Auto-online → charge les commandes
    ref.listen<ProfileState>(profileProvider, (prev, next) {
      if (!(prev?.isAvailable ?? false) && next.isAvailable) {
        ref.read(availableOrdersProvider.notifier).refresh();
      }
    });

    // Nouvelle course → countdown
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
      availableOrdersProvider,
      (prev, next) {
        final prevList = prev?.value ?? [];
        final nextList = next.value ?? [];
        if (nextList.isNotEmpty && prevList.isEmpty && isAvailable) {
          _startCountdown();
        } else if (nextList.isEmpty) {
          _cancelCountdown();
        }
      },
    );

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(target: _dakar, zoom: 14),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_driverPosition != null) _centerOn(_driverPosition!);
              },
              onCameraMove: (_) {
                if (_autoFollow) setState(() => _autoFollow = false);
              },
              style: _mapStyle,
              markers: _driverMarkers,
              trafficEnabled: isAvailable && orders.isNotEmpty,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Header ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: profile.isLoading ? null : () => _toggleAvailability(!isAvailable),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isAvailable ? AppColors.primary : Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 8,
                              color: isAvailable ? Colors.white : AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(isAvailable ? 'En ligne' : 'Hors ligne',
                              style: TextStyle(
                                  color: isAvailable ? Colors.white : AppColors.textSecondary,
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Switch.adaptive(
                            value: isAvailable,
                            onChanged: _toggleAvailability,
                            activeThumbColor: Colors.white,
                            activeTrackColor: Colors.white.withValues(alpha: 0.4),
                            inactiveThumbColor: AppColors.textSecondary,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/driver/profile'),
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
                      ),
                      child: const Icon(Icons.person_outline, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bouton re-centrer ──
          if (!_autoFollow)
            Positioned(
              left: 16,
              bottom: 220,
              child: GestureDetector(
                onTap: _recenter,
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                  child: const Icon(Icons.my_location, color: AppColors.primary, size: 22),
                ),
              ),
            ),

          // ── Bottom sheet — 2 états ──
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: isAvailable && orders.isNotEmpty
                  ? _ThiakOrderSheet(
                      key: const ValueKey('order'),
                      order: orders.first,
                      countdown: _countdown,
                      onAccept: () => _acceptOrder(orders.first['id']),
                      onDecline: () {
                        _cancelCountdown();
                        ref.read(availableOrdersProvider.notifier).refresh();
                      },
                    )
                  : _ThiakNormalSheet(
                      key: const ValueKey('normal'),
                      profile: profile,
                      isAvailable: isAvailable,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sheet normal Thiak Thiak ──────────────────────────────────────────────────
class _ThiakNormalSheet extends StatelessWidget {
  final dynamic profile;
  final bool isAvailable;

  const _ThiakNormalSheet({super.key, required this.profile, required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.80),
                Colors.white.withValues(alpha: 0.70),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.50), width: 0.8),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 32, offset: const Offset(0, -4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                profile.name.isNotEmpty ? 'Bonjour, ${profile.name} 👋' : 'Bonjour 👋',
                style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                isAvailable ? 'En attente de courses...' : 'Activez pour recevoir des courses',
                style: TextStyle(color: const Color(0xFF1A1A2E).withValues(alpha: 0.55), fontSize: 13),
              ),
              if (isAvailable) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    _StatChip(icon: Icons.route, label: '0 courses', color: AppColors.primary),
                    const SizedBox(width: 12),
                    _StatChip(icon: Icons.star_outline, label: '—', color: AppColors.primaryMid),
                    const SizedBox(width: 12),
                    _StatChip(icon: Icons.monetization_on_outlined, label: '0 FCFA', color: AppColors.primaryDark),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sheet nouvelle course Thiak Thiak ────────────────────────────────────────
class _ThiakOrderSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final int countdown;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _ThiakOrderSheet({
    super.key,
    required this.order,
    required this.countdown,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final pickup = order['pickupAddress'] ?? '';
    final delivery = order['deliveryAddress'] ?? '';

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: 0.80), Colors.white.withValues(alpha: 0.70)],
            ),
            border: const Border(
              top: BorderSide(color: AppColors.primary, width: 2),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 32, offset: const Offset(0, -4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              )),
              Row(
                children: [
                  const Icon(Icons.delivery_dining, color: AppColors.primary, size: 26),
                  const SizedBox(width: 10),
                  const Text('Nouvelle course', style: TextStyle(color: Color(0xFF1A1A2E), fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  SizedBox(
                    width: 44, height: 44,
                    child: Stack(alignment: Alignment.center, children: [
                      CircularProgressIndicator(
                        value: countdown / 20, strokeWidth: 3,
                        backgroundColor: Colors.black12,
                        color: countdown > 8 ? AppColors.primary : Colors.orange,
                      ),
                      Text('$countdown', style: TextStyle(
                          color: countdown > 8 ? AppColors.primary : Colors.orange,
                          fontSize: 13, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.circle, color: Color(0xFF4CAF50), size: 12),
                const SizedBox(width: 8),
                Expanded(child: Text(pickup, style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.location_on, color: AppColors.primary, size: 12),
                const SizedBox(width: 8),
                Expanded(child: Text(delivery, style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Text('$price FCFA', textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: onDecline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black12, width: 1.5), borderRadius: BorderRadius.circular(14)),
                    child: const Text('Refuser', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: GestureDetector(
                  onTap: onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
                    child: const Text('Accepter', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
