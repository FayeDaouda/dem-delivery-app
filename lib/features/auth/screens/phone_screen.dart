import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../providers/auth_provider.dart';

// ── Formateur : "77 123 45 67" (max 9 chiffres) ──────────────────────────────
class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped  = digits.length > 9 ? digits.substring(0, 9) : digits;
    final buf     = StringBuffer();

    for (int i = 0; i < capped.length; i++) {
      if (i == 2 || i == 5 || i == 7) buf.write(' ');
      buf.write(capped[i]);
    }

    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneController = TextEditingController();
  final _focusNode       = FocusNode();

  // Nombre de chiffres réels (sans espaces de format)
  int get _digitCount => _phoneController.text.replaceAll(' ', '').length;
  bool get _canContinue => _digitCount >= 8;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_canContinue) return;
    // On envoie le numéro brut (sans espaces) au backend
    final phone = _phoneController.text.replaceAll(' ', '').trim();
    _focusNode.unfocus();
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
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final keyboardUp = MediaQuery.viewInsetsOf(ctx).bottom > 50;

              return SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Logo — disparaît proprement quand clavier s'ouvre ──
                      AnimatedSize(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: keyboardUp ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 220),
                          child: SizedBox(
                            height: keyboardUp ? 0 : null,
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.center,
                                  child: GestureDetector(
                                    onLongPress: () => context.push('/admin/login'),
                                    child: Image.asset('assets/DEM.png', width: 72, height: 72),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Center(
                                  child: Text(
                                    'DELIVERY · EXPRESS · MOBILITY',
                                    style: TextStyle(
                                      color: Colors.white70, fontSize: 10,
                                      letterSpacing: 2.5, fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ── Titre ──
                      const Text(
                        'Bienvenue 👋',
                        style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Entrez votre numéro pour continuer',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                      const SizedBox(height: 28),

                      // ── Label ──
                      const Text(
                        'Numéro de téléphone',
                        style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12,
                          fontWeight: FontWeight.w600, letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Champ ──
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                            ),
                            child: const Text(
                              '+221',
                              style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _phoneController,
                              focusNode: _focusNode,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [_PhoneFormatter()],
                              style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: '77 123 45 67',
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                                ),
                              ),
                              onSubmitted: (_) => _sendOtp(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // ── Bouton — désactivé tant que < 8 chiffres ──
                      GradientButton(
                        label: 'Continuer',
                        loading: loading,
                        enabled: _canContinue,
                        onTap: _sendOtp,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
