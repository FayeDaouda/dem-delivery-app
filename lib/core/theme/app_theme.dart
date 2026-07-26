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
  static const success     = Color(0xFF00C853);
  static const error       = Color(0xFFEF4444);
  static const warning     = Color(0xFFFFB300);
  static const online      = Color(0xFF4CAF50);
  static const offline     = Color(0xFF4A6080);

  // Accents sémantiques — reprennent des valeurs déjà en usage dispersées
  // dans les écrans (statuts de commande, note, SOS) pour leur donner un nom
  // au lieu d'un hex one-off répété à chaque écran.
  static const ratingGold   = Color(0xFFFFD700);
  static const sos          = Color(0xFFFF3D00);
  static const accentIndigo = Color(0xFF6366F1);
  static const accentMint   = Color(0xFF40F0C0);
  static const surge        = Color(0xFFFF9800); // badge multiplicateur tarifaire
  static const successBright = Color(0xFF69F0AE); // vert départ, plus visible que `success` sur fond dégradé
  static const accentCyan   = Color(0xFF00BCD4); // variante cyan distincte de `primary` (statut "payée")
  static const pending      = Color(0xFFF59E0B); // ambre "en attente/en cours de vérification" — distinct de `warning`/`surge`

  // Écrans "gestion" en thème clair (historique, profil, favoris) — palette
  // séparée du thème sombre ci-dessus, choix assumé (voir décisions produit).
  static const textDark    = Color(0xFF1A1A2E); // texte principal sur fond clair
  static const textMuted   = Color(0xFF7B8CA0); // texte secondaire sur fond clair
  static const lightBg     = Color(0xFFF4F6FA); // fond des écrans clairs
  static const lightBorder = Color(0xFFEEF0F5); // bordures/séparateurs sur fond clair
  static const lightFill      = Color(0xFFF1F5F9); // fond des champs/icônes sur fond clair
  static const lightIconMuted = Color(0xFFBCC5D0); // icônes discrètes (chevrons, états vides) sur fond clair
  static const successLight   = Color(0xFF22C55E); // vert "livrée"/succès sur fond clair — distinct de `success` (sombre)
  static const successLightBg = Color(0xFFE8F5E9); // fond teinté clair assorti à `successLight` (icônes/chips "terminé")

  // Accent spécifique au module livreur — tournées/routes (icône route,
  // badge tournée active, countdown offre de tournée).
  static const driverAccent     = Color(0xFF00AECB);
  static const driverAccentDone = Color(0xFF00E08C); // variante "terminé" de driverAccent (arrêt/tournée complétée)

  // Surface dédiée aux AlertDialog du module livreur (fond + texte muté) —
  // distincte de `surface`/`card` (utilisées pour les panneaux/carte), pas
  // une simple variante de style, un rôle à part (fond de boîte de dialogue).
  static const dialogSurface   = Color(0xFF0C1628);
  static const dialogTextMuted = Color(0xFF6B8BAA);

  // Gradient principal (splash, boutons)
  static const gradientSplash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C), Color(0xFF020822)],
    stops: [0.0, 0.35, 0.7, 1.0],
  );

  // Gradient CTA cyan (bouton principal) — était dupliqué avec deux paires de
  // teintes légèrement différentes (0xFF00D4FF/0xFF0099CC côté création de
  // commande, 0xFF00D2FF/0xFF0086C8 côté confirmation) pour le même type de
  // bouton d'action, à un écran d'intervalle. Unifié ici.
  static const gradientCta = LinearGradient(
    colors: [Color(0xFF00D4FF), Color(0xFF0099CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dégradé de dialogue/panneau (paiement, litige, stats...) — 3 teintes de
  // marque sans aller jusqu'au quasi-noir de `gradientSplash` (pas adapté à
  // une boîte de dialogue compacte). Trouvé dupliqué à l'identique dans
  // plusieurs écrans livreur.
  static const gradientDialog = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryMid, primaryDark],
  );
}

/// Échelle d'élévation partagée — avant ça, chaque écran définissait ses
/// propres `BoxShadow` avec des flous/opacités légèrement différents (6 à 20,
/// alpha 0.06 à 0.35...), ce qui donnait une hiérarchie visuelle incohérente
/// d'un écran à l'autre. Trois niveaux suffisent à couvrir tous les usages :
/// une carte posée sur la page, un élément flottant au-dessus, une feuille
/// modale qui se détache du fond.
class AppShadows {
  const AppShadows._();

  /// Cartes de contenu dans une liste ou une page (tuiles, cartes de
  /// commande, groupes de menu) — légèrement soulevées.
  static const card = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Boutons flottants, contrôles de carte, badges — nettement au-dessus du
  /// contenu, doivent rester lisibles sur une carte ou une image.
  static const floating = [
    BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// Bottom sheets et dialogues qui se détachent du fond de l'écran.
  static const modal = [
    BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, -4)),
  ];

  /// Halo teinté pour les boutons d'action en dégradé (CTA principal) — la
  /// couleur du bouton "irradie" légèrement au lieu d'une ombre neutre.
  static List<BoxShadow> tinted(Color color, {double alpha = 0.35, double blur = 12}) => [
    BoxShadow(color: color.withValues(alpha: alpha), blurRadius: blur, offset: const Offset(0, 4)),
  ];
}

/// Échelle d'espacement partagée — à utiliser dans les écrans touchés par
/// la passe de refonte UI en cours, plutôt que des valeurs magiques inline.
/// Pas de migration rétroactive du code existant.
class AppSpacing {
  const AppSpacing._();

  static const xs  = 4.0;
  static const s   = 8.0;
  static const m   = 12.0;
  static const l   = 16.0;
  static const xl  = 24.0;
  static const xxl = 32.0;
}

const _fontFamily = 'PlusJakartaSans';

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: _fontFamily,
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
