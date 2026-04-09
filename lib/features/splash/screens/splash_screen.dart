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

  late final AnimationController _logoController;
  late final AnimationController _taglineController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();

    // Logo : scale + fade — 800ms
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Tagline : fade — 600ms
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineController, curve: Curves.easeIn),
    );

    _runAnimations();
  }

  Future<void> _runAnimations() async {
    await _logoController.forward();
    await _taglineController.forward();
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _navigate();
  }

  Future<void> _navigate() async {
    final isLoggedIn = await AuthStorage.isLoggedIn();
    if (!mounted) return;

    if (!isLoggedIn) {
      context.go('/phone');
      return;
    }

    // Récupère les données fraîches depuis l'API (évite le cache obsolète)
    Map<String, dynamic>? user;
    try {
      user = await ProfileRepository().getMe();
    } catch (_) {
      // fallback sur le cache local si l'API échoue
      user = await AuthStorage.getUser();
    }

    if (!mounted) return;
    final role = user?['role'] as String?;
    final vehicleType = user?['vehicleType'] as String?;
    if (role == 'DRIVER' && vehicleType == 'TAXI') {
      context.go('/driver/thiak/home');
    } else if (role == 'DRIVER') {
      context.go('/driver/home');
    } else {
      context.go('/client/home');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _taglineController.dispose();
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
              // Logo DEM animé
              AnimatedBuilder(
                animation: _logoController,
                builder: (context, child) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Image.asset(
                      'assets/DEM.png',
                      width: 140,
                      height: 140,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Tagline fade in
              AnimatedBuilder(
                animation: _taglineController,
                builder: (context, child) => Opacity(
                  opacity: _taglineOpacity.value,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
