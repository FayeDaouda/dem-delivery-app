import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';

import 'app_startup_notifier.dart';

import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/role_selection_screen.dart';
import '../../features/auth/screens/driver_onboarding_screen.dart';
import '../../features/auth/screens/client_onboarding_screen.dart';
import '../../features/home_client/client_home_shell_screen.dart';
import '../../features/home_client/batch_create_screen.dart';
import '../../features/home_client/batch_confirmation_screen.dart';
import '../../features/home_client/batch_tracking_screen.dart';
import '../../features/home_client/order_confirmation_screen.dart';
import '../../features/home_driver/home_driver_screen.dart';

import '../../features/client_profile/client_profile_screen.dart';
import '../../features/client_profile/favorite_addresses_screen.dart';
import '../../features/client_profile/promo_code_screen.dart';
import '../../features/client_profile/referrals_screen.dart';
import '../../features/client_profile/settings_screen.dart';
import '../../features/home_client/orders_history_screen.dart';
import '../../features/home_client/order_tracking_screen.dart';
import '../../features/home_client/order_detail_screen.dart';
import '../../features/notifications/notifications_screen.dart';

import '../../features/splash/screens/splash_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/onboarding/screens/location_disclosure_screen.dart';
import '../../features/profile/screens/document_upload_screen.dart';
import '../../features/profile/screens/driver_profile_screen.dart';
import '../../features/profile/screens/driver_settings_screen.dart';
import '../../features/home_driver/active_order_screen.dart';
import '../../features/home_driver/active_batch_screen.dart';
import '../../features/admin/screens/admin_login_screen.dart';
import '../../features/admin/screens/admin_panel_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_onboarding_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_pending_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_dashboard_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_add_driver_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_rejected_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_suspended_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_profile_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_driver_detail_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_fleet_map_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_fleet_extensions_screen.dart';
import '../../features/chef_de_flotte/screens/chef_de_flotte_incidents_screen.dart';
import '../../features/profile/screens/driver_suspended_screen.dart';
import '../../features/dem_pro/screens/dem_pro_onboarding_screen.dart';
import '../../features/dem_pro/screens/dem_pro_pending_screen.dart';
import '../../features/dem_pro/screens/dem_pro_rejected_screen.dart';
import '../../features/dem_pro/screens/dem_pro_suspended_screen.dart';
import '../../features/dem_pro/screens/dem_pro_home_screen.dart';
import '../../features/dem_pro/screens/dem_pro_order_create_screen.dart';
import '../../features/dem_pro/screens/dem_pro_batch_create_screen.dart';
import '../../features/dem_pro/screens/dem_pro_batch_confirmation_screen.dart';
import '../../features/dem_pro/screens/dem_pro_batch_tracking_screen.dart';
import '../../features/dem_pro/screens/dem_pro_order_confirmation_screen.dart';
import '../../features/dem_pro/screens/dem_pro_order_tracking_screen.dart';
import '../../features/dem_pro/screens/dem_pro_receipt_screen.dart';
import '../../features/dem_pro/screens/dem_pro_products_screen.dart';
import '../../features/dem_pro/screens/dem_pro_order_requests_screen.dart';
import '../../features/dem_pro/screens/dem_pro_promo_code_screen.dart';
import '../../features/dem_pro/screens/dem_pro_wallet_screen.dart';
import '../../features/dem_pro/screens/dem_pro_clients_screen.dart';
import '../../features/guest_tracking/guest_tracking_screen.dart';
import '../../features/public_storefront/screens/storefront_screen.dart';

final routeObserver = RouteObserver<ModalRoute<void>>();

// ── Ensemble des routes "publiques" (avant auth) ──────────────────────────────
const _preAuthRoutes = {
  '/splash',
  '/onboarding',
  '/location-disclosure',
  '/phone',
  '/otp',
};

// ── Ensemble des routes admin (pas de garde onboarding) ───────────────────────
const _adminRoutes = {'/admin/login', '/admin/home'};

final appRouter = GoRouter(
  initialLocation: '/splash',
  observers: [routeObserver],

  // ── Notifier : déclenche redirect à chaque changement d'état ─────────────────
  refreshListenable: appStartupNotifier,

  // ─────────────────────────────────────────────────────────────────────────────
  // REDIRECT — contrôle toutes les routes
  // ─────────────────────────────────────────────────────────────────────────────
  redirect: (context, state) {
    final path = state.matchedLocation;
    final n = appStartupNotifier;

    // ── 0. Pas encore initialisé → rester sur /splash ───────────────────────
    if (!n.isReady) {
      return path == '/splash' ? null : '/splash';
    }

    // ── Admin : pas de garde de flux onboarding ──────────────────────────────
    if (_adminRoutes.contains(path)) return null;

    // ── Suivi invité : accessible sans auth ─────────────────────────────────
    if (path.startsWith('/track/')) return null;

    // ── Boutique publique DEM Pro : accessible sans auth ────────────────────
    if (path.startsWith('/commander/')) return null;

    // ── 1. Utilisateur connecté ──────────────────────────────────────────────
    if (n.isLoggedIn) {
      // Si sur une route pré-auth → rediriger vers la home du rôle
      if (_preAuthRoutes.contains(path)) return n.homeForRole;
      return null; // toute autre route → OK
    }

    // ── 2. Utilisateur non connecté ──────────────────────────────────────────

    // Onboarding pas encore vu → forcer /onboarding
    if (!n.onboardingSeen) {
      return path == '/onboarding' ? null : '/onboarding';
    }

    // Divulgation pas encore vue → forcer /location-disclosure
    if (!n.disclosureSeen) {
      return path == '/location-disclosure' ? null : '/location-disclosure';
    }

    // Onboarding + disclosure vus : si encore sur ces pages → /phone
    if (path == '/splash' ||
        path == '/onboarding' ||
        path == '/location-disclosure') {
      return '/phone';
    }

    return null; // laisser passer
  },

  // ─────────────────────────────────────────────────────────────────────────────
  // ROUTES
  // ─────────────────────────────────────────────────────────────────────────────
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/location-disclosure',
      builder: (context, state) => const LocationDisclosureScreen(),
    ),

    // ── Suivi invité (public, sans auth) ──
    GoRoute(
      path: '/track/:id',
      builder: (context, state) =>
          GuestTrackingScreen(orderId: state.pathParameters['id']!),
    ),

    // ── Boutique publique DEM Pro (public, sans auth) ──
    GoRoute(
      path: '/commander/:merchantId',
      builder: (context, state) =>
          StorefrontScreen(merchantId: state.pathParameters['merchantId']!),
    ),

    // ── Auth ──
    GoRoute(path: '/phone', builder: (context, state) => const PhoneScreen()),
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
      builder: (context, state) => const ClientHomeShellScreen(),
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
      path: '/client/promo-code',
      builder: (context, state) => const PromoCodeScreen(),
    ),
    GoRoute(
      path: '/client/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/client/referrals',
      builder: (context, state) => const ReferralsScreen(),
    ),
    // '/orders/create' supprimée (fusion pré-production, étape A) — Express/
    // Simple sont désormais des modes de ClientHomeShellScreen ('/client/home'),
    // plus une route séparée. Confirmé qu'aucun deep-link externe ne pointe
    // vers cette route avant suppression (seule '/dem-pro/orders/create',
    // sans rapport, existe ailleurs).
    GoRoute(
      path: '/orders/batch/create',
      builder: (context, state) => const BatchCreateScreen(),
    ),
    GoRoute(
      path: '/orders/batch/confirmation',
      builder: (context, state) {
        final batch = state.extra as Map<String, dynamic>;
        return BatchConfirmationScreen(batch: batch);
      },
    ),
    GoRoute(
      path: '/orders/batch/mine',
      builder: (context, state) => const BatchListScreen(),
    ),
    GoRoute(
      path: '/orders/batch/mine/:id',
      builder: (context, state) =>
          BatchDetailScreen(batchId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/dem-pro/orders/create',
      builder: (context, state) {
        final scheduled = state.uri.queryParameters['scheduled'] == 'true';
        final priority = state.uri.queryParameters['priority'] == 'EXPRESS'
            ? 'EXPRESS'
            : 'NORMAL';
        final extra = state.extra;
        Map<String, dynamic>? reorderFrom;
        Map<String, dynamic>? fromOrderRequest;
        if (extra is Map<String, dynamic>) {
          if (extra.containsKey('fromOrderRequest')) {
            fromOrderRequest =
                extra['fromOrderRequest'] as Map<String, dynamic>?;
          } else {
            reorderFrom = extra;
          }
        }
        return DemProOrderCreateScreen(
          scheduled: scheduled,
          priority: priority,
          reorderFrom: reorderFrom,
          fromOrderRequest: fromOrderRequest,
        );
      },
    ),
    GoRoute(
      path: '/dem-pro/batch/create',
      builder: (context, state) => DemProBatchCreateScreen(
        reorderFrom: state.extra as Map<String, dynamic>?,
      ),
    ),
    GoRoute(
      path: '/dem-pro/batch/confirmation',
      builder: (context, state) {
        final batch = state.extra as Map<String, dynamic>;
        return DemProBatchConfirmationScreen(batch: batch);
      },
    ),
    GoRoute(
      path: '/dem-pro/batch/tracking',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>;
        final batchId = args['batchId'] as String;
        final initialBatch = args['initialBatch'] as Map<String, dynamic>?;
        return DemProBatchTrackingScreen(
          batchId: batchId,
          initialBatch: initialBatch,
        );
      },
    ),
    GoRoute(
      path: '/dem-pro/orders/confirmation',
      builder: (context, state) {
        final order = state.extra as Map<String, dynamic>;
        return DemProOrderConfirmationScreen(order: order);
      },
    ),
    GoRoute(
      path: '/dem-pro/orders/tracking',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>;
        return DemProOrderTrackingScreen(
          orderId: args['orderId'] as String,
          driverId: args['driverId'] as String,
          etaPickupMin: args['etaPickupMin'] as int?,
          initialOrder: args['initialOrder'] as Map<String, dynamic>?,
        );
      },
    ),
    GoRoute(
      path: '/dem-pro/orders/receipt',
      builder: (context, state) =>
          DemProReceiptScreen(order: state.extra as Map<String, dynamic>),
    ),
    GoRoute(
      path: '/dem-pro/products',
      builder: (context, state) => DemProProductsScreen(
        autoOpenForm: state.uri.queryParameters['add'] == 'true',
      ),
    ),
    GoRoute(
      path: '/dem-pro/order-requests',
      builder: (context, state) => const DemProOrderRequestsScreen(),
    ),
    GoRoute(
      path: '/dem-pro/promo-code',
      builder: (context, state) => const DemProPromoCodeScreen(),
    ),
    GoRoute(
      path: '/dem-pro/wallet',
      builder: (context, state) => const DemProWalletScreen(),
    ),
    GoRoute(
      path: '/dem-pro/clients',
      builder: (context, state) => const DemProClientsScreen(),
    ),
    GoRoute(
      path: '/dem-pro/clients/detail',
      builder: (context, state) =>
          DemProClientDetailScreen(client: state.extra as Map<String, dynamic>),
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
          initialOrder: extra['initialOrder'] as Map<String, dynamic>?,
        );
      },
    ),
    GoRoute(
      path: '/orders/detail',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return OrderDetailScreen(
          orderId: extra['orderId'] as String,
          initialOrder: extra['initialOrder'] as Map<String, dynamic>?,
        );
      },
    ),
    GoRoute(
      path: '/client/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/driver/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),

    // ── Driver Livraison (moto) ──
    GoRoute(
      path: '/driver/home',
      builder: (context, state) => const HomeDriverScreen(),
    ),

    // ── Active order (driver) ──
    GoRoute(
      path: '/driver/order/active',
      builder: (context, state) {
        final order = state.extra as Map<String, dynamic>;
        return ActiveOrderScreen(order: order);
      },
    ),

    // ── Active batch (driver) ──
    GoRoute(
      path: '/driver/batch/active',
      builder: (context, state) {
        final batch = state.extra as Map<String, dynamic>;
        return ActiveBatchScreen(batch: batch);
      },
    ),

    // ── Profil driver ──
    GoRoute(
      path: '/driver/profile',
      builder: (context, state) => const DriverProfileScreen(),
    ),

    // ── Documents driver (KYC) ──
    GoRoute(
      path: '/driver/documents',
      builder: (context, state) => const DocumentUploadScreen(),
    ),

    // ── Paramètres & aide driver ──
    GoRoute(
      path: '/driver/settings',
      builder: (context, state) => const DriverSettingsScreen(),
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
      path: '/chef-de-flotte/drivers/:id',
      builder: (context, state) =>
          ChefDeFlotteDriverDetailScreen(driverId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/chef-de-flotte/fleet-map',
      builder: (context, state) => const ChefDeFlotteFleetMapScreen(),
    ),
    GoRoute(
      path: '/chef-de-flotte/fleet-extensions',
      builder: (context, state) => const ChefDeFlotteFleetExtensionsScreen(),
    ),
    GoRoute(
      path: '/chef-de-flotte/incidents',
      builder: (context, state) => const ChefDeFlotteIncidentsScreen(),
    ),

    // ── DEM Pro ──
    GoRoute(
      path: '/dem-pro/onboarding',
      builder: (context, state) => const DemProOnboardingScreen(),
    ),
    GoRoute(
      path: '/dem-pro/pending',
      builder: (context, state) => const DemProPendingScreen(),
    ),
    GoRoute(
      path: '/dem-pro/rejected',
      builder: (context, state) => const DemProRejectedScreen(),
    ),
    GoRoute(
      path: '/dem-pro/suspended',
      builder: (context, state) => const DemProSuspendedScreen(),
    ),
    GoRoute(
      path: '/dem-pro/home',
      builder: (context, state) => const DemProHomeScreen(),
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
