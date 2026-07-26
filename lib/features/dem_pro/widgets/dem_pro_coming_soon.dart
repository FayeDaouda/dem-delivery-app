import 'package:flutter/material.dart';
import '../theme/dem_pro_colors.dart';
import '../theme/dem_pro_text.dart';

/// Placeholder "Bientôt disponible" pour les onglets de l'espace DEM Pro
/// pas encore implémentés (Livraisons, Adresses, Finances...).
class DemProComingSoon extends StatelessWidget {
  final String title;
  final IconData icon;
  const DemProComingSoon({super.key, required this.title, this.icon = Icons.construction_outlined});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DemProColors.bg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84, height: 84,
              decoration: const BoxDecoration(color: DemProColors.bg3, shape: BoxShape.circle),
              child: Icon(icon, color: DemProColors.accent, size: 36),
            ),
            const SizedBox(height: 20),
            Text(title, style: DemProText.title.copyWith(color: DemProColors.text, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Bientôt disponible', style: DemProText.body.copyWith(color: DemProColors.muted)),
          ],
        ),
      ),
    );
  }
}
