import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';

const _kFaq = [
  (
    'Comment recevoir des courses ?',
    'Passez le bouton "Hors ligne" sur "En ligne" depuis l\'accueil. Vous '
        'recevrez alors des propositions de courses à proximité, à '
        'accepter ou refuser dans le délai affiché.',
  ),
  (
    'Comment fonctionne la passe journalière ?',
    'Une passe payante donne accès au dispatch pour la journée. Le solde '
        'restant et le temps avant expiration sont visibles depuis le '
        'Portefeuille.',
  ),
  (
    'Pourquoi dois-je uploader des documents ?',
    'Permis, carte grise, assurance et photo profil sont obligatoires '
        'pour être vérifié. Après 3 courses sans dossier complet, un '
        'délai de 72h est accordé avant suspension automatique du compte.',
  ),
  (
    'Un document a été refusé, que faire ?',
    'L\'écran Documents affiche le motif exact du refus sur la pièce '
        'concernée (photo illisible, document expiré...). Renvoyez '
        'uniquement ce document — les autres restent valides.',
  ),
  (
    'Comment retirer mon solde ?',
    'Depuis le Portefeuille, "Retirer" vers Wave ou Orange Money. Le '
        'montant ne peut pas dépasser votre solde retirable (l\'argent '
        'réellement collecté par DEM, hors espèces en poche).',
  ),
  (
    'Comment fonctionnent les badges ?',
    'Chaque badge (Xarit, Mbokk, Door Warr...) débloque des avantages en '
        'fonction du nombre de courses, de parrainages et de votre note '
        'moyenne. Le détail est visible sur votre profil.',
  ),
];

/// Écran Aide/FAQ livreur — adapté de la version client (settings_screen.dart),
/// n'existait pas du tout côté livreur jusqu'ici.
class DriverSettingsScreen extends StatefulWidget {
  const DriverSettingsScreen({super.key});

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
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
