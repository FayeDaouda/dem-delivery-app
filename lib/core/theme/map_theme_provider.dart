import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapNightNotifier extends StateNotifier<bool> {
  static const _key = 'map_night_mode';

  // Démarre toujours en mode jour — init() charge la préférence sauvegardée.
  // Ne jamais auto-détecter depuis l'heure : l'utilisateur contrôle le toggle.
  MapNightNotifier() : super(false);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_key);
    if (saved != null && mounted) state = saved;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

final mapNightProvider =
    StateNotifierProvider<MapNightNotifier, bool>((ref) {
  final notifier = MapNightNotifier();
  notifier.init();
  return notifier;
});
