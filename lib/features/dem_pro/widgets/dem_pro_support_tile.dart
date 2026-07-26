import 'package:flutter/material.dart';
import '../theme/dem_pro_colors.dart';
import '../theme/dem_pro_text.dart';

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
    color: DemProColors.bg3,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, color: DemProColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: DemProText.bodyStrong.copyWith(color: DemProColors.text)),
              Text(sub, style: DemProText.caption.copyWith(color: DemProColors.muted, fontWeight: FontWeight.w400)),
            ],
          )),
          const Icon(Icons.arrow_forward_ios, size: 14, color: DemProColors.muted),
        ]),
      ),
    ),
  );
}
