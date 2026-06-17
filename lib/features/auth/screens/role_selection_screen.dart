import '../../../core/error/app_exception.dart';
import '../../../core/utils/dem_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../dem_pro/theme/dem_pro_colors.dart';
import '../providers/auth_provider.dart';

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // 4 animations décalées : slide up + fade
  late final List<Animation<double>>  _fades;
  late final List<Animation<Offset>>  _slides;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Chaque carte démarre 100ms après la précédente
    _fades = List.generate(4, (i) {
      final start = 0.08 + i * 0.15;
      return CurvedAnimation(
        parent: _ctrl,
        curve: Interval(start, (start + 0.40).clamp(0.0, 1.0), curve: Curves.easeOut),
      );
    });

    _slides = List.generate(4, (i) {
      final start = 0.08 + i * 0.15;
      return Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, (start + 0.40).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
        ),
      );
    });

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _select(String role, {String? vehicleType}) async {
    try {
      await ref.read(authProvider.notifier).setupProfile(role: role, vehicleType: vehicleType);
      if (!mounted) return;
      // Notifie le router que le rôle est maintenant connu
      appStartupNotifier.markLoggedIn(
        userRole: role,
        vehicle: vehicleType,
        pro: role == 'DEM_PRO' ? 'PENDING' : null,
      );
      if (role == 'DRIVER') {
        context.go('/driver/onboarding?type=$vehicleType');
      } else if (role == 'CHEF_DE_FLOTTE') {
        context.go('/chef-de-flotte/onboarding');
      } else if (role == 'DEM_PRO') {
        context.go('/dem-pro/onboarding');
      } else {
        context.go('/client/onboarding');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authProvider).isLoading;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: DemLayout.formMaxWidth(context)),
          child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/phone'),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Builder(builder: (ctx) {
                          final t = MediaQuery.of(ctx).size.width > 600;
                          return Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(t ? 22 : 16),
                              child: Image.asset('assets/DEM.png', width: t ? 96.0 : 72.0, height: t ? 96.0 : 72.0),
                            ),
                          );
                        }),
                    ],
                  ),
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
                    Builder(builder: (ctx) {
                      final t = MediaQuery.of(ctx).size.width > 600;
                      return Text(
                        'Je suis …',
                        style: TextStyle(
                          color: AppColors.textPrimary, fontSize: t ? 30.0 : 26.0, fontWeight: FontWeight.w800,
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    const Text(
                      'Choisissez votre profil pour continuer',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // ── Cartes animées ──
                    _AnimatedCard(
                      fade: _fades[0], slide: _slides[0],
                      child: _RoleCard(
                        icon: Icons.shopping_bag_outlined,
                        title: 'Client',
                        subtitle: 'Je veux envoyer des colis ou me faire livrer',
                        color: AppColors.primary,
                        loading: loading,
                        onTap: () => _select('CLIENT'),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _AnimatedCard(
                      fade: _fades[1], slide: _slides[1],
                      child: _RoleCard(
                        icon: Icons.motorcycle,
                        title: 'Livreur — DEM',
                        subtitle: 'Je récupère et livre des colis à moto.',
                        color: AppColors.primaryMid,
                        loading: loading,
                        onTap: () => _select('DRIVER', vehicleType: 'MOTO'),
                      ),
                    ),
                    const SizedBox(height: 32),

                    _AnimatedCard(
                      fade: _fades[2], slide: _slides[2],
                      child: _RoleCard(
                        icon: Icons.handshake_outlined,
                        title: 'Chef de flotte - DEM',
                        subtitle: 'Je recrute et gère une flotte de livreurs',
                        color: const Color(0xFF7C3AED),
                        loading: loading,
                        onTap: () => _select('CHEF_DE_FLOTTE'),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _AnimatedCard(
                      fade: _fades[3], slide: _slides[3],
                      child: _RoleCard(
                        icon: Icons.storefront_outlined,
                        title: 'DEM Pro',
                        subtitle: 'Je gère des livraisons pour mon business',
                        color: DemProColors.accent,
                        loading: loading,
                        onTap: () => _select('DEM_PRO'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
        ),          // ConstrainedBox
      ),            // Center
    );
  }
}

// ── Wrapper animation ─────────────────────────────────────────────────────────
class _AnimatedCard extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset> slide;
  final Widget child;

  const _AnimatedCard({required this.fade, required this.slide, required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

// ── Carte rôle ────────────────────────────────────────────────────────────────
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
    final isTablet   = MediaQuery.of(context).size.width > 600;
    final iconBox    = isTablet ? 64.0 : 52.0;
    final iconSize   = isTablet ? 32.0 : 26.0;
    final titleFS    = isTablet ? 17.0 : 15.0;

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
              width: iconBox, height: iconBox,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
              ),
              child: Icon(icon, color: color, size: iconSize),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary, fontSize: titleFS, fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, color: color, size: isTablet ? 18 : 16),
          ],
        ),
      ),
    );
  }
}
