import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Bouton retour flottant — même style que côté DEM Pro
/// (_buildFloatingBackButton, dem_pro_order_create_screen.dart /
/// dem_pro_batch_create_screen.dart) : cercle blanc, icône colorée, ombre.
/// Remplace le mode jour/nuit de la carte sur les écrans de commande (le
/// toggle a migré vers Réglages, voir mapNightProvider) — plus visible
/// qu'une icône noyée dans la barre du haut.
class FloatingBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const FloatingBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.arrow_back, color: AppColors.primary, size: 22),
      ),
    );
  }
}
