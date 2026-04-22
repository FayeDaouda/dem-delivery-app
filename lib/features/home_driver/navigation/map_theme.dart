import 'package:flutter/material.dart';

/// Système de thème carte jour/nuit — style Waze/Uber.
/// Détection automatique basée sur l'heure locale.
class MapTheme {
  MapTheme._();

  // ── Détection automatique jour/nuit ───────────────────────────────────
  static bool get isNight {
    final hour = DateTime.now().hour;
    return hour >= 20 || hour < 7;
  }

  // ── Assets map style (avec override manuel possible) ──────────────────
  static String styleAssetFor(bool night) => night
      ? 'assets/map_style_waze.json'   // nuit : sombre immersif
      : 'assets/map_style_day.json';   // jour  : clair lisible

  static String get styleAsset => styleAssetFor(isNight);

  // ── Couleurs trafic ───────────────────────────────────────────────────
  /// [level] : 'low' | 'medium' | 'high'
  static Color trafficColor(String level) {
    if (isNight) {
      return switch (level) {
        'medium' => const Color(0xFFFFB300), // orange vif
        'high'   => const Color(0xFFFF3D00), // rouge vif
        _        => const Color(0xFF00FF95), // vert néon
      };
    } else {
      return switch (level) {
        'medium' => const Color(0xFFFF9800), // orange
        'high'   => const Color(0xFFFF1744), // rouge
        _        => const Color(0xFF00E676), // vert
      };
    }
  }

  // ── Marqueur driver ───────────────────────────────────────────────────
  /// Nuit : cyan Waze #33BCD4 — Jour : violet-bleu Waze #5B6FC8
  static Color get driverMarkerColor =>
      isNight ? const Color(0xFF33BCD4) : const Color(0xFF5B6FC8);

  // ── Route polyline ────────────────────────────────────────────────────
  /// Nuit : cyan Waze #33BCD4 — Jour : violet-bleu Waze #5B6FC8
  static Color get routeColor =>
      isNight ? const Color(0xFF33BCD4) : const Color(0xFF5B6FC8);

  // ── UI overlay ────────────────────────────────────────────────────────
  static Color get headerBackground => isNight
      ? Colors.black.withValues(alpha: 0.75)
      : Colors.white.withValues(alpha: 0.92);

  static Color get headerText =>
      isNight ? Colors.white : const Color(0xFF212121);

  static Color get compassBackground => isNight
      ? Colors.black.withValues(alpha: 0.75)
      : Colors.white.withValues(alpha: 0.92);
}
