import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/dem_layout.dart';

/// Bouton CTA plein/contour standard de l'espace DEM Pro — remplace les
/// implémentations dupliquées à l'identique dans plusieurs écrans
/// (`dem_pro_rejected_screen.dart`, `dem_pro_pending_screen.dart`,
/// `dem_pro_onboarding_screen.dart`, `dem_pro_batch_confirmation_screen.dart`).
class DemProButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool loading;
  final Color color;

  /// Quand true : fond transparent + bordure/texte dans [color] au lieu
  /// d'un fond plein — utilisé pour l'action secondaire d'un couple de
  /// boutons (ex: "Retour au tableau de bord" à côté de "Voir le suivi").
  final bool outlined;

  const DemProButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.loading = false,
    this.color = AppColors.primary,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = outlined ? color : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: DemLayout.isTablet(context) ? 56.0 : 52.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(14),
          border: outlined ? Border.all(color: color.withValues(alpha: 0.4)) : null,
          boxShadow: outlined
              ? null
              : [BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: loading ? null : onTap,
            child: Center(
              child: loading
                  ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: foreground, strokeWidth: 2))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: foreground, size: 20),
                          const SizedBox(width: 10),
                        ],
                        Text(label, style: ClientText.button.copyWith(color: foreground)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
