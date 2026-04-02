import 'package:flutter/material.dart';

class AppColors {
  // Palette officielle DEM
  static const primary     = Color(0xFF0CB8DE);  // Bleu clair principal
  static const primaryMid  = Color(0xFF0671BA);  // Bleu moyen
  static const primaryDark = Color(0xFF04317C);  // Bleu foncé
  static const background  = Color(0xFF020822);  // Bleu très foncé (quasi noir)
  static const surface     = Color(0xFF0A1535);
  static const card        = Color(0xFF0E1F4A);
  static const textPrimary = Color(0xFFFEFEFE);
  static const textSecondary = Color(0xFF8AAFD4);
  static const success     = Color(0xFF4CAF50);
  static const error       = Color(0xFFE53935);
  static const online      = Color(0xFF4CAF50);
  static const offline     = Color(0xFF4A6080);

  // Gradient principal (splash, boutons)
  static const gradientSplash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C), Color(0xFF020822)],
    stops: [0.0, 0.35, 0.7, 1.0],
  );
}

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    surface: AppColors.surface,
    error: AppColors.error,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.background,
      minimumSize: const Size(double.infinity, 54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.card,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
    hintStyle: const TextStyle(color: AppColors.textSecondary),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    centerTitle: true,
  ),
);
