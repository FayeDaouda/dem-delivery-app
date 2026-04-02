import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/api/api_client.dart';

class HomeDriverThiakScreen extends StatefulWidget {
  const HomeDriverThiakScreen({super.key});

  @override
  State<HomeDriverThiakScreen> createState() => _HomeDriverThiakScreenState();
}

class _HomeDriverThiakScreenState extends State<HomeDriverThiakScreen> {
  bool _isAvailable = false;
  String? _driverName;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) {
      setState(() => _driverName = user?['name'] as String?);
    }
  }

  Future<void> _toggleAvailability(bool val) async {
    try {
      await ApiClient.dio.patch('/users/driver/availability');
      if (mounted) setState(() => _isAvailable = val);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Carte OpenStreetMap ──
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(14.6937, -17.4441),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.dem.app',
              ),
            ],
          ),

          // ── Header ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Badge Thiak Thiak
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.directions_car, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text('Thiak Thiak', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Toggle disponibilité
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isAvailable ? AppColors.primary : AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _isAvailable ? 'En ligne' : 'Hors ligne',
                          style: TextStyle(
                            color: _isAvailable ? Colors.white : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch.adaptive(
                          value: _isAvailable,
                          onChanged: _toggleAvailability,
                          activeThumbColor: Colors.white,
                          activeTrackColor: AppColors.primaryMid,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ],
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
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _driverName != null ? 'Bonjour, $_driverName 👋' : 'Bonjour 👋',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isAvailable
                        ? 'Vous êtes en ligne — en attente de courses'
                        : 'Activez votre disponibilité pour recevoir des courses',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  // Stats rapides
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
  const _StatChip({required this.icon, required this.label, required this.color});

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
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
