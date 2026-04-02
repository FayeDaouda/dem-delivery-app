import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../core/theme/app_theme.dart';
import 'auth_service.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';
  bool _loading = false;
  bool _resending = false;

  Future<void> _verifyOtp() async {
    if (_code.length < 4) return;
    setState(() => _loading = true);
    try {
      final data = await AuthService.verifyOtp(phone: widget.phone, code: _code);
      if (!mounted) return;

      final user = data['user'] as Map<String, dynamic>;
      final isNew = data['isNew'] as bool;

      if (isNew) {
        // Nouveau compte → choisir son rôle
        context.go('/role-selection');
        return;
      }

      _navigateByRole(user);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code invalide ou expiré. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateByRole(Map<String, dynamic> user) {
    final role = user['role'] as String;
    final vehicleType = user['vehicleType'] as String?;

    if (role == 'DRIVER' && vehicleType == 'TAXI') {
      context.go('/driver/thiak/home');
    } else if (role == 'DRIVER') {
      context.go('/driver/home');
    } else {
      context.go('/client/home');
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    await AuthService.sendOtp(widget.phone);
    if (mounted) {
      setState(() => _resending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code renvoyé !')),
      );
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                          ),
                          const Spacer(),
                          Text(
                            '+221 ${widget.phone}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 32),
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
                      'Vérification',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Code envoyé au +221 ${widget.phone}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 36),
                    PinCodeTextField(
                      appContext: context,
                      length: 4,
                      keyboardType: TextInputType.number,
                      animationType: AnimationType.scale,
                      pinTheme: PinTheme(
                        shape: PinCodeFieldShape.box,
                        borderRadius: BorderRadius.circular(14),
                        fieldHeight: 68,
                        fieldWidth: 68,
                        activeFillColor: AppColors.card,
                        inactiveFillColor: AppColors.card,
                        selectedFillColor: AppColors.card,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.card,
                        selectedColor: AppColors.primary,
                      ),
                      enableActiveFill: true,
                      textStyle: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700),
                      onChanged: (val) => _code = val,
                      onCompleted: (_) => _verifyOtp(),
                    ),
                    const SizedBox(height: 32),
                    _GradientButton(label: 'Valider', loading: _loading, onTap: _verifyOtp),
                    const SizedBox(height: 20),
                    Center(
                      child: _resending
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(
                              onPressed: _resend,
                              child: const Text('Renvoyer le code',
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
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
                  colors: [AppColors.primary, AppColors.primaryMid, AppColors.primaryDark]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: loading
              ? const SizedBox(height: 22, width: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
