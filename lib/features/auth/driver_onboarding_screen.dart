import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/api_client.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';

class DriverOnboardingScreen extends StatefulWidget {
  final String vehicleType; // 'MOTO' ou 'TAXI'
  const DriverOnboardingScreen({super.key, required this.vehicleType});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  final _nameController = TextEditingController();
  final _plateController = TextEditingController();
  bool _loading = false;

  bool get _isMoto => widget.vehicleType == 'MOTO';

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrez votre nom complet.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await ApiClient.dio.post('/users/driver/onboarding', data: {
        'name': name,
        'vehicleType': widget.vehicleType,
        if (_plateController.text.trim().isNotEmpty)
          'vehiclePlate': _plateController.text.trim().toUpperCase(),
      });

      // Sauvegarder le profil mis à jour
      final user = response.data['user'] as Map<String, dynamic>;
      await AuthStorage.saveUser(user);

      if (!mounted) return;
      _isMoto ? context.go('/driver/home') : context.go('/driver/thiak/home');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ── Header gradient ──
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Icône véhicule
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isMoto ? 'DEM Livraison' : 'DEM Thiak Thiak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    // Indicateur d'étapes
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepDot(active: false, done: true),
                        _StepLine(),
                        _StepDot(active: false, done: true),
                        _StepLine(),
                        _StepDot(active: true, done: false),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // ── Carte ──
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Votre profil',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ces informations seront visibles par vos clients',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // Nom complet
                    _InputLabel('Nom complet *'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Ex : Mamadou Diallo',
                        prefixIcon: Icon(Icons.person_outline,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Plaque d'immatriculation
                    _InputLabel(_isMoto ? 'Plaque moto' : 'Plaque véhicule'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _plateController,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: _isMoto ? 'Ex : DK 1234 AB' : 'Ex : DK 5678 CD',
                        prefixIcon: Icon(
                          _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Bouton
                    _GradientButton(
                      label: 'Commencer',
                      loading: _loading,
                      onTap: _submit,
                    ),

                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Vous pourrez compléter votre profil plus tard',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets internes ──

class _InputLabel extends StatelessWidget {
  final String text;
  const _InputLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  const _StepDot({required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? AppColors.primary
            : active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.3),
        border: active ? Border.all(color: Colors.white, width: 2) : null,
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.3),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _GradientButton({required this.label, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          gradient: loading
              ? const LinearGradient(colors: [AppColors.card, AppColors.card])
              : const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryMid, AppColors.primaryDark],
                ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  height: 22, width: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
