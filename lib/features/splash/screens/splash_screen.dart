import 'package:flutter/material.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';

/// Écran de démarrage : affiche l'animation DEM pendant que
/// [appStartupNotifier.initialize()] charge l'état.
/// Dès que [isReady] est true, GoRouter.redirect prend le relais.
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
  late final Animation<Offset>  _taglineSlide;
  late final Animation<double> _loaderOpacity;

  @override
  void initState() {
    super.initState();

    // ── Animations ──────────────────────────────────────────────────────────
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _logoScale   = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.45, curve: Curves.easeIn)));

    _taglineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOut));
    _taglineSlide   = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOutCubic));

    _loaderCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _loaderOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _loaderCtrl, curve: Curves.easeIn));

    _runSequence();
  }

  Future<void> _runSequence() async {
    // 1. Animation d'entrée
    await _logoCtrl.forward();
    await _taglineCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _loaderCtrl.forward();

    // 2. Chargement de l'état (await complet — pas de saut possible)
    //    GoRouter.redirect prend le relais dès que isReady == true.
    await appStartupNotifier.initialize();
    // GoRouter reçoit notifyListeners() → redirect se déclenche automatiquement.
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

              // ── Tagline ──
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

              // ── Loader (visible pendant initialize()) ──
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
