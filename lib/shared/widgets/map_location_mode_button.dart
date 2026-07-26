import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/services/map_location_mode_controller.dart';
import '../../core/theme/app_theme.dart';
import 'pressable.dart';

/// Bouton rond à 3 états (libre / suivi / boussole) — même apparence et
/// même logique de cycle sur tous les écrans avec carte live, piloté par un
/// [MapLocationModeController].
class MapLocationModeButton extends StatelessWidget {
  const MapLocationModeButton({
    super.key,
    required this.mode,
    required this.compassBearing,
    required this.onTap,
    this.size = 52,
  });

  final MapLocationMode mode;
  final double compassBearing;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isFree = mode == MapLocationMode.free;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isFree ? AppColors.surface : AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(
            color: isFree ? AppColors.card : AppColors.primary,
            width: 1.5,
          ),
          boxShadow: isFree ? AppShadows.floating : AppShadows.tinted(AppColors.primary, alpha: 0.45),
        ),
        child: mode == MapLocationMode.compass
            ? Transform.rotate(
                angle: -compassBearing * pi / 180,
                child: Icon(Icons.navigation, color: Colors.white, size: size * 0.46),
              )
            : Icon(
                mode == MapLocationMode.follow ? Icons.navigation : Icons.navigation_outlined,
                color: isFree ? AppColors.primary : Colors.white,
                size: size * 0.46,
              ),
      ),
    );
  }
}
