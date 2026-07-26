import 'package:flutter/material.dart';

/// Palette dédiée à l'espace "DEM Pro" (compte entrepreneur).
/// Distincte du thème Client/Driver pour donner une identité "pro" propre.
class DemProColors {
  DemProColors._();

  static const Color accent  = Color(0xFF00AECB);
  static const Color bg      = Color(0xFF060D1A);
  static const Color bg2     = Color(0xFF0C1628);
  static const Color bg3     = Color(0xFF111E35);
  static const Color bg4     = Color(0xFF172444);
  static const Color text    = Color(0xFFE8F4F8);
  static const Color muted   = Color(0xFF6B8BAA);
  static const Color success = Color(0xFF00E08C);
  static const Color warning = Color(0xFFFFB830);
  static const Color danger  = Color(0xFFFF5C5C);

  // Séparateur entre deux adresses (récapitulatif trajet).
  static const Color divider    = Color(0xFF1E3050);
  static const Color ratingGold = Color(0xFFFFD700);

  // Contrepartie "mode clair" — chaque écran DEM Pro bascule sombre/clair via
  // sa propre classe `_T` locale ; ces valeurs étaient redéfinies à
  // l'identique dans plusieurs écrans (commentaire d'origine dans
  // dem_pro_batch_tracking_screen.dart : "calque DemProHomeScreen") au lieu
  // de pointer vers une seule source.
  static const Color lightBg      = Color(0xFFF8FAFC);
  static const Color lightCardBg2 = Color(0xFFF1F5F9);
  static const Color lightCardBg3 = Color(0xFFE8EFF6);
  static const Color lightBorder  = Color(0xFFE2E8F0);
  static const Color lightText    = Color(0xFF0F172A);
  static const Color lightMuted   = Color(0xFF64748B);

  // Dégradés "carte" en mode clair, dupliqués à l'identique dans
  // dem_pro_home_screen.dart (résumé ventes/livraisons + en-tête).
  static const List<Color> lightGradientBlue   = [Color(0xFFEFF6FF), Color(0xFFDCEFFB)];
  static const List<Color> lightGradientHeader = [Colors.white, Color(0xFFEFF6FF)];
}
