import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// En-tête d'un flux de commande à étapes (retour, titre, progression) —
/// partagé entre "Livraison simple/Express" et "Livraison groupée" pour
/// garder le même repère visuel tout au long de l'app.
class WizardTopBar extends StatelessWidget {
  final String title;
  final int step;
  final int stepCount;
  final VoidCallback onBack;
  const WizardTopBar({
    super.key,
    required this.title,
    required this.step,
    required this.onBack,
    this.stepCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: AppColors.gradientSplash,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.textPrimary,
                size: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          // Compteur texte — ne pas reposer uniquement sur la couleur des
          // points pour indiquer la progression (peu lisible en plein
          // soleil sur mobile).
          Text(
            '${step + 1}/$stepCount',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Row(
            children: List.generate(
              stepCount,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(left: 4),
                width: i == step ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == step ? AppColors.primary : AppColors.card,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
