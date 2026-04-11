import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _select(BuildContext context, WidgetRef ref, String role, {String? vehicleType}) async {
    try {
      await ref.read(authProvider.notifier).setupProfile(role: role, vehicleType: vehicleType);
      if (!context.mounted) return;
      if (role == 'DRIVER') {
        context.go('/driver/onboarding?type=$vehicleType');
      } else {
        context.go('/client/home');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(authProvider).isLoading;

    return Scaffold(
      body: Column(
        children: [
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
                    const Text('Qui êtes-vous ?',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('Choisissez votre profil pour continuer',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    const SizedBox(height: 32),
                    _RoleCard(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Client',
                      subtitle: 'Je veux envoyer des colis ou me faire livrer',
                      color: AppColors.primary,
                      loading: loading,
                      onTap: () => _select(context, ref, 'CLIENT'),
                    ),
                    const SizedBox(height: 16),
                    _RoleCard(
                      icon: Icons.motorcycle,
                      title: 'Livreur — DEM Livraison',
                      subtitle: 'Je livre des colis à moto dans la ville',
                      color: AppColors.primaryMid,
                      loading: loading,
                      onTap: () => _select(context, ref, 'DRIVER', vehicleType: 'MOTO'),
                    ),
                    const SizedBox(height: 16),
                    _RoleCard(
                      icon: Icons.directions_car_outlined,
                      title: 'Chauffeur — Thiak Thiak',
                      subtitle: 'Je transporte des passagers en taxi / clando',
                      color: AppColors.primaryDark,
                      loading: loading,
                      onTap: () => _select(context, ref, 'DRIVER', vehicleType: 'TAXI'),
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
              width: 52, height: 52,
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
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
