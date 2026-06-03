import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';

class ReferralCard extends StatelessWidget {
  final String? referralCode;

  const ReferralCard({super.key, required this.referralCode});

  String get _shareMessage =>
      'Rejoins DEM — livraison à moto à Dakar ! 🚀\n'
      'Utilise mon code *${referralCode ?? ''}* à l\'inscription '
      'et profite de l\'offre de lancement.\n'
      'Télécharge l\'app : https://dem.sn';

  Future<void> _copy(BuildContext context) async {
    if (referralCode == null) return;
    await Clipboard.setData(ClipboardData(text: referralCode!));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('Code copié !', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareWhatsApp() async {
    final encoded = Uri.encodeComponent(_shareMessage);
    final uri = Uri.parse('whatsapp://send?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = referralCode ?? '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // En-tête cyan
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              gradient: AppColors.gradientSplash,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(children: [
              Icon(Icons.people_alt_outlined, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Mon code parrainage',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ]),
          ),

          // Corps
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Code mis en valeur
                GestureDetector(
                  onTap: () => _copy(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.30),
                          width: 1.5),
                    ),
                    child: Column(children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          code.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Appuyer pour copier',
                        style: TextStyle(
                            color: AppColors.primary.withValues(alpha: 0.60),
                            fontSize: 11),
                      ),
                    ]),
                  ),
                ),

                const SizedBox(height: 12),

                // Boutons
                Row(children: [
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.copy_rounded,
                      label: 'Copier',
                      color: AppColors.primary,
                      onTap: () => _copy(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.chat_rounded,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: _shareWhatsApp,
                    ),
                  ),
                ]),

                const SizedBox(height: 10),

                // Info
                Row(children: [
                  Icon(Icons.info_outline,
                      size: 13, color: AppColors.primary.withValues(alpha: 0.55)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Chaque personne inscrite avec votre code vous rapproche du badge suivant.',
                      style: TextStyle(
                          color: const Color(0xFF7B8CA0).withValues(alpha: 0.85),
                          fontSize: 11,
                          height: 1.4),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}
