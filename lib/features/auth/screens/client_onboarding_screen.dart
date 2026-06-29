import '../../../core/error/app_exception.dart';
import '../../../core/utils/dem_layout.dart';
import '../../../core/utils/input_formatters.dart';
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
    FocusScope.of(context).unfocus();
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet  = DemLayout.isTablet(context);
    final logoSize  = isTablet ? 72.0 : 56.0;
    final titleFS   = isTablet ? 32.0 : 28.0;
    final btnHeight = isTablet ? 56.0 : 52.0;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: DemLayout.formMaxWidth(context)),
          child: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bouton retour
                Semantics(
                  label: 'Retour',
                  button: true,
                  child: GestureDetector(
                    onTap: () => context.go('/role-selection'),
                    child: Container(
                      width: isTablet ? 52.0 : 48.0,
                      height: isTablet ? 52.0 : 48.0,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  child: Image.asset('assets/DEM.png', width: logoSize, height: logoSize),
                ),
                const SizedBox(height: 32),
                Text(
                  'Entrez votre nom complet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleFS,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ces informations seront visibles par les livreurs.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 15),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.name,
                  inputFormatters: [NameInputFormatter()],
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Ex : Fatou Ndiaye',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
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
                    hintText: 'Si vous avez un code de parrainage, renseignez-le ici',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 12, letterSpacing: 0),
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
                  height: btnHeight,
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
                const SizedBox(height: 16),
                Text(
                  'Vous devrez télécharger les pièces justificatives de ces informations plus tard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),            // Container
        ),          // ConstrainedBox
      ),            // Center
    );
  }
}
