import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Bouton flottant rond au-dessus de la carte (recentrage GPS, etc.) —
/// partagé entre "Livraison simple/Express" et "Livraison groupée".
class FloatingMapButton extends StatelessWidget {
  final IconData? icon;
  final bool loading;
  final VoidCallback onTap;
  const FloatingMapButton({
    super.key,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8),
          ],
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }
}
