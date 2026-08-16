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

/// Écran Paramètres/Aide. Historique : n'existait pas du tout au départ (ni
/// FAQ, ni page "À propos"). Une 1ère passe a ajouté la FAQ + les liens
/// légaux + la version — cette 2e passe fusionne le contact support ici
/// (jusque-là seulement accessible depuis une bulle séparée sur le profil,
/// deux endroits différents pour "j'ai besoin d'aide" — pas cohérent) et
/// ajoute une recherche + une ouverture animée sur la FAQ.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _version;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
    final filteredFaq = _query.isEmpty
        ? _kFaq
        : _kFaq
              .where(
                (f) =>
                    f.$1.toLowerCase().contains(_query) ||
                    f.$2.toLowerCase().contains(_query),
              )
              .toList();

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
                // Recherche — filtre la FAQ en direct, plutôt que de
                // laisser l'utilisateur défiler 6 questions pour trouver
                // la sienne (chaque écran d'aide "pro" en propose une).
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppShadows.card,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Rechercher dans la FAQ…',
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13.5,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textMuted,
                                size: 18,
                              ),
                              onPressed: _searchCtrl.clear,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (filteredFaq.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_off_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aucune question ne correspond à "${_searchCtrl.text.trim()}".',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < filteredFaq.length; i++) ...[
                          _FaqTile(
                            question: filteredFaq[i].$1,
                            answer: filteredFaq[i].$2,
                          ),
                          if (i < filteredFaq.length - 1)
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
                  'Besoin d\'aide supplémentaire ?',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Notre équipe support répond directement.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
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
                      _SupportTile(
                        icon: Icons.phone_rounded,
                        color: AppColors.success,
                        label: 'Appeler le support',
                        subtitle: AppConfig.supportPhone,
                        onTap: () => _launch('tel:${AppConfig.supportPhone}'),
                      ),
                      const Divider(height: 1, color: AppColors.lightBorder),
                      _SupportTile(
                        icon: Icons.chat_rounded,
                        color: const Color(0xFF25D366),
                        label: 'WhatsApp',
                        subtitle: AppConfig.supportPhone,
                        onTap: () => _launch(
                          'https://wa.me/${AppConfig.supportWhatsapp}',
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.lightBorder),
                      _SupportTile(
                        icon: Icons.email_rounded,
                        color: AppColors.primary,
                        label: 'Envoyer un e-mail',
                        subtitle: AppConfig.supportEmail,
                        onTap: () =>
                            _launch('mailto:${AppConfig.supportEmail}'),
                      ),
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
                // Rotation animée (au lieu d'un simple échange d'icône
                // instantané) — un détail, mais c'est exactement ce genre
                // de micro-transition qui distingue une FAQ "premium" d'une
                // FAQ générique.
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.expand_more,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
            // AnimatedSize (au lieu d'un `if` sec) — la réponse se déplie
            // en douceur au lieu d'apparaître d'un coup.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.answer,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tuile "contacter le support" — variante claire de SupportContactTile
/// (celle-ci est pensée pour un fond sombre, utilisée sur le profil) : même
/// idée (icône colorée en cercle + libellé + sous-titre + chevron) mais
/// réhabillée pour rester cohérente avec le reste de cet écran, en clair.
class _SupportTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _SupportTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
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
