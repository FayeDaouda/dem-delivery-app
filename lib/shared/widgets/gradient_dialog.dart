import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';

/// Boîte de dialogue au dégradé cyan DEM (`AppColors.gradientDialog`) — même
/// habillage que les feuilles de paiement, pour ne plus avoir de popups au
/// fond blanc/gris par défaut qui détonnent avec le reste de l'app.
Widget _shell({required Widget child}) {
  return Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Container(
      decoration: BoxDecoration(
        gradient: AppColors.gradientDialog,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: child,
    ),
  );
}

/// Dialogue d'information — une icône, un titre, un message, un seul bouton
/// d'action. Pour les notifications qui interrompent (course/arrêt annulé…).
Future<void> showGradientInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  required VoidCallback onAction,
  IconData icon = Icons.info_outline,
  Color iconColor = Colors.white,
  bool barrierDismissible = false,
}) {
  return showDialog(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogCtx) => _shell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: ClientText.subtitle.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                onAction();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Dialogue de confirmation — titre, message, deux boutons (rester/agir).
/// Retourne `true` si l'utilisateur a confirmé l'action, `false`/`null` sinon.
Future<bool?> showGradientConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Annuler',
  required String confirmLabel,
  Color confirmColor = AppColors.error,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogCtx) => _shell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, textAlign: TextAlign.center, style: ClientText.subtitle.copyWith(color: Colors.white)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(cancelLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: confirmColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
