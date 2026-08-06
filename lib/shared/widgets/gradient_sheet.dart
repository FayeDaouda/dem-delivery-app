import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Feuille de bas d'écran au dégradé bleu DEM (fond flouté en verre dépoli en
/// option) — partagée entre les notifications livreur, la tournée batch et
/// les feuilles du profil, qui dessinaient chacune leur propre variante du
/// même conteneur.
class GradientSheet extends StatelessWidget {
  final Widget child;
  final bool blurred;
  final bool bordered;
  final double radius;
  final EdgeInsetsGeometry? padding;

  const GradientSheet({
    super.key,
    required this.child,
    this.blurred = true,
    this.bordered = true,
    this.radius = 28,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.vertical(top: Radius.circular(radius));
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        // Mêmes 3 couleurs que AppColors.gradientDialog — dupliquées en dur
        // ici jusqu'ici, avec le risque qu'une modification de l'une ne soit
        // pas répercutée sur l'autre.
        gradient: AppColors.gradientDialog,
        border: bordered
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.20),
                width: 0.8,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: child,
    );

    if (!blurred) return ClipRRect(borderRadius: borderRadius, child: content);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: content,
      ),
    );
  }
}

/// Poignée de glissement en haut d'une [GradientSheet].
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 4,
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.30),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}
