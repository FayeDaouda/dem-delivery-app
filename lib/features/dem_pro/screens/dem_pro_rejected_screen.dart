import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/utils/dem_layout.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../../profile/data/profile_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.support_agent_outlined, color: AppColors.primary, size: 36),
              const SizedBox(height: 10),
              Text('Support DEM', style: ClientText.title.copyWith(fontSize: 17)),
              const SizedBox(height: 6),
              Text(
                'Besoin de précisions sur le refus de votre demande ?',
                style: ClientText.body.copyWith(color: AppColors.textMuted),
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Se déconnecter ?', style: ClientText.title.copyWith(color: AppColors.textDark)),
        content: Text(
          'Vous pourrez vous reconnecter avec le même numéro.',
          style: ClientText.body.copyWith(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: ClientText.body.copyWith(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Déconnexion', style: ClientText.body.copyWith(color: AppColors.error, fontWeight: FontWeight.w600)),
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
      backgroundColor: AppColors.lightBg,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: DemLayout.formMaxWidth(context)),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                              style: ClientText.micro.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w400, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 24),

                            Builder(builder: (ctx) {
                              final t = MediaQuery.of(ctx).size.width > 600;
                              return Container(
                                width: t ? 110.0 : 84.0, height: t ? 110.0 : 84.0,
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.cancel_outlined, color: AppColors.error, size: t ? 52.0 : 42.0),
                              );
                            }),
                            const SizedBox(height: 24),

                            Builder(builder: (ctx) {
                              final t = MediaQuery.of(ctx).size.width > 600;
                              return Text(
                                'Demande non retenue',
                                textAlign: TextAlign.center,
                                style: ClientText.headline.copyWith(color: AppColors.textDark, fontSize: t ? 26.0 : 22.0),
                              );
                            }),
                            const SizedBox(height: 10),
                            Text(
                              _businessName != null
                                  ? 'Le profil "$_businessName" n\'a pas été validé par notre équipe.'
                                  : 'Votre profil DEM Pro n\'a pas été validé par notre équipe.',
                              textAlign: TextAlign.center,
                              style: ClientText.subtitle.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w400, height: 1.5),
                            ),
                            const SizedBox(height: 24),

                            // ── Motif de refus ──────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
                              ),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Icon(Icons.info_outline, color: AppColors.error, size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Motif du refus',
                                    style: ClientText.subtitle.copyWith(color: AppColors.error, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(_rejectionReason ?? 'Non précisé',
                                    style: ClientText.body.copyWith(color: AppColors.error, height: 1.4)),
                                ])),
                              ]),
                            ),
                            const SizedBox(height: 24),

                            // ── Encart infos ─────────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
                              ),
                              child: Row(children: [
                                Icon(Icons.edit_outlined, color: AppColors.primary, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Corrigez les informations de votre profil entreprise et resoumettez votre demande.',
                                    style: ClientText.label.copyWith(color: AppColors.textDark, fontWeight: FontWeight.w400),
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
                                foregroundColor: AppColors.textMuted,
                                textStyle: ClientText.label.copyWith(fontWeight: FontWeight.w400),
                              ),
                            ),
                            const SizedBox(height: 4),

                            // ── Déconnexion ─────────────────────────────────
                            TextButton.icon(
                              onPressed: () => _confirmLogout(context),
                              icon: const Icon(Icons.logout, size: 15),
                              label: const Text('Se déconnecter'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.error,
                                textStyle: ClientText.label.copyWith(fontWeight: FontWeight.w400),
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

