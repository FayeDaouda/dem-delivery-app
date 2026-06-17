import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dem_layout.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../../profile/data/profile_repository.dart';
import '../theme/dem_pro_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                            Builder(builder: (ctx) {
                              final t = MediaQuery.of(ctx).size.width > 600;
                              return Container(
                                width: t ? 110.0 : 84.0, height: t ? 110.0 : 84.0,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF5C5C).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.cancel_outlined, color: const Color(0xFFFF5C5C), size: t ? 52.0 : 42.0),
                              );
                            }),
                            const SizedBox(height: 24),

                            Builder(builder: (ctx) {
                              final t = MediaQuery.of(ctx).size.width > 600;
                              return Text(
                                'Demande non retenue',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: t ? 26.0 : 22.0, fontWeight: FontWeight.w800, color: const Color(0xFF0F2942)),
                              );
                            }),
                            const SizedBox(height: 10),
                            Text(
                              _businessName != null
                                  ? 'Le profil "$_businessName" n\'a pas été validé par notre équipe.'
                                  : 'Votre profil DEM Pro n\'a pas été validé par notre équipe.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
                            ),
                            const SizedBox(height: 24),

                            // ── Motif de refus ──────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Icon(Icons.info_outline, color: Colors.red.shade600, size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Motif du refus',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.red.shade700)),
                                  const SizedBox(height: 4),
                                  Text(_rejectionReason ?? 'Non précisé',
                                    style: TextStyle(fontSize: 13, color: Colors.red.shade600, height: 1.4)),
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
                                const Expanded(
                                  child: Text(
                                    'Corrigez les informations de votre profil entreprise et resoumettez votre demande.',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF0F2942)),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 28),

                            _GradientButton(
                              label: 'Modifier ma demande',
                              icon: Icons.edit_outlined,
                              onTap: () => context.go('/dem-pro/onboarding'),
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

// ── Bouton ────────────────────────────────────────────────────────────────────
class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GradientButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: DemLayout.isTablet(context) ? 56.0 : 52.0,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.primary, AppColors.primaryMid, AppColors.primaryDark],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ),
      ),
    ),
  );
}
