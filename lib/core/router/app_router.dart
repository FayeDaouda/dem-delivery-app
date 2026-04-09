import 'package:go_router/go_router.dart';
import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/role_selection_screen.dart';
import '../../features/auth/screens/driver_onboarding_screen.dart';
import '../../features/home_client/home_client_screen.dart';
import '../../features/home_client/order_create_screen.dart';
import '../../features/home_client/order_confirmation_screen.dart';
import '../../features/home_driver/home_driver_screen.dart';
import '../../features/home_driver_thiak/home_driver_thiak_screen.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/profile/screens/driver_profile_screen.dart';
import '../../features/home_driver/active_order_screen.dart';

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
    GoRoute(
      path: '/orders/create',
      builder: (context, state) => const OrderCreateScreen(),
    ),
    GoRoute(
      path: '/orders/confirmation',
      builder: (context, state) {
        final order = state.extra as Map<String, dynamic>;
        return OrderConfirmationScreen(order: order);
      },
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

    // ── Active order (driver) ──
    GoRoute(
      path: '/driver/order/active',
      builder: (context, state) {
        final order = state.extra as Map<String, dynamic>;
        return ActiveOrderScreen(order: order);
      },
    ),

    // ── Profil driver ──
    GoRoute(
      path: '/driver/profile',
      builder: (context, state) => const DriverProfileScreen(),
    ),
  ],
);
