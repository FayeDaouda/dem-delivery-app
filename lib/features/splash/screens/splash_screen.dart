import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_repository.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late final AnimationController _logoCtrl;
  late final AnimationController _taglineCtrl;
  late final AnimationController _loaderCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _loaderOpacity;

  @override
  void initState() {
    super.initState();

    // Logo : scale élastique + fade — 800ms
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.45, curve: Curves.easeIn)),
    );

    // Tagline : slide-up + fade — 500ms
    _taglineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOut),
    );
    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOutCubic),
    );

    // Loader : fade in discret — 400ms
    _loaderCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _loaderOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _loaderCtrl, curve: Curves.easeIn),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // 1. Logo pop élastique
    await _logoCtrl.forward();
    // 2. Tagline slide-up + fade
    await _taglineCtrl.forward();
    // 3. Courte pause puis loader visible pendant l'appel réseau
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _loaderCtrl.forward();

    // 4. Résolution de la navigation (appel API)
    final destination = await _resolveDestination();
    if (!mounted) return;

    // 5. Navigation directe — pas de fade-out pour éviter l'écran noir
    context.go(destination);
  }

  Future<String> _resolveDestination() async {
    final isLoggedIn = await AuthStorage.isLoggedIn();
    if (!isLoggedIn) {
      final seen = await AuthStorage.isOnboardingSeen();
      return seen ? '/phone' : '/onboarding';
    }

    Map<String, dynamic>? user;
    try {
      user = await ProfileRepository().getMe().timeout(const Duration(seconds: 8));
    } catch (_) {
      user = await AuthStorage.getUser();
    }

    final role        = user?['role'] as String?;
    final vehicleType = user?['vehicleType'] as String?;
    final isActive    = user?['isActive'] as bool? ?? true;

    if (role == 'DRIVER') {
      if (!isActive) return '/driver/suspended';
      if (vehicleType == 'TAXI') return '/driver/thiak/home';
      return '/driver/home';
    }
    if (role == 'CLIENT') return '/client/home';
    if (role == 'CHEF_DE_FLOTTE') {
      if (!isActive) return '/chef-de-flotte/suspended';
      final status = user?['chefDeFlotteStatus'] as String?;
      if (status == 'ACTIVE')   return '/chef-de-flotte/dashboard';
      if (status == 'PENDING')  return '/chef-de-flotte/pending';
      if (status == 'REJECTED') return '/chef-de-flotte/rejected';
      return '/chef-de-flotte/onboarding';
    }
    return '/phone';
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _taglineCtrl.dispose();
    _loaderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              // ── Logo ──
              AnimatedBuilder(
                animation: _logoCtrl,
                builder: (_, _) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Image.asset('assets/DEM.png', width: 140, height: 140),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Tagline slide-up ──
              AnimatedBuilder(
                animation: _taglineCtrl,
                builder: (_, child) => FadeTransition(
                  opacity: _taglineOpacity,
                  child: SlideTransition(position: _taglineSlide, child: child),
                ),
                child: const Text(
                  'DELIVERY · EXPRESS · MOBILITY',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 3,
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // ── Loader discret — visible pendant l'appel réseau ──
              AnimatedBuilder(
                animation: _loaderCtrl,
                builder: (_, _) => Opacity(
                  opacity: _loaderOpacity.value,
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.50),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
