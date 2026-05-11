import 'package:go_router/go_router.dart';
import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/role_selection_screen.dart';
import '../../features/auth/screens/driver_onboarding_screen.dart';
import '../../features/auth/screens/client_onboarding_screen.dart';
import '../../features/home_client/home_client_screen.dart';
import '../../features/home_client/order_create_screen.dart';
import '../../features/home_client/order_confirmation_screen.dart';
import '../../features/home_driver/home_driver_screen.dart';
import '../../features/home_driver_thiak/home_driver_thiak_screen.dart';

import '../../features/client_profile/client_profile_screen.dart';
import '../../features/client_profile/favorite_addresses_screen.dart';
import '../../features/home_client/orders_history_screen.dart';
import '../../features/home_client/order_tracking_screen.dart';


import '../../features/splash/screens/splash_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/profile/screens/driver_profile_screen.dart';
import '../../features/home_driver/active_order_screen.dart';
import '../../features/admin/screens/admin_login_screen.dart';
import '../../features/admin/screens/admin_panel_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_onboarding_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_pending_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_dashboard_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_add_driver_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_rejected_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_suspended_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_profile_screen.dart';
import '../../features/profile/screens/driver_suspended_screen.dart';

import 'package:flutter/widgets.dart';

final routeObserver = RouteObserver<ModalRoute<void>>();

final appRouter = GoRouter(
  initialLocation: '/splash',
  observers: [routeObserver],
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
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
      path: '/client/onboarding',
      builder: (context, state) => const ClientOnboardingScreen(),
    ),
    GoRoute(
      path: '/client/home',
      builder: (context, state) => const HomeClientScreen(),
    ),
    GoRoute(
      path: '/client/profile',
      builder: (context, state) => const ClientProfileScreen(),
    ),
    GoRoute(
      path: '/client/favorite-addresses',
      builder: (context, state) => const FavoriteAddressesScreen(),
    ),
    GoRoute(
      path: '/orders/create',
      builder: (context, state) {
        final type = state.uri.queryParameters['type'] ?? 'DELIVERY';
        return OrderCreateScreen(orderType: type);
      },
    ),
    GoRoute(
      path: '/orders/confirmation',
      builder: (context, state) {
        final order = state.extra as Map<String, dynamic>;
        return OrderConfirmationScreen(order: order);
      },
    ),
    GoRoute(
      path: '/orders/my',
      builder: (context, state) => const OrdersHistoryScreen(),
    ),
    GoRoute(
      path: '/orders/tracking',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return OrderTrackingScreen(
          orderId: extra['orderId'] as String,
          driverId: extra['driverId'] as String,
          etaPickupMin: extra['etaPickupMin'] as int?,
        );
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

    // ── Chef de flotte ──
    GoRoute(
      path: '/chef-de-flotte/onboarding',
      builder: (context, state) => const ChefDeFlotteOnboardingScreen(),
    ),
    GoRoute(
      path: '/chef-de-flotte/pending',
      builder: (context, state) => const ChefDeFlottePendingScreen(),
    ),
    GoRoute(
      path: '/chef-de-flotte/dashboard',
      builder: (context, state) => const ChefDeFlotteDashboardScreen(),
    ),
    GoRoute(
      path: '/chef-de-flotte/add-driver',
      builder: (context, state) => const ChefDeFlotteAddDriverScreen(),
    ),
    GoRoute(
      path: '/chef-de-flotte/rejected',
      builder: (context, state) => const ChefDeFlotteRejectedScreen(),
    ),
    GoRoute(
      path: '/chef-de-flotte/suspended',
      builder: (context, state) => const ChefDeFlotteSuspendedScreen(),
    ),
    GoRoute(
      path: '/chef-de-flotte/profile',
      builder: (context, state) => const ChefDeFlotteProfileScreen(),
    ),
    GoRoute(
      path: '/driver/suspended',
      builder: (context, state) => const DriverSuspendedScreen(),
    ),

    // ── Admin ──
    GoRoute(
      path: '/admin/login',
      builder: (context, state) => const AdminLoginScreen(),
    ),
    GoRoute(
      path: '/admin/home',
      builder: (context, state) => const AdminPanelScreen(),
    ),
  ],
);
