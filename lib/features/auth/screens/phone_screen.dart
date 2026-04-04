import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../providers/auth_provider.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 8) return;
    try {
      await ref.read(authProvider.notifier).sendOtp(phone);
      if (mounted) context.push('/otp', extra: {'phone': phone});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authProvider).isLoading;

    return Scaffold(
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Image.asset('assets/DEM.png', width: 80, height: 80),
                    const SizedBox(height: 10),
                    const Text(
                      'DELIVERY · EXPRESS · MOBILITY',
                      style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 2.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
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
                    const Text('Bienvenue 👋',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('Entrez votre numéro pour continuer',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    const SizedBox(height: 32),
                    const Text('Numéro de téléphone',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
                          child: const Text('+221',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(hintText: '77 123 45 67'),
                            onSubmitted: (_) => _sendOtp(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    GradientButton(label: 'Continuer', loading: loading, onTap: _sendOtp),
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
