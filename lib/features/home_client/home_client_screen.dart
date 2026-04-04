import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';

// Centre par défaut : Dakar
const _dakar = LatLng(14.6937, -17.4441);

class HomeClientScreen extends StatefulWidget {
  const HomeClientScreen({super.key});

  @override
  State<HomeClientScreen> createState() => _HomeClientScreenState();
}

class _HomeClientScreenState extends State<HomeClientScreen> {
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _user = user);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Carte plein écran
          FlutterMap(
            options: const MapOptions(initialCenter: _dakar, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.dem.app',
              ),
            ],
          ),

          // Header avec nom utilisateur
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha:0.95),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _user?['name'] ?? 'Mon compte',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      final router = GoRouter.of(context);
                      await AuthStorage.clear();
                      router.go('/phone');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha:0.95),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.logout, color: AppColors.textSecondary, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom sheet — Choix du service
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.4), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Que voulez-vous envoyer ?',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _ServiceCard(
                        icon: Icons.inventory_2_outlined,
                        label: 'Colis',
                        onTap: () => context.push('/orders/create'),
                      ),
                      const SizedBox(width: 12),
                      _ServiceCard(
                        icon: Icons.restaurant_outlined,
                        label: 'Repas',
                        onTap: () => context.push('/orders/create'),
                      ),
                      const SizedBox(width: 12),
                      _ServiceCard(
                        icon: Icons.more_horiz,
                        label: 'Autre',
                        onTap: () => context.push('/orders/create'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/orders/create'),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Nouvelle livraison'),
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

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ServiceCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
              Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
