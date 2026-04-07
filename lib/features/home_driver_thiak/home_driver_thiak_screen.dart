import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
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

  Future<void> _toggleAvailability(bool val) async {
    try {
      await ref.read(profileProvider.notifier).toggleAvailability();
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

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte Google Maps dark style Waze ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition:
                  const CameraPosition(target: _dakar, zoom: 14),
              onMapCreated: (controller) {
                _mapController = controller;
                if (_driverPosition != null) _centerOn(_driverPosition!);
              },
              onCameraMove: (_) {
                if (_autoFollow) setState(() => _autoFollow = false);
              },
              style: _mapStyle,
              markers: _driverMarkers,
              trafficEnabled: true,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _toggleAvailability(!isAvailable),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isAvailable
                            ? AppColors.primary
                            : Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8)
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.circle,
                              size: 8,
                              color: isAvailable
                                  ? Colors.white
                                  : AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            isAvailable ? 'En ligne' : 'Hors ligne',
                            style: TextStyle(
                              color: isAvailable
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch.adaptive(
                            value: isAvailable,
                            onChanged: _toggleAvailability,
                            activeThumbColor: Colors.white,
                            activeTrackColor:
                                Colors.white.withValues(alpha: 0.4),
                            inactiveThumbColor: AppColors.textSecondary,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/driver/profile'),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8)
                        ],
                      ),
                      child: const Icon(Icons.person_outline,
                          color: Colors.white, size: 22),
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
              bottom: 200,
              child: GestureDetector(
                onTap: _recenter,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2), width: 1),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 12)
                    ],
                  ),
                  child: const Icon(Icons.navigation,
                      color: Colors.white, size: 22),
                ),
              ),
            ),

          // ── Bottom sheet ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name.isNotEmpty
                        ? 'Bonjour, ${profile.name} 👋'
                        : 'Bonjour 👋',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAvailable
                        ? 'Vous êtes en ligne — en attente de courses'
                        : 'Activez votre disponibilité pour recevoir des courses',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _StatChip(
                          icon: Icons.route,
                          label: '0 courses',
                          color: AppColors.primary),
                      const SizedBox(width: 12),
                      _StatChip(
                          icon: Icons.star_outline,
                          label: '—',
                          color: AppColors.primaryMid),
                      const SizedBox(width: 12),
                      _StatChip(
                          icon: Icons.monetization_on_outlined,
                          label: '0 FCFA',
                          color: AppColors.primaryDark),
                    ],
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
