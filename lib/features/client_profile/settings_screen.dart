import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';

const _kFaq = [
  (
    'Comment passer une commande ?',
    'Depuis l\'accueil, choisissez Simple, Express ou Groupée, indiquez '
        'les adresses de départ et de destination, puis validez. Un '
        'livreur est recherché automatiquement.',
  ),
  (
    'Comment payer ma commande ?',
    'Par défaut, le paiement se fait en espèces à la livraison. Vous '
        'pouvez aussi payer en ligne (Wave, Orange Money) une fois la '
        'commande acceptée par un livreur, depuis l\'écran de suivi.',
  ),
  (
    'Puis-je annuler une commande ?',
    'Oui, tant qu\'aucun livreur ne l\'a acceptée. Après acceptation, '
        'l\'annulation reste possible pendant une courte fenêtre depuis '
        'l\'écran de suivi.',
  ),
  (
    'Quelle est la différence entre Simple, Express et Groupée ?',
    'Simple : tarif standard. Express : livraison prioritaire (livreur '
        'le plus proche), +40% du tarif. Groupée : plusieurs destinations '
        'en une seule tournée, -20% sur le total.',
  ),
  (
    'Le livreur n\'a pas encore accepté ma commande, que faire ?',
    'La recherche continue automatiquement. Si aucun livreur n\'est '
        'trouvé après plusieurs minutes, vous pouvez continuer d\'attendre '
        'ou annuler depuis l\'écran de confirmation.',
  ),
  (
    'Comment fonctionne le parrainage ?',
    'Partagez votre code depuis votre profil. Chaque personne qui '
        's\'inscrit avec vous rapproche du badge suivant.',
  ),
];

/// Écran Paramètres/Aide — n'existait pas du tout jusqu'ici (ni FAQ, ni
/// page "À propos" avec la version de l'app, nulle part dans le parcours
/// client). Les liens CGU/Politique de confidentialité restent aussi
/// disponibles depuis le profil — pas de suppression, juste un second accès.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {}
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Paramètres & aide',
                      style: ClientText.subtitle.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                const Text(
                  'Questions fréquentes',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _kFaq.length; i++) ...[
                        _FaqTile(question: _kFaq[i].$1, answer: _kFaq[i].$2),
                        if (i < _kFaq.length - 1)
                          const Divider(
                            height: 1,
                            color: AppColors.lightBorder,
                          ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                const Text(
                  'Informations',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    children: [
                      _InfoTile(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Politique de confidentialité',
                        onTap: () => _launch(AppConfig.privacyPolicyUrl),
                      ),
                      const Divider(height: 1, color: AppColors.lightBorder),
                      _InfoTile(
                        icon: Icons.description_outlined,
                        label: 'Conditions générales d\'utilisation',
                        onTap: () => _launch(AppConfig.termsUrl),
                      ),
                      const Divider(height: 1, color: AppColors.lightBorder),
                      _InfoTile(
                        icon: Icons.info_outline,
                        label: 'Version de l\'application',
                        trailing: _version ?? '…',
                        onTap: null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.question,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textMuted,
                  size: 20,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Text(
                widget.answer,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;
  const _InfoTile({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 13.5,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                ),
              )
            else if (onTap != null)
              const Icon(
                Icons.chevron_right,
                color: AppColors.lightIconMuted,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
