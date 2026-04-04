import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_theme.dart';
import '../../features/profile/providers/profile_provider.dart';

class HomeDriverThiakScreen extends ConsumerStatefulWidget {
  const HomeDriverThiakScreen({super.key});

  @override
  ConsumerState<HomeDriverThiakScreen> createState() => _HomeDriverThiakScreenState();
}

class _HomeDriverThiakScreenState extends ConsumerState<HomeDriverThiakScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).fetchProfile();
    });
  }

  Future<void> _toggleAvailability(bool val) async {
    try {
      await ref.read(profileProvider.notifier).toggleAvailability();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
                  // Toggle disponibilité (gauche)
                  GestureDetector(
                    onTap: () => _toggleAvailability(!isAvailable),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isAvailable ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 8,
                              color: isAvailable ? Colors.white : AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            isAvailable ? 'En ligne' : 'Hors ligne',
                            style: TextStyle(
                              color: isAvailable ? Colors.white : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
                  // Icône profil (droite)
                  GestureDetector(
                    onTap: () => context.push('/driver/profile'),
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                      ),
                      child: const Icon(Icons.person_outline, color: AppColors.textPrimary, size: 22),
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
                    profile.name.isNotEmpty ? 'Bonjour, ${profile.name} 👋' : 'Bonjour 👋',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAvailable
                        ? 'Vous êtes en ligne — en attente de courses'
                        : 'Activez votre disponibilité pour recevoir des courses',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
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
