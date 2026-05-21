import 'package:flutter/material.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';

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

  // Logo
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoOffsetY;

  // Tagline
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _taglineScale;
  late final Animation<double> _taglineOffsetY;
  late final Animation<double> _letterSpacing;

  // Loader
  late final Animation<double> _loaderOpacity;

  @override
  void initState() {
    super.initState();

    // ── Logo (700ms) — easeOutBack donne un léger rebond élastique ───────────
    _logoCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

    _logoScale = Tween<double>(begin: 0.60, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.50, curve: Curves.easeIn)),
    );
    _logoOffsetY = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic),
    );

    // ── Tagline (600ms) — lettrines qui se resserrent (effet cinématique) ────
    _taglineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOut),
    );
    _taglineScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOutCubic),
    );
    _taglineOffsetY = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOutCubic),
    );
    // Les lettres se resserrent progressivement → effet signature
    _letterSpacing = Tween<double>(begin: 9.0, end: 3.5).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOutCubic),
    );

    // ── Loader ────────────────────────────────────────────────────────────────
    _loaderCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _loaderOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _loaderCtrl, curve: Curves.easeIn),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    await _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 120));
    await _taglineCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    _loaderCtrl.forward();
    await appStartupNotifier.initialize();
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

              // ── Logo arrondi + ombre animée ──
              AnimatedBuilder(
                animation: _logoCtrl,
                builder: (_, _) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.translate(
                    offset: Offset(0, _logoOffsetY.value),
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.30 * _logoOpacity.value),
                              blurRadius: 48,
                              spreadRadius: 4,
                              offset: const Offset(0, 14),
                            ),
                            BoxShadow(
                              color: const Color(0xFF00C8FF).withValues(alpha: 0.20 * _logoOpacity.value),
                              blurRadius: 70,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: Image.asset('assets/DEM.png', width: 118, height: 118),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Tagline avec lettrines qui se resserrent ──
              AnimatedBuilder(
                animation: _taglineCtrl,
                builder: (_, _) => Opacity(
                  opacity: _taglineOpacity.value,
                  child: Transform.translate(
                    offset: Offset(0, _taglineOffsetY.value),
                    child: Transform.scale(
                      scale: _taglineScale.value,
                      child: Text(
                        'DELIVERY · EXPRESS · MOBILITY',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: _letterSpacing.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 56),

              // ── Loader ──
              AnimatedBuilder(
                animation: _loaderCtrl,
                builder: (_, _) => Opacity(
                  opacity: _loaderOpacity.value,
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.45),
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
