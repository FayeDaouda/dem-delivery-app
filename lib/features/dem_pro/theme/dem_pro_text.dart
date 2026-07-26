import 'package:flutter/material.dart';
import 'dem_pro_colors.dart';

/// Échelle typographique DEM Pro — un jeu réduit de styles nommés à utiliser
/// partout dans le module plutôt que des `TextStyle(fontSize: ..., fontWeight: ...)`
/// ad hoc. Utiliser `.copyWith(color: ...)` quand la couleur par défaut ne
/// convient pas au contexte (accent, danger, succès...).
class DemProText {
  DemProText._();

  /// Badge/label minuscule (ex: compteur d'étape, tag de statut compact).
  static const TextStyle micro = TextStyle(
    fontSize: 10, fontWeight: FontWeight.w700, color: DemProColors.muted, letterSpacing: 0.2,
  );

  /// Légende / info secondaire (adresse, sous-titre, horodatage).
  static const TextStyle caption = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600, color: DemProColors.muted,
  );

  /// Corps de texte standard (labels de champ, description, hint).
  static const TextStyle body = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w500, color: DemProColors.text,
  );

  /// Corps de texte accentué (valeurs, noms, montants secondaires).
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w700, color: DemProColors.text,
  );

  /// Sous-titre de section (ex: "Type de colis", "Mes adresses").
  static const TextStyle subtitle = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w700, color: DemProColors.text,
  );

  /// Titre d'écran ou de carte importante.
  static const TextStyle title = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w800, color: DemProColors.text,
  );

  /// Titre pleine page (en-tête d'écran, message d'état).
  static const TextStyle headline = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w800, color: DemProColors.text,
  );

  /// Chiffre hero (prix total, montant principal).
  static const TextStyle hero = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w900, color: DemProColors.accent, letterSpacing: -0.5,
  );

  /// Libellé de bouton.
  static const TextStyle button = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
  );
}
