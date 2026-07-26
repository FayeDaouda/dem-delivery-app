import 'package:flutter/services.dart';

class AppConfig {
  // Clé lue au démarrage via MethodChannel (iOS) ou --dart-define (Android/CI).
  // Appeler AppConfig.init() dans main() avant runApp().
  static String _mapsApiKey = String.fromEnvironment('MAPS_API_KEY', defaultValue: '');
  static String get mapsApiKey => _mapsApiKey;

  static Future<void> init() async {
    if (_mapsApiKey.isEmpty) {
      try {
        final key = await const MethodChannel('dem/config')
            .invokeMethod<String>('getMapsApiKey');
        if (key != null && key.isNotEmpty) _mapsApiKey = key;
      } catch (_) {}
    }
  }

  static const privacyPolicyUrl = 'https://www.dem.sn/privacy';
  static const termsUrl         = 'https://www.dem.sn/terms';

  // Contact support — centralisé ici pour éviter les numéros dupliqués/
  // divergents d'un écran à l'autre (Signaler un problème, profil, suivi...).
  static const supportPhone     = '+221710064664';
  static const supportWhatsapp  = '221710064664';
  static const supportEmail     = 'support@dem.sn';
}
