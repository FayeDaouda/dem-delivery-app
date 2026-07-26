import 'package:shared_preferences/shared_preferences.dart';

/// Code promo "retenu" par l'utilisateur depuis l'écran dédié (voir
/// promo_code_screen.dart) — pré-rempli automatiquement à la prochaine
/// commande éligible, pour ne pas avoir à le retaper à chaque fois.
class PromoCodeStorage {
  static const _key = 'saved_promo_code';

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> save(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code.trim().toUpperCase());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
