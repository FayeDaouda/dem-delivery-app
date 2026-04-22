import 'package:firebase_messaging/firebase_messaging.dart';
import '../api/api_client.dart';

/// Handler background (app fermée / suspendue).
/// Doit être top-level (pas une méthode de classe).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Firebase est déjà initialisé par main.dart avant ce handler.
  // Pas besoin de naviguer ici — l'app n'est pas en mémoire.
}

class NotificationService {
  static final _messaging = FirebaseMessaging.instance;

  /// À appeler une seule fois dans main(), après Firebase.initializeApp().
  static Future<void> init() async {
    // 1. Demande de permission (iOS + Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. iOS : affiche les notifications même quand l'app est au premier plan
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. Handler background
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // 4. Envoi du token au backend dès qu'on en a un
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);

    // 5. Renouvellement automatique du token
    _messaging.onTokenRefresh.listen(_saveToken);
  }

  static Future<void> _saveToken(String token) async {
    try {
      await ApiClient.dio.put('/users/fcm-token', data: {'token': token});
    } catch (_) {
      // Silencieux — ne pas crasher si non connecté
    }
  }
}
