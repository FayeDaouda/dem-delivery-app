import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/utils/dem_layout.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../../profile/data/profile_repository.dart';
import '../theme/dem_pro_colors.dart';
import '../theme/dem_pro_text.dart';
import '../widgets/dem_pro_button.dart';
import '../widgets/dem_pro_support_tile.dart';

class DemProRejectedScreen extends StatefulWidget {
  const DemProRejectedScreen({super.key});
  @override
  State<DemProRejectedScreen> createState() => _State();
}

class _State extends State<DemProRejectedScreen> {
  final _profileRepo = ProfileRepository();

  String? _businessName;
  String? _rejectionReason;
  bool    _loading    = true;
  bool    _loadFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _profileRepo.getMe();
      if (!mounted) return;
      setState(() {
        _businessName    = user['proBusinessName'] as String?;
        _rejectionReason = user['rejectionReason'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _loadFailed = true; _error = friendlyError(e); });
    }
  }

  void _showSupport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DemProColors.bg2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.support_agent_outlined, color: DemProColors.accent, size: 36),
              const SizedBox(height: 10),
              Text('Support DEM', style: DemProText.title.copyWith(fontSize: 17)),
              const SizedBox(height: 6),
              Text(
                'Besoin de précisions sur le refus de votre demande ?',
                style: DemProText.body.copyWith(color: DemProColors.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              DemProSupportTile(
                icon: Icons.phone_outlined,
                label: 'Appeler le support',
                sub: '+221 71 006 46 64',
                onTap: () { Navigator.pop(context); launchUrl(Uri.parse('tel:+221710064664')); },
              ),
              const SizedBox(height: 10),
              DemProSupportTile(
                icon: Icons.chat_bubble_outline,
                label: 'WhatsApp',
                sub: '+221 71 006 46 64',
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse('https://wa.me/221710064664?text=${Uri.encodeComponent("Bonjour, ma demande DEM Pro a été refusée. Je souhaite obtenir plus de détails.")}'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              const SizedBox(height: 10),
              DemProSupportTile(
                icon: Icons.email_outlined,
                label: 'Envoyer un e-mail',
                sub: 'support@dem.sn',
                onTap: () { Navigator.pop(context); launchUrl(Uri.parse('mailto:support@dem.sn')); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DemProColors.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Se déconnecter ?', style: DemProText.title),
        content: Text(
          'Vous pourrez vous reconnecter avec le même numéro.',
          style: DemProText.body.copyWith(color: DemProColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: DemProText.body.copyWith(color: DemProColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Déconnexion', style: DemProText.body.copyWith(color: DemProColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AuthStorage.clear();
    if (!mounted) return;
    if (this.context.mounted) this.context.go('/phone');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DemProColors.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: DemLayout.formMaxWidth(context)),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: DemProColors.accent))
              : _loadFailed
                  ? NetworkErrorWidget(
                      message: _error!,
                      onRetry: () { setState(() { _loading = true; _loadFailed = false; _error = null; }); _loadProfile(); },
                    )
                  : SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ── Logo DEM ────────────────────────────────────
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset('assets/DEM.png', width: 56, height: 56, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'delivery express mobility',
                              style: DemProText.micro.copyWith(color: DemProColors.muted, fontWeight: FontWeight.w400, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 24),

                            Builder(builder: (ctx) {
                              final t = MediaQuery.of(ctx).size.width > 600;
                              return Container(
                                width: t ? 110.0 : 84.0, height: t ? 110.0 : 84.0,
                                decoration: BoxDecoration(
                                  color: DemProColors.danger.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.cancel_outlined, color: DemProColors.danger, size: t ? 52.0 : 42.0),
                              );
                            }),
                            const SizedBox(height: 24),

                            Builder(builder: (ctx) {
                              final t = MediaQuery.of(ctx).size.width > 600;
                              return Text(
                                'Demande non retenue',
                                textAlign: TextAlign.center,
                                style: DemProText.headline.copyWith(color: DemProColors.text, fontSize: t ? 26.0 : 22.0),
                              );
                            }),
                            const SizedBox(height: 10),
                            Text(
                              _businessName != null
                                  ? 'Le profil "$_businessName" n\'a pas été validé par notre équipe.'
                                  : 'Votre profil DEM Pro n\'a pas été validé par notre équipe.',
                              textAlign: TextAlign.center,
                              style: DemProText.subtitle.copyWith(color: DemProColors.muted, fontWeight: FontWeight.w400, height: 1.5),
                            ),
                            const SizedBox(height: 24),

                            // ── Motif de refus ──────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: DemProColors.danger.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: DemProColors.danger.withValues(alpha: 0.25)),
                              ),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.info_outline, color: DemProColors.danger, size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Motif du refus',
                                    style: DemProText.subtitle.copyWith(color: DemProColors.danger, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(_rejectionReason ?? 'Non précisé',
                                    style: DemProText.body.copyWith(color: DemProColors.danger, height: 1.4)),
                                ])),
                              ]),
                            ),
                            const SizedBox(height: 24),

                            // ── Encart infos ─────────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: DemProColors.accent.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: DemProColors.accent.withValues(alpha: 0.20)),
                              ),
                              child: Row(children: [
                                Icon(Icons.edit_outlined, color: DemProColors.accent, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Corrigez les informations de votre profil entreprise et resoumettez votre demande.',
                                    style: DemProText.caption.copyWith(color: DemProColors.text, fontWeight: FontWeight.w400),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 28),

                            DemProButton(
                              label: 'Modifier ma demande',
                              icon: Icons.edit_outlined,
                              onTap: () => context.go('/dem-pro/onboarding'),
                            ),
                            const SizedBox(height: 16),

                            // ── Support ─────────────────────────────────────
                            TextButton.icon(
                              onPressed: () => _showSupport(context),
                              icon: const Icon(Icons.help_outline, size: 15),
                              label: const Text('Besoin d\'aide ? Contacter le support'),
                              style: TextButton.styleFrom(
                                foregroundColor: DemProColors.muted,
                                textStyle: DemProText.caption.copyWith(fontWeight: FontWeight.w400),
                              ),
                            ),
                            const SizedBox(height: 4),

                            // ── Déconnexion ─────────────────────────────────
                            TextButton.icon(
                              onPressed: () => _confirmLogout(context),
                              icon: const Icon(Icons.logout, size: 15),
                              label: const Text('Se déconnecter'),
                              style: TextButton.styleFrom(
                                foregroundColor: DemProColors.danger,
                                textStyle: DemProText.caption.copyWith(fontWeight: FontWeight.w400),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}

