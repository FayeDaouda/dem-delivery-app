import 'package:go_router/go_router.dart';
import '../../features/auth/phone_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/role_selection_screen.dart';
import '../../features/auth/driver_onboarding_screen.dart';
import '../../features/home_client/home_client_screen.dart';
import '../../features/home_driver/home_driver_screen.dart';
import '../../features/home_driver_thiak/home_driver_thiak_screen.dart';
import '../../features/splash/splash_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),

    // ── Auth ──
    GoRoute(
      path: '/phone',
      builder: (context, state) => const PhoneScreen(),
    ),
    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return OtpScreen(phone: extra['phone']);
      },
    ),
    GoRoute(
      path: '/role-selection',
      builder: (context, state) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: '/driver/onboarding',
      builder: (context, state) {
        final type = state.uri.queryParameters['type'] ?? 'MOTO';
        return DriverOnboardingScreen(vehicleType: type);
      },
    ),

    // ── Client ──
    GoRoute(
      path: '/client/home',
      builder: (context, state) => const HomeClientScreen(),
    ),

    // ── Driver Livraison (moto) ──
    GoRoute(
      path: '/driver/home',
      builder: (context, state) => const HomeDriverScreen(),
    ),

    // ── Driver Thiak Thiak (taxi) ──
    GoRoute(
      path: '/driver/thiak/home',
      builder: (context, state) => const HomeDriverThiakScreen(),
    ),
  ],
);
