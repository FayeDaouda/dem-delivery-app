import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import 'auth_service.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _loading = false;

  Future<void> _select(String role, {String? vehicleType}) async {
    setState(() => _loading = true);
    try {
      await AuthService.setupProfile(role: role, vehicleType: vehicleType);
      if (!mounted) return;

      if (role == 'DRIVER') {
        // Driver → onboarding pour compléter le profil (nom + plaque)
        context.go('/driver/onboarding?type=$vehicleType');
      } else {
        context.go('/client/home');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Une erreur est survenue. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Header gradient ──
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Image.asset('assets/DEM.png', width: 72, height: 72),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),

          // ── Carte ──
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Qui êtes-vous ?',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Choisissez votre profil pour continuer',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // CLIENT
                    _RoleCard(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Client',
                      subtitle: 'Je veux envoyer des colis ou me faire livrer',
                      color: AppColors.primary,
                      loading: _loading,
                      onTap: () => _select('CLIENT'),
                    ),
                    const SizedBox(height: 16),

                    // DRIVER LIVRAISON
                    _RoleCard(
                      icon: Icons.motorcycle,
                      title: 'Livreur — DEM Livraison',
                      subtitle: 'Je livre des colis à moto dans la ville',
                      color: AppColors.primaryMid,
                      loading: _loading,
                      onTap: () => _select('DRIVER', vehicleType: 'MOTO'),
                    ),
                    const SizedBox(height: 16),

                    // DRIVER THIAK THIAK
                    _RoleCard(
                      icon: Icons.directions_car_outlined,
                      title: 'Chauffeur — Thiak Thiak',
                      subtitle: 'Je transporte des passagers en taxi / clando',
                      color: AppColors.primaryDark,
                      loading: _loading,
                      onTap: () => _select('DRIVER', vehicleType: 'TAXI'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}
