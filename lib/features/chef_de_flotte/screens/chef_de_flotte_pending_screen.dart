import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chef_de_flotte_repository.dart';
import '../../../core/utils/dem_layout.dart';

class ChefDeFlottePendingScreen extends StatefulWidget {
  const ChefDeFlottePendingScreen({super.key});
  @override
  State<ChefDeFlottePendingScreen> createState() => _State();
}

class _State extends State<ChefDeFlottePendingScreen> {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);

  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final s = await _repo.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _logout() async {
    await AuthStorage.clear();
    appStartupNotifier.markLoggedOut();
    if (mounted) context.go('/phone');
  }

  @override
  Widget build(BuildContext context) {
    final fleetSize = (_stats?['fleetSize'] as num?)?.toInt() ?? 0;
    final fleetMax = (_stats?['fleetMax'] as num?)?.toInt() ?? 10;
    final atLimit = fleetSize >= fleetMax;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: DemLayout.formMaxWidth(context),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Indicateur d'étape ─────────────────────────────────────
                  const _StepIndicator(
                    currentStep: 2,
                    totalSteps: 3,
                    label: 'En attente',
                  ),
                  const SizedBox(height: 32),

                  // ── Icône hourglass (cyan) ─────────────────────────────────
                  Builder(
                    builder: (ctx) {
                      final t = MediaQuery.of(ctx).size.width > 600;
                      return Container(
                        width: t ? 110.0 : 84.0,
                        height: t ? 110.0 : 84.0,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.18),
                              AppColors.primaryMid.withValues(alpha: 0.10),
                            ],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          color: AppColors.primaryMid,
                          size: t ? 52.0 : 42.0,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  Builder(
                    builder: (ctx) {
                      final t = MediaQuery.of(ctx).size.width > 600;
                      return Text(
                        'Dossier en cours de validation',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: t ? 26.0 : 22.0,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F2942),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Votre dossier a été soumis avec succès.\nL\'équipe DEM va le vérifier sous 24 à 48h.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Carte drivers ajoutés ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.group_outlined,
                            color: AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$fleetSize livreur${fleetSize != 1 ? 's' : ''} ajouté${fleetSize != 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: Color(0xFF0F2942),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Ils seront activés après validation de votre compte.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Alerte limite flotte ───────────────────────────────────
                  if (atLimit) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Limite atteinte : $fleetSize/$fleetMax livreurs. Vous pourrez demander une extension une fois votre compte validé.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ── Encart infos ───────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'En attendant, vous pouvez déjà :',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF0F2942),
                          ),
                        ),
                        SizedBox(height: 10),
                        _Bullet('Ajouter vos livreurs et leurs documents'),
                        _Bullet('Constituer votre flotte (jusqu\'à 10 motos)'),
                        _Bullet(
                          'Dès validation, ils seront activés automatiquement',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Bouton gradient ────────────────────────────────────────
                  _GradientButton(
                    label: 'Gérer mes livreurs',
                    icon: Icons.group_add_outlined,
                    onTap: () => context.push('/chef-de-flotte/dashboard'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _logout,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    child: const Text(
                      'Se déconnecter',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ), // SafeArea
        ), // ConstrainedBox
      ), // Center
    );
  }
}

// ── Indicateur d'étape ────────────────────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final String label;
  const _StepIndicator({
    required this.currentStep,
    required this.totalSteps,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.12),
          AppColors.primaryMid.withValues(alpha: 0.08),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryDark,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 1,
          height: 12,
          color: AppColors.primary.withValues(alpha: 0.35),
        ),
        const SizedBox(width: 8),
        Text(
          'Étape $currentStep/$totalSteps',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryMid.withValues(alpha: 0.85),
          ),
        ),
      ],
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
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '• ',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          ),
        ),
      ],
    ),
  );
}

// ── Bouton gradient ───────────────────────────────────────────────────────────
class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: DemLayout.isTablet(context) ? 56.0 : 52.0,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          AppColors.primary,
          AppColors.primaryMid,
          AppColors.primaryDark,
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.35),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
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
  );
}
