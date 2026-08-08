import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';

/// Tile de contact support (téléphone / WhatsApp / e-mail) — remplace les
/// implémentations dupliquées à l'identique dans plusieurs écrans DEM Pro
/// (`dem_pro_rejected_screen.dart`, `dem_pro_pending_screen.dart`).
class DemProSupportTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const DemProSupportTile({super.key, required this.icon, required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.lightFill,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ClientText.bodyStrong.copyWith(color: AppColors.textDark)),
              Text(sub, style: ClientText.label.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w400)),
            ],
          )),
          const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
        ]),
      ),
    ),
  );
}
