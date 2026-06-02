import 'package:flutter/material.dart';

/// Utilitaire de layout responsive pour DEM.
/// Breakpoint tablette : largeur > 600pt (iPad Air/Pro/mini en portrait).
class DemLayout {
  DemLayout._();

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width > 600;

  /// Largeur max du contenu des formulaires (auth, profil).
  /// Sur iPad, le formulaire est centré et limité à 520pt.
  static double formMaxWidth(BuildContext context) =>
      isTablet(context) ? 520.0 : double.infinity;

  /// Padding horizontal de page pour les formulaires.
  static EdgeInsets pagePadding(BuildContext context, {
    double mobile = 28,
    double tablet = 0,
  }) =>
      EdgeInsets.symmetric(horizontal: isTablet(context) ? tablet : mobile);

  /// Hauteurs du panel bas sur les écrans carte selon le step.
  static List<double> panelHeights(BuildContext context) =>
      isTablet(context)
          ? [210.0, 330.0, 400.0, 290.0]
          : [180.0, 290.0, 350.0, 250.0];

  /// Wrap un widget dans un Center + ConstrainedBox si on est sur tablette.
  /// Pratique pour les formulaires pleine largeur.
  static Widget constrain(BuildContext context, Widget child) {
    final max = formMaxWidth(context);
    if (max == double.infinity) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}
