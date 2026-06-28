import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/utils/dem_layout.dart';
import '../theme/dem_pro_colors.dart';

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
      backgroundColor: Colors.white,
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
                            DemProColors.accent.withValues(alpha: 0.18),
                            DemProColors.accent.withValues(alpha: 0.06),
                          ]),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          color: DemProColors.accent,
                          size: isTablet ? 50.0 : 40.0,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Titre ──────────────────────────────────────────
                      Text(
                        'Votre profil DEM Pro\nest en cours d\'examen',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isTablet ? 24.0 : 20.0,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F2942),
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Votre demande a été envoyée avec succès.\nNotre équipe l\'examinera sous 24 à 48h.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF6B7280),
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_active_outlined, color: DemProColors.accent, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Vous serez notifié dès que votre demande sera traitée.',
                            style: TextStyle(fontSize: 12, color: DemProColors.accent, fontWeight: FontWeight.w600),
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
                          color: DemProColors.accent.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: DemProColors.accent.withValues(alpha: 0.18)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Une fois validé, vous pourrez :',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: Color(0xFF0F2942),
                              ),
                            ),
                            SizedBox(height: 10),
                            _Bullet('Commander vos livraisons en quelques tapotements'),
                            _Bullet('Suivre vos dépenses et votre activité'),
                            _Bullet('Gérer vos adresses de départ favorites'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Bouton actualiser ──────────────────────────────
                      _RefreshButton(loading: _refreshing, onTap: _refresh),

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
                                      color: Color(0xFF10B981),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _checkedText!,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xFF6B7280),
                                      ),
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
                          foregroundColor: const Color(0xFF9CA3AF),
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ── Déconnexion ──────────────────────────────────
                      TextButton.icon(
                        onPressed: () => _confirmLogout(context),
                        icon: const Icon(Icons.logout, size: 15),
                        label: const Text('Se déconnecter'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          textStyle: const TextStyle(fontSize: 12.5),
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
              const Text('Support DEM', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Pour toute question sur votre demande DEM Pro',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _SupportOption(
                icon: Icons.phone_outlined,
                label: 'Appeler le support',
                sub: '+221 71 006 46 64',
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(Uri.parse('tel:+221710064664'));
                },
              ),
              const SizedBox(height: 10),
              _SupportOption(
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
              _SupportOption(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Se déconnecter ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Vous pourrez vous reconnecter avec le même numéro.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Déconnexion', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
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
      const Text(
        'delivery express mobility',
        style: TextStyle(
          fontSize: 10,
          color: Color(0xFF9CA3AF),
          letterSpacing: 0.5,
        ),
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
        DemProColors.accent.withValues(alpha: 0.12),
        DemProColors.accent.withValues(alpha: 0.06),
      ]),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: DemProColors.accent.withValues(alpha: 0.30)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(color: DemProColors.accent, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F2942),
          letterSpacing: 0.3,
        ),
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
          child: Container(height: 2, color: DemProColors.accent),
        ),
      ),
      const _TimelineStep(label: 'En examen', active: true),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 15),
          child: Container(height: 2, color: const Color(0xFFE5E7EB)),
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
              ? DemProColors.accent
              : active
                  ? DemProColors.accent.withValues(alpha: 0.12)
                  : const Color(0xFFF3F4F6),
          shape: BoxShape.circle,
          border: Border.all(
            color: (done || active) ? DemProColors.accent : const Color(0xFFE5E7EB),
            width: active ? 2 : 1,
          ),
        ),
        child: Center(
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : active
                  ? const _PulsingDot()
                  : const Icon(Icons.circle_outlined, color: Color(0xFFD1D5DB), size: 12),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: (done || active) ? FontWeight.w600 : FontWeight.w400,
          color: (done || active) ? const Color(0xFF0F2942) : const Color(0xFF9CA3AF),
        ),
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
      decoration: const BoxDecoration(color: DemProColors.accent, shape: BoxShape.circle),
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
      const Text('• ', style: TextStyle(color: DemProColors.accent, fontWeight: FontWeight.w700)),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
    ]),
  );
}

// ── Bouton actualiser ─────────────────────────────────────────────────────────

class _RefreshButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _RefreshButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: DemLayout.isTablet(context) ? 56.0 : 52.0,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: DemProColors.accent,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: DemProColors.accent.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Actualiser le statut',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
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

// ── Tile support ─────────────────────────────────────────────────────────────

class _SupportOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _SupportOption({required this.icon, required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF8FAFC),
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
              Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
              Text(sub, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ],
          )),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFD1D5DB)),
        ]),
      ),
    ),
  );
}
