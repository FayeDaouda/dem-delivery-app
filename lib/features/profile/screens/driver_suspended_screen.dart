import '../../../core/router/app_startup_notifier.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_repository.dart';
import '../../../core/utils/dem_layout.dart';

class DriverSuspendedScreen extends StatefulWidget {
  const DriverSuspendedScreen({super.key});
  @override
  State<DriverSuspendedScreen> createState() => _State();
}

class _State extends State<DriverSuspendedScreen> {
  String? _suspensionReason;
  bool    _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await ProfileRepository().getMe();
      if (mounted) setState(() {
        _suspensionReason = user['suspensionReason'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  Future<void> _contactSupport() async {
    final phone = '+221710064664';
    final wa    = '221710064664';
    final msg   = Uri.encodeComponent(
      'Bonjour, mon compte livreur DEM a été suspendu. Je souhaite obtenir des informations sur la réactivation.',
    );

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(
              width: 36, height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 20),
            const Text('Contacter le support',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Notre équipe peut vous aider à réactiver votre compte.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13, height: 1.4),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            _contactTile(
              icon: Icons.phone_rounded, color: const Color(0xFF22C55E),
              label: 'Appeler le support', sub: phone,
              onTap: () async {
                final uri = Uri.parse('tel:$phone');
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
            ),
            const SizedBox(height: 10),
            _contactTile(
              icon: Icons.chat_rounded, color: const Color(0xFF25D366),
              label: 'WhatsApp support', sub: 'Message pré-rempli',
              onTap: () async {
                final uri = Uri.parse('https://wa.me/$wa?text=$msg');
                if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon, required Color color,
    required String label, required String sub,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
        ])),
        Icon(Icons.arrow_forward_ios, color: color.withValues(alpha: 0.60), size: 14),
      ]),
    ),
  );

  Future<void> _logout() async {
    await AuthStorage.clear();
    appStartupNotifier.markLoggedOut();
    if (mounted) context.go('/phone');
  }

  @override
  Widget build(BuildContext context) {
    final parts = _suspensionReason?.split('\n') ?? [];
    final motif = parts.isNotEmpty ? parts[0] : null;
    final fix   = parts.length > 1 ? parts.sublist(1).join('\n') : null;
    final t = DemLayout.isTablet(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: DemLayout.formMaxWidth(context)),
          child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                          width: t ? 90.0 : 72.0, height: t ? 90.0 : 72.0,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.block_rounded, color: Colors.white, size: t ? 44.0 : 36.0),
                        ),
                        const SizedBox(height: 14),
                        Text('Compte suspendu',
                            style: TextStyle(color: Colors.white, fontSize: t ? 26.0 : 22.0, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Votre accès livreur est temporairement suspendu',
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
                            body: 'Votre compte a été suspendu par un administrateur. Contactez le support pour plus d\'informations.',
                          ),
                          const SizedBox(height: 16),
                        ],

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
                            const Text('Contactez le support DEM pour accélérer la réactivation de votre compte.',
                                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4)),
                            const SizedBox(height: 12),
                            _GradientButton(
                              label: 'Contacter le support',
                              icon: Icons.support_agent_outlined,
                              onTap: _contactSupport,
                            ),
                          ]),
                        ),

                        const SizedBox(height: 28),

                        // Rafraîchir
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
            ),          // Column
        ),          // ConstrainedBox
      ),            // Center
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
        Text(body, style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87)),
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
