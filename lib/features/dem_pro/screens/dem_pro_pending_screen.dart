import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/utils/dem_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../widgets/dem_pro_button.dart';
import '../widgets/dem_pro_support_tile.dart';

class DemProPendingScreen extends StatefulWidget {
  const DemProPendingScreen({super.key});
  @override
  State<DemProPendingScreen> createState() => _State();
}

class _State extends State<DemProPendingScreen> {
  bool    _refreshing  = false;
  String? _checkedText;

  Future<void> _refresh() async {
    setState(() { _refreshing = true; _checkedText = null; });
    await appStartupNotifier.refreshProStatus();
    if (!mounted) return;
    setState(() => _refreshing = false);

    final dest = appStartupNotifier.homeForRole;
    if (dest != '/dem-pro/pending') {
      context.go(dest);
    } else {
      final now = TimeOfDay.now();
      final h = now.hour.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      setState(() => _checkedText = 'Vérifié à $h:$m · Toujours en cours');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = DemLayout.isTablet(context);
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) => SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                  maxWidth: DemLayout.formMaxWidth(ctx),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      // ── Logo DEM arrondi + tagline ─────────────────────
                      const _DemLogo(),
                      const SizedBox(height: 28),

                      // ── Badge statut ───────────────────────────────────
                      const _StepBadge(label: 'En attente de validation'),
                      const SizedBox(height: 28),

                      // ── Icône sablier ──────────────────────────────────
                      Container(
                        width: isTablet ? 100.0 : 80.0,
                        height: isTablet ? 100.0 : 80.0,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AppColors.primary.withValues(alpha: 0.18),
                            AppColors.primary.withValues(alpha: 0.06),
                          ]),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          color: AppColors.primary,
                          size: isTablet ? 50.0 : 40.0,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Titre ──────────────────────────────────────────
                      Text(
                        'Votre profil DEM Pro\nest en cours d\'examen',
                        textAlign: TextAlign.center,
                        style: ClientText.headline.copyWith(color: AppColors.textDark, fontSize: isTablet ? 24.0 : 20.0, height: 1.25),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Votre demande a été envoyée avec succès.\nNotre équipe l\'examinera sous 24 à 48h.',
                        textAlign: TextAlign.center,
                        style: ClientText.body.copyWith(color: AppColors.textMuted, height: 1.55),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_active_outlined, color: AppColors.primary, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Vous serez notifié dès que votre demande sera traitée.',
                            style: ClientText.label.copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // ── Timeline 3 étapes ──────────────────────────────
                      const _Timeline(),
                      const SizedBox(height: 24),

                      // ── Card avantages ─────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Une fois validé, vous pourrez :',
                              style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
                            ),
                            const SizedBox(height: 10),
                            const _Bullet('Commander vos livraisons en quelques tapotements'),
                            const _Bullet('Suivre vos dépenses et votre activité'),
                            const _Bullet('Gérer vos adresses de départ favorites'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Bouton actualiser ──────────────────────────────
                      DemProButton(
                        label: 'Actualiser le statut',
                        icon: Icons.refresh_rounded,
                        loading: _refreshing,
                        onTap: _refresh,
                      ),

                      // ── Feedback inline après refresh ──────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _checkedText != null
                            ? Padding(
                                key: ValueKey(_checkedText),
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      color: AppColors.successLight,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _checkedText!,
                                      style: ClientText.label.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w400),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 16),

                      // ── Lien support ───────────────────────────────────
                      TextButton.icon(
                        onPressed: () => _showSupportDialog(context),
                        icon: const Icon(Icons.help_outline, size: 15),
                        label: const Text('Besoin d\'aide ? Contacter le support'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                          textStyle: ClientText.label.copyWith(fontWeight: FontWeight.w400),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ── Déconnexion ──────────────────────────────────
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
        ),
      ),
    );
  }

  void _showSupportDialog(BuildContext context) {
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
                'Pour toute question sur votre demande DEM Pro',
                style: ClientText.body.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              DemProSupportTile(
                icon: Icons.phone_outlined,
                label: 'Appeler le support',
                sub: '+221 71 006 46 64',
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(Uri.parse('tel:+221710064664'));
                },
              ),
              const SizedBox(height: 10),
              DemProSupportTile(
                icon: Icons.chat_bubble_outline,
                label: 'WhatsApp',
                sub: '+221 71 006 46 64',
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse('https://wa.me/221710064664?text=${Uri.encodeComponent("Bonjour, j'ai une question concernant ma demande DEM Pro.")}'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              const SizedBox(height: 10),
              DemProSupportTile(
                icon: Icons.email_outlined,
                label: 'Envoyer un e-mail',
                sub: 'support@dem.sn',
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(Uri.parse('mailto:support@dem.sn'));
                },
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
}

// ── Logo DEM ──────────────────────────────────────────────────────────────────

class _DemLogo extends StatelessWidget {
  const _DemLogo();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset('assets/DEM.png', width: 56, height: 56, fit: BoxFit.cover),
      ),
      const SizedBox(height: 6),
      Text(
        'delivery express mobility',
        style: ClientText.micro.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w400, letterSpacing: 0.5),
      ),
    ],
  );
}

// ── Badge statut ──────────────────────────────────────────────────────────────

class _StepBadge extends StatelessWidget {
  final String label;
  const _StepBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        AppColors.primary.withValues(alpha: 0.12),
        AppColors.primary.withValues(alpha: 0.06),
      ]),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: ClientText.label.copyWith(color: AppColors.textDark, fontWeight: FontWeight.w700, letterSpacing: 0.3),
      ),
    ]),
  );
}

// ── Timeline ──────────────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  const _Timeline();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _TimelineStep(label: 'Envoyé', done: true),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 15),
          child: Container(height: 2, color: AppColors.primary),
        ),
      ),
      const _TimelineStep(label: 'En examen', active: true),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 15),
          child: Container(height: 2, color: AppColors.lightBorder),
        ),
      ),
      const _TimelineStep(label: 'Validé'),
    ],
  );
}

class _TimelineStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;
  const _TimelineStep({required this.label, this.done = false, this.active = false});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: done
              ? AppColors.primary
              : active
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.lightFill,
          shape: BoxShape.circle,
          border: Border.all(
            color: (done || active) ? AppColors.primary : AppColors.lightBorder,
            width: active ? 2 : 1,
          ),
        ),
        child: Center(
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : active
                  ? const _PulsingDot()
                  : const Icon(Icons.circle_outlined, color: AppColors.textMuted, size: 12),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: ClientText.label.copyWith(fontWeight: (done || active) ? FontWeight.w600 : FontWeight.w400, color: (done || active) ? AppColors.textDark : AppColors.textMuted),
      ),
    ],
  );
}

// ── Point pulsant pour l'étape active ────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 10, height: 10,
      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
    ),
  );
}

// ── Puce ──────────────────────────────────────────────────────────────────────

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('• ', style: ClientText.bodyStrong.copyWith(color: AppColors.primary)),
      Expanded(child: Text(text, style: ClientText.body.copyWith(color: AppColors.textMuted))),
    ]),
  );
}

