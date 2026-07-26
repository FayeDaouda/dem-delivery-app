import 'package:flutter/material.dart';

/// Échelle typographique partagée côté client (accueil, création, suivi,
/// historique, profil, adresses favorites, suivi invité) — remplace les
/// `TextStyle` ad-hoc dispersés écran par écran par un jeu de styles nommés
/// et cohérents, dérivé des tailles/graisses réellement utilisées dans le
/// module. Ne fixe pas de couleur par défaut (chaque écran l'applique via
/// `.copyWith(color: ...)` selon son thème sombre ou clair).
class ClientText {
  ClientText._();

  static const micro = TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3);
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
  static const label = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const labelStrong = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const bodyStrong = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
  static const subtitle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  /// Titre de feuille/dialogue (sheets et Dialog côté livreur) — distinct de
  /// `subtitle` (16) et `title` (18), trouvé répété à l'identique dans
  /// plusieurs sheets/dialogues du profil livreur.
  static const sheetTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);
  static const title = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
  static const headline = TextStyle(fontSize: 24, fontWeight: FontWeight.w800);
  static const hero = TextStyle(fontSize: 28, fontWeight: FontWeight.w800);
  static const button = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
}
