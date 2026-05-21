import '../../../core/router/app_startup_notifier.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../../profile/data/profile_repository.dart';

class ChefDeFlotteSuspendedScreen extends StatefulWidget {
  const ChefDeFlotteSuspendedScreen({super.key});
  @override
  State<ChefDeFlotteSuspendedScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteSuspendedScreen> {
  String? _suspensionReason;
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await ProfileRepository().getMe();
      if (mounted) {
        setState(() {
          _suspensionReason = user['suspensionReason'] as String?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = friendlyError(e); });
    }
  }

  Future<void> _logout() async {
    await AuthStorage.clear();
    appStartupNotifier.markLoggedOut();
    if (mounted) { context.go('/phone'); }
  }

  @override
  Widget build(BuildContext context) {
    final parts = _suspensionReason?.split('\n') ?? [];
    final motif = parts.isNotEmpty ? parts[0] : null;
    final fix   = parts.length > 1 ? parts.sublist(1).join('\n') : null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? NetworkErrorWidget(
                  message: _error!,
                  onRetry: () { setState(() { _loading = true; _error = null; }); _load(); },
                )
              : Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      child: Column(children: [
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.block_rounded, color: Colors.white, size: 36),
                        ),
                        const SizedBox(height: 14),
                        const Text('Espace suspendu',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Votre espace chef de flotte est temporairement suspendu',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                            textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Motif
                        if (motif != null) ...[
                          _InfoCard(
                            icon: Icons.warning_amber_rounded,
                            iconColor: Colors.orange.shade700,
                            bgColor: Colors.orange.shade50,
                            borderColor: Colors.orange.shade200,
                            title: 'Motif de suspension',
                            body: motif,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Correction
                        if (fix != null) ...[
                          _InfoCard(
                            icon: Icons.check_circle_outline,
                            iconColor: Colors.green.shade700,
                            bgColor: Colors.green.shade50,
                            borderColor: Colors.green.shade200,
                            title: 'Comment régulariser',
                            body: fix.replaceFirst('À corriger : ', ''),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (motif == null && fix == null) ...[
                          _InfoCard(
                            icon: Icons.info_outline,
                            iconColor: AppColors.primaryMid,
                            bgColor: AppColors.primary.withValues(alpha: 0.06),
                            borderColor: AppColors.primary.withValues(alpha: 0.20),
                            title: 'Compte suspendu',
                            body: 'Votre espace chef de flotte a été suspendu. Votre flotte de livreurs est également suspendue jusqu\'à réactivation.',
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Note flotte
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.people_outline, color: Colors.red.shade400, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              'Tous vos livreurs sont également suspendus tant que votre compte n\'est pas réactivé.',
                              style: TextStyle(fontSize: 12, color: Colors.red.shade600, height: 1.4),
                            )),
                          ]),
                        ),
                        const SizedBox(height: 20),

                        // Contact support
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Besoin d\'aide ?',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 4),
                            const Text('Contactez le support DEM pour accélérer la réactivation de votre espace.',
                                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4)),
                            const SizedBox(height: 12),
                            _GradientButton(
                              label: 'Contacter le support',
                              icon: Icons.support_agent_outlined,
                              onTap: () {},
                            ),
                          ]),
                        ),

                        const SizedBox(height: 28),

                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Vérifier le statut'),
                          onPressed: () { setState(() => _loading = true); _load(); },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryMid,
                            side: const BorderSide(color: AppColors.primaryMid),
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                        const SizedBox(height: 12),

                        TextButton(
                          onPressed: _logout,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey,
                            minimumSize: const Size(double.infinity, 44),
                          ),
                          child: const Text('Se déconnecter', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor, bgColor, borderColor;
  final String title, body;
  const _InfoCard({
    required this.icon, required this.iconColor,
    required this.bgColor, required this.borderColor,
    required this.title, required this.body,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: borderColor),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: iconColor, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: iconColor)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
      ])),
    ]),
  );
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GradientButton({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.primary, AppColors.primaryMid, AppColors.primaryDark],
        begin: Alignment.centerLeft, end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
    ),
  );
}
