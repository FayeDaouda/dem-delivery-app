import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_client.dart';
import '../router/app_router.dart';
import '../router/app_startup_notifier.dart';

/// Handler background (app fermée / suspendue) — doit être top-level.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Firebase est déjà initialisé par main.dart. Navigation impossible ici.
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  /// À appeler dans main() : initialise les canaux et listeners, sans demander la permission.
  static Future<void> setup() async {
    try {
      // Local notifications — pas de demande de permission ici (false sur iOS)
      const androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInitSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(android: androidInitSettings, iOS: iosInitSettings);
      await _localNotificationsPlugin.initialize(settings: initSettings);

      // Canal Android haute importance (alertes, nouvelles courses)
      const channel = AndroidNotificationChannel(
        'dem_order_alert',
        'Alertes courses DEM',
        description: 'Son et vibration pour les nouvelles courses',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('dem_order_alert'),
      );
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Canal Android notifications générales (broadcast, statut commande, etc.)
      const notifyChannel = AndroidNotificationChannel(
        'dem_notify',
        'Notifications DEM',
        description: 'Notifications générales DEM',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('dem_notify'),
      );
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(notifyChannel);

      // Canal Android discret (notification persistante GPS pendant la course)
      // Importance.low = pas de son/vibration, mais visible dans la barre de statut.
      // DOIT être créé ici — Android 8+ refuse d'afficher une notification
      // sur un canal inexistant (silencieux, sans erreur apparente).
      const ongoingChannel = AndroidNotificationChannel(
        'dem_ongoing_course',
        'Course en cours',
        description: 'Suivi de la course active en temps réel',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      );
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(ongoingChannel);

      // iOS : affiche en foreground nativement via Firebase
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      // Handler background
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      // Message reçu en foreground → banner in-app
      FirebaseMessaging.onMessage.listen(_handleForeground);

      // Tap sur notification depuis background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // Tap sur notification depuis app terminée
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);

    } catch (_) {
      // Silencieux sur émulateur sans Google Play Services
    }
  }

  /// À appeler après l'onboarding : demande la permission et enregistre le token FCM.
  static Future<void> requestPermissionAndToken() async {
    try {
      await _messaging.requestPermission(
        alert: true, badge: true, sound: true,
      ).timeout(const Duration(seconds: 5));

      // iOS : attendre le token APNs avant le token FCM (obligatoire v15+)
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken;
        for (int i = 0; i < 10 && apnsToken == null; i++) {
          apnsToken = await _messaging.getAPNSToken();
          if (apnsToken == null) await Future.delayed(const Duration(seconds: 1));
        }
      }

      final token = await _messaging.getToken().timeout(const Duration(seconds: 10));
      if (token != null) await _saveToken(token);
      _messaging.onTokenRefresh.listen(_saveToken);

    } catch (_) {
      // Silencieux si pas de Google Play Services ou refus utilisateur
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  static void _handleTap(RemoteMessage message) {
    final type     = message.data['type'] as String?;
    final orderId  = message.data['orderId'] as String?;
    final driverId = message.data['driverId'] as String?;
    final batchId  = message.data['batchId'] as String?;

    Future.delayed(const Duration(milliseconds: 300), () {
      final role = appStartupNotifier.role;
      final isDemPro = role == 'DEM_PRO';

      if ((type == 'ORDER_ACCEPTED' || type == 'ORDER_PICKED_UP' || type == 'DRIVER_NEARBY') &&
          orderId != null && driverId != null) {
        appRouter.push(isDemPro ? '/dem-pro/orders/tracking' : '/orders/tracking', extra: {
          'orderId': orderId,
          'driverId': driverId,
        });
        return;
      }
      if ((type == 'BATCH_ACCEPTED' || type == 'BATCH_COMPLETED') && batchId != null) {
        appRouter.push('/dem-pro/batch/tracking', extra: {'batchId': batchId});
        return;
      }
      if (isDemPro && (type == 'ORDER_DELIVERED' || type == 'ORDER_AUTO_CANCELLED')) {
        appRouter.go('/dem-pro/home');
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
      if ((type == 'ORDER_ACCEPTED' || type == 'ORDER_PICKED_UP' || type == 'DRIVER_NEARBY') &&
          orderId != null && driverId != null) {
        final role = appStartupNotifier.role;
        final path = role == 'DEM_PRO' ? '/dem-pro/orders/tracking' : '/orders/tracking';
        appRouter.push(path, extra: {
          'orderId': orderId,
          'driverId': driverId,
        });
      } else {
        final batchId = message.data['batchId'] as String?;
        if ((type == 'BATCH_ACCEPTED' || type == 'BATCH_COMPLETED') && batchId != null) {
          appRouter.push('/dem-pro/batch/tracking', extra: {'batchId': batchId});
        } else {
          final route = _routeForType(type);
          if (route != null) appRouter.go(route);
        }
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
    playAlertSound();
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
    // ── Orders — client / DEM Pro ──────────────────────────────────────────
    'ORDER_ACCEPTED'            => null, // géré dans _handleTap avec role-aware routing
    'ORDER_PICKED_UP'           => null,
    'ORDER_DELIVERED'           => '/orders/my',
    'ORDER_SEARCHING'           => '/client/home',
    'ORDER_AUTO_CANCELLED'      => '/orders/my',
    'BATCH_ACCEPTED'            => null, // géré dans _handleTap
    'BATCH_COMPLETED'           => null,
    'DRIVER_NEARBY'             => null, // géré dans _handleTap
    'DISPUTE_OPENED'            => '/orders/my',
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

  // ── Son d'alerte (accompagne la bannière in-app) ─────────────────────────
  static Future<void> playAlertSound() async {
    HapticFeedback.mediumImpact();
    // iOS : notification silencieuse (pas de bannière) qui joue juste le son
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _localNotificationsPlugin.show(
        id: 6666,
        title: '',
        body: '',
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: true,
          ),
        ),
      );
    }
  }

  // ── Sonnerie en boucle pour nouvelle course (livreur) ─────────────────────
  static Timer? _orderAlertTimer;

  static void startOrderAlert() {
    stopOrderAlert();
    _playOrderAlertOnce();
    _orderAlertTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _playOrderAlertOnce();
    });
  }

  static void stopOrderAlert() {
    _orderAlertTimer?.cancel();
    _orderAlertTimer = null;
    _localNotificationsPlugin.cancel(id: 7777);
  }

  static Future<void> _playOrderAlertOnce() async {
    HapticFeedback.heavyImpact();
    final androidDetails = AndroidNotificationDetails(
      'dem_order_alert',
      'Alertes courses DEM',
      channelDescription: 'Son et vibration pour les nouvelles courses',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      fullScreenIntent: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('dem_order_alert'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 300, 200, 300, 200, 300]),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'dem_order_alert.wav',
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _localNotificationsPlugin.show(
      id: 7777,
      title: 'Nouvelle course disponible !',
      body: 'Ouvrez l\'application pour accepter la course.',
      notificationDetails: details,
    );
  }

  // ── Notifications système persistantes (en cours) ─────────────────────────
  static Future<void> showOngoingNotification({required int id, required String title, required String body}) async {
    // iOS ne supporte pas les notifications "ongoing" — on ne les affiche que sur Android
    if (defaultTargetPlatform != TargetPlatform.android) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'dem_ongoing_course',
        'Course en cours',
        channelDescription: 'Suivi de la course active',
        importance: Importance.low,
        priority: Priority.low,
        icon: '@mipmap/ic_launcher',
        ongoing: true,
        autoCancel: false,
        showWhen: false,
      ),
    );
    await _localNotificationsPlugin.show(
      id: id, title: title, body: body,
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
