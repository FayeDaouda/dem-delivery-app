import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../router/app_router.dart';

/// Handler background (app fermée / suspendue) — doit être top-level.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Firebase est déjà initialisé par main.dart. Navigation impossible ici.
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;

  /// À appeler une seule fois dans main(), après Firebase.initializeApp().
  static Future<void> init() async {
    try {
      // 1. Permission (iOS + Android 13+)
      await _messaging.requestPermission(
        alert: true, badge: true, sound: true,
      ).timeout(const Duration(seconds: 5));

      // 2. iOS : affiche en foreground
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      // 3. Handler background
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      // 4. Token → backend
      final token = await _messaging.getToken().timeout(const Duration(seconds: 10));
      if (token != null) await _saveToken(token);
      _messaging.onTokenRefresh.listen(_saveToken);

      // 5. Message reçu en foreground → banner in-app
      FirebaseMessaging.onMessage.listen(_handleForeground);

      // 6. Tap sur notification depuis background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // 7. Tap sur notification depuis app terminée
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);

    } catch (_) {
      // Silencieux sur émulateur sans Google Play Services
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  static void _handleTap(RemoteMessage message) {
    final route = _routeForType(message.data['type'] as String?);
    if (route != null) {
      // Petit délai pour laisser le router s'initialiser (cas app terminée)
      Future.delayed(const Duration(milliseconds: 300), () {
        appRouter.go(route);
      });
    }
  }

  // ── Banner in-app (foreground) ────────────────────────────────────────────

  static void _handleForeground(RemoteMessage message) {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;

    final title = message.notification?.title ?? '';
    final body  = message.notification?.body  ?? '';
    final type  = message.data['type'] as String?;
    final route = _routeForType(type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(body, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        action: route != null
            ? SnackBarAction(
                label: 'Voir',
                textColor: Colors.white,
                onPressed: () => appRouter.go(route),
              )
            : null,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xFF0F2942),
      ),
    );
  }

  // ── Mapping type → route ──────────────────────────────────────────────────

  static String? _routeForType(String? type) => switch (type) {
    // ── Admin / validation ──────────────────────────────────────────────────
    'CHEF_DE_FLOTTE_VALIDATED'      => '/chef-de-flotte/dashboard',
    'CHEF_DE_FLOTTE_REJECTED'       => '/chef-de-flotte/rejected',
    'CHEF_DE_FLOTTE_SUSPENDED'      => '/chef-de-flotte/suspended',
    'DRIVER_VALIDATED_FOR_AM'   => '/chef-de-flotte/dashboard',
    'DRIVER_REJECTED_FOR_AM'    => '/chef-de-flotte/dashboard',
    'FLEET_EXTENSION_APPROVED'  => '/chef-de-flotte/dashboard',
    'FLEET_EXTENSION_REJECTED'  => '/chef-de-flotte/dashboard',
    'DRIVER_VALIDATED'          => '/driver/home',
    'DRIVER_REJECTED'           => '/phone',
    'DRIVER_SUSPENDED'          => '/driver/suspended',
    // ── Orders — driver ─────────────────────────────────────────────────────
    'ORDER_OFFER'               => '/driver/home',     // socket affiche le modal d'offre
    'ORDER_CANCELLED'           => '/driver/home',     // client a annulé avant acceptation
    // ── Orders — client ─────────────────────────────────────────────────────
    'ORDER_ACCEPTED'            => '/client/home',
    'ORDER_PICKED_UP'           => '/client/home',
    'ORDER_DELIVERED'           => '/orders/my',
    'ORDER_SEARCHING'           => '/client/home',     // on cherche encore un livreur
    'ORDER_AUTO_CANCELLED'      => '/client/home',     // annulation auto après 15 min
    'DISPUTE_OPENED'            => '/orders/my',       // litige signalé → historique
    // ── Paiement — driver ───────────────────────────────────────────────────
    'PAYMENT_RESOLVED'          => '/driver/home',     // admin confirme paiement
    _ => null,
  };

  // ── Token ─────────────────────────────────────────────────────────────────

  static Future<void> _saveToken(String token) async {
    try {
      await ApiClient.dio.put('/users/fcm-token', data: {'token': token});
    } catch (_) {}
  }
}
