import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../profile/providers/profile_provider.dart';

// ── Formateur plaque sénégalaise : "DK 1234 AB" ───────────────────────────────
// Accepte les formes : "DK1234AB", "DK 1234 AB", etc.
// Normalise : 2 lettres · espace · 1-4 chiffres · espace · 1-2 lettres
class _PlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // On garde uniquement lettres et chiffres, en majuscules
    final raw = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (raw.isEmpty) return newValue.copyWith(text: '');

    final buf = StringBuffer();
    int i = 0;

    // 1-2 lettres préfixe (ex: "DK")
    while (i < raw.length && i < 2 && RegExp(r'[A-Z]').hasMatch(raw[i])) {
      buf.write(raw[i++]);
    }
    // chiffres (max 4)
    if (i < raw.length) {
      final digits = StringBuffer();
      while (i < raw.length && digits.length < 4 && RegExp(r'\d').hasMatch(raw[i])) {
        digits.write(raw[i++]);
      }
      if (digits.isNotEmpty) { buf.write(' '); buf.write(digits); }
    }
    // lettres suffixe (max 2)
    if (i < raw.length) {
      final suffix = StringBuffer();
      while (i < raw.length && suffix.length < 2 && RegExp(r'[A-Z]').hasMatch(raw[i])) {
        suffix.write(raw[i++]);
      }
      if (suffix.isNotEmpty) { buf.write(' '); buf.write(suffix); }
    }

    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class DriverOnboardingScreen extends ConsumerStatefulWidget {
  final String vehicleType;
  const DriverOnboardingScreen({super.key, required this.vehicleType});

  @override
  ConsumerState<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends ConsumerState<DriverOnboardingScreen> {
  final _nameController  = TextEditingController();
  final _plateController = TextEditingController();
  bool    _loading   = false;
  String? _nameError;

  bool get _isMoto => widget.vehicleType == 'MOTO';

  @override
  void dispose() {
    _nameController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();

    // Validation inline
    if (name.isEmpty) {
      setState(() => _nameError = 'Entrez votre nom complet.');
      return;
    }
    if (name.split(' ').length < 2) {
      setState(() => _nameError = 'Prénom et nom requis (ex : Mamadou Diallo).');
      return;
    }

    setState(() { _loading = true; _nameError = null; });
    try {
      await ref.read(profileRepositoryProvider).completeOnboarding(
            name: name,
            vehiclePlate: _plateController.text.trim().replaceAll(' ', '').toUpperCase(),
          );
      await ref.read(profileProvider.notifier).fetchProfile();
      if (!mounted) return;
      _isMoto ? context.go('/driver/home') : context.go('/driver/thiak/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                        color: Colors.white, size: 36,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isMoto ? 'DEM Livraison' : 'DEM Thiak Thiak',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w700, letterSpacing: 1,
                      ),
                    ),
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
                        color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ces informations seront visibles par vos clients',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // ── Nom complet ──
                    _InputLabel('Nom complet *'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Ex : Mamadou Diallo',
                        prefixIcon: const Icon(Icons.person_outline, color: AppColors.textSecondary, size: 20),
                        errorText: _nameError,
                        errorStyle: const TextStyle(fontSize: 12),
                      ),
                      onChanged: (_) {
                        if (_nameError != null) setState(() => _nameError = null);
                      },
                    ),
                    const SizedBox(height: 20),

                    // ── Plaque ──
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
                      inputFormatters: [_PlateFormatter()],
                      decoration: InputDecoration(
                        hintText: _isMoto ? 'Ex : DK 1234 AB' : 'Ex : DK 5678 CD',
                        prefixIcon: Icon(
                          _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                          color: AppColors.textSecondary, size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    GradientButton(label: 'Commencer', loading: _loading, onTap: _submit),

                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Vous pourrez compléter votre profil plus tard',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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

class _InputLabel extends StatelessWidget {
  final String text;
  const _InputLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary, fontSize: 12,
        fontWeight: FontWeight.w600, letterSpacing: 0.5,
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
      width: 10, height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.primary : active ? Colors.white : Colors.white.withValues(alpha: 0.3),
        border: active ? Border.all(color: Colors.white, width: 2) : null,
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28, height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.3),
    );
  }
}
