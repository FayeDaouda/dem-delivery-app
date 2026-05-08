import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';

class ClientOnboardingScreen extends ConsumerStatefulWidget {
  const ClientOnboardingScreen({super.key});

  @override
  ConsumerState<ClientOnboardingScreen> createState() => _ClientOnboardingScreenState();
}

class _ClientOnboardingScreenState extends ConsumerState<ClientOnboardingScreen> {
  final _nameController   = TextEditingController();
  final _refCodeController = TextEditingController();
  bool    _loading   = false;
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _refCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Entrez votre prénom et nom.');
      return;
    }
    if (name.split(' ').length < 2) {
      setState(() => _nameError = 'Prénom et nom requis (ex : Fatou Diallo).');
      return;
    }

    setState(() { _loading = true; _nameError = null; });
    try {
      final code = _refCodeController.text.trim().toUpperCase();
      final response = await ApiClient.dio.post('/users/client/onboarding', data: {
        'name': name,
        if (code.isNotEmpty) 'usedReferralCode': code,
      });
      final user = response.data['user'] as Map<String, dynamic>;
      await AuthStorage.saveUser(user);
      if (!mounted) return;
      context.go('/client/home');
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
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Image.asset('assets/DEM.png', width: 56, height: 56),
                const SizedBox(height: 32),
                const Text(
                  'Comment vous\nappelle-t-on ?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Votre nom sera visible par le livreur.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 15),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.name,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Ex : Fatou Diallo',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                    errorText: _nameError,
                    errorStyle: const TextStyle(color: Color(0xFFFFCDD2)),
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFFFCDD2)),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFFFCDD2), width: 1.5),
                    ),
                  ),
                  onChanged: (_) { if (_nameError != null) setState(() => _nameError = null); },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _refCodeController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 1.5),
                  decoration: InputDecoration(
                    hintText: 'Code de parrainage (optionnel)',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 13, letterSpacing: 0),
                    prefixIcon: const Icon(Icons.card_giftcard_outlined, color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                          )
                        : const Text('Continuer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
