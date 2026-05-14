import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_client.dart';
import '../router/app_router.dart';

/// Handler background (app fermée / suspendue) — doit être top-level.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Firebase est déjà initialisé par main.dart. Navigation impossible ici.
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  /// À appeler une seule fois dans main(), après Firebase.initializeApp().
  static Future<void> init() async {
    try {
      // 1. Permission (iOS + Android 13+)
      await _messaging.requestPermission(
        alert: true, badge: true, sound: true,
      ).timeout(const Duration(seconds: 5));

      // 1.b Initialisation Local Notifications (pour afficher en foreground)
      const androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInitSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(android: androidInitSettings, iOS: iosInitSettings);
      await _localNotificationsPlugin.initialize(settings: initSettings);

      // Création du channel Android haute importance
      const channel = AndroidNotificationChannel(
        'dem_high_importance',
        'Notifications Importantes DEM',
        description: 'Notifications de courses en temps réel',
        importance: Importance.max,
        enableVibration: true,
      );
      await _localNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

      // 2. iOS : affiche en foreground nativement via Firebase
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      // 3. Handler background
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      // 4. iOS : attendre le token APNs avant de demander le token FCM (obligatoire v15+)
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken;
        for (int i = 0; i < 10 && apnsToken == null; i++) {
          apnsToken = await _messaging.getAPNSToken();
          if (apnsToken == null) await Future.delayed(const Duration(seconds: 1));
        }
      }

      // 5. Token FCM → backend
      final token = await _messaging.getToken().timeout(const Duration(seconds: 10));
      if (token != null) await _saveToken(token);
      _messaging.onTokenRefresh.listen(_saveToken);

      // 6. Message reçu en foreground → banner in-app
      FirebaseMessaging.onMessage.listen(_handleForeground);

      // 7. Tap sur notification depuis background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // 8. Tap sur notification depuis app terminée
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);

    } catch (_) {
      // Silencieux sur émulateur sans Google Play Services
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  static void _handleTap(RemoteMessage message) {
    final type     = message.data['type'] as String?;
    final orderId  = message.data['orderId'] as String?;
    final driverId = message.data['driverId'] as String?;

    // Petit délai pour laisser le router s'initialiser (cas app terminée)
    Future.delayed(const Duration(milliseconds: 300), () {
      // ORDER_ACCEPTED / ORDER_PICKED_UP → aller directement au suivi si on a les IDs
      if ((type == 'ORDER_ACCEPTED' || type == 'ORDER_PICKED_UP') &&
          orderId != null && driverId != null) {
        appRouter.push('/orders/tracking', extra: {
          'orderId': orderId,
          'driverId': driverId,
        });
        return;
      }
      final route = _routeForType(type);
      if (route != null) appRouter.go(route);
    });
  }

  // ── Bannière en haut (foreground) ────────────────────────────────────────

  static OverlayEntry? _activeBanner;

  static void _handleForeground(RemoteMessage message) {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;

    final title    = message.notification?.title ?? '';
    final body     = message.notification?.body  ?? '';
    final type     = message.data['type'] as String?;
    final orderId  = message.data['orderId'] as String?;
    final driverId = message.data['driverId'] as String?;

    // Retire l'éventuelle bannière précédente
    _activeBanner?.remove();

    late OverlayEntry entry;
    var removed = false;

    void dismiss() {
      if (removed) return;
      removed = true;
      entry.remove();
      _activeBanner = null;
    }

    void onTap() {
      dismiss();
      if ((type == 'ORDER_ACCEPTED' || type == 'ORDER_PICKED_UP') &&
          orderId != null && driverId != null) {
        appRouter.push('/orders/tracking', extra: {
          'orderId': orderId,
          'driverId': driverId,
        });
      } else {
        final route = _routeForType(type);
        if (route != null) appRouter.go(route);
      }
    }

    entry = OverlayEntry(
      builder: (_) => _TopBanner(
        title: title,
        body: body,
        hasAction: _routeForType(type) != null ||
            ((type == 'ORDER_ACCEPTED' || type == 'ORDER_PICKED_UP') &&
                orderId != null && driverId != null),
        onTap: onTap,
        onDismiss: dismiss,
      ),
    );

    _activeBanner = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 6), dismiss);
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

  // ── Notifications système locales ─────────────────────────────────────────
  static Future<void> showSystemNotification({required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'dem_high_importance',
      'Notifications Importantes DEM',
      channelDescription: 'Notifications de courses en temps réel',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _localNotificationsPlugin.show(
      id: DateTime.now().millisecond, // ID unique
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  // ── Notifications système persistantes (en cours) ─────────────────────────
  static Future<void> showOngoingNotification({required int id, required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'dem_ongoing_course',
      'Course en cours',
      channelDescription: 'Suivi de la course active',
      importance: Importance.low, // Pour ne pas sonner à chaque maj
      priority: Priority.low,
      icon: '@mipmap/ic_launcher',
      ongoing: true,      // Reste dans la barre
      autoCancel: false,  // Ne se ferme pas au clic
      showWhen: false,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: false, // Pas d'alerte agaçante sur iOS pour l'ongoing
      presentBadge: false,
      presentSound: false,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _localNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  static Future<void> cancelNotification(int id) async {
    await _localNotificationsPlugin.cancel(id: id);
  }
}

// ── Bannière in-app en haut (cyan, slide depuis le haut) ─────────────────────

class _TopBanner extends StatefulWidget {
  final String title;
  final String body;
  final bool hasAction;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _TopBanner({
    required this.title,
    required this.body,
    required this.hasAction,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: widget.hasAction ? widget.onTap : null,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0CB8DE), Color(0xFF0671BA)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0CB8DE).withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.title.isNotEmpty)
                              Text(widget.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  )),
                            if (widget.body.isNotEmpty)
                              Text(widget.body,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      if (widget.hasAction) ...[
                        const SizedBox(width: 8),
                        const Text('Voir',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            )),
                        const SizedBox(width: 4),
                      ],
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              color: Colors.white70, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
