import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/map_theme_provider.dart';
import 'pressable.dart';

/// Bouton rond qui bascule le thème de la carte (jour/nuit) — même
/// apparence sur tous les écrans avec carte pour un contrôle reconnaissable.
///
/// [onTap] est laissé à la charge de l'écran hôte (plutôt que de basculer
/// [mapNightProvider] directement ici) car chaque écran recharge lui-même
/// le style de carte (asset JSON jour/nuit) après le changement.
class MapThemeToggleButton extends ConsumerWidget {
  const MapThemeToggleButton({super.key, required this.onTap, this.size = 52});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNight = ref.watch(mapNightProvider);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.card, width: 1.5),
          boxShadow: AppShadows.floating,
        ),
        child: Icon(
          isNight ? Icons.wb_sunny_outlined : Icons.nightlight_round,
          color: isNight ? AppColors.warning : AppColors.primary,
          size: size * 0.46,
        ),
      ),
    );
  }
}
