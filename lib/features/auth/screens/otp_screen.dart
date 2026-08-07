import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/error/app_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dem_layout.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../providers/auth_provider.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _code     = '';
  bool   _hasError = false;

  // ── Compte à rebours renvoyer ──────────────────────────────────────────────
  static const _resendDelay = 60;
  int    _secondsLeft = _resendDelay;
  Timer? _resendTimer;
  bool   _resending   = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _resendTimer?.cancel();
    setState(() => _secondsLeft = _resendDelay);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  // ── Vérification OTP ───────────────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    if (_code.length < 6 || ref.read(authProvider).isLoading) return;
    setState(() => _hasError = false);
    try {
      final data = await ref.read(authProvider.notifier).verifyOtp(
            phone: widget.phone,
            code: _code,
          );
      if (!mounted) return;
      _navigate(data);
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _navigate(Map<String, dynamic> data) {
    final user  = data['user'] as Map<String, dynamic>;
    final isNew = data['isNew'] as bool;

    if (isNew) {
      // Nouvel utilisateur : pas encore de rôle — on ne peut pas markLoggedIn
      // Le rôle sera défini dans RoleSelectionScreen puis markLoggedIn sera appelé
      context.go('/role-selection');
      return;
    }

    final role            = user['role'] as String;
    final vehicleType     = user['vehicleType'] as String?;
    final isActive        = user['isActive'] as bool? ?? true;
    final chefStatus      = user['chefDeFlotteStatus'] as String?;
    final proStatus       = user['proStatus'] as String?;
    final proBusinessName = user['proBusinessName'] as String?;

    // Notifie le router que l'utilisateur est connecté → évite les redirects erronés
    appStartupNotifier.markLoggedIn(
      userRole: role,
      vehicle:  vehicleType,
      active:   isActive,
      chef:     chefStatus,
      pro:      proStatus,
      proDone:  proBusinessName?.isNotEmpty ?? false,
    );

    if (role == 'DRIVER') {
      if (!isActive) { context.go('/driver/suspended'); return; }
      context.go('/driver/home');
    } else if (role == 'CHEF_DE_FLOTTE') {
      if (!isActive) { context.go('/chef-de-flotte/suspended'); return; }
      if (chefStatus == 'ACTIVE')        { context.go('/chef-de-flotte/dashboard'); }
      else if (chefStatus == 'PENDING')  { context.go('/chef-de-flotte/pending'); }
      else if (chefStatus == 'REJECTED') { context.go('/chef-de-flotte/rejected'); }
      else                               { context.go('/chef-de-flotte/onboarding'); }
    } else if (role == 'DEM_PRO') {
      context.go(appStartupNotifier.homeForRole);
    } else {
      context.go('/client/home');
    }
  }

  // ── Renvoyer ───────────────────────────────────────────────────────────────
  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() { _resending = true; _hasError = false; });
    try {
      await ref.read(authProvider.notifier).sendOtp(widget.phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code renvoyé !')),
        );
        _startTimer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
    if (mounted) setState(() => _resending = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final loading         = ref.watch(authProvider).isLoading;
    final canResend       = _secondsLeft == 0 && !_resending;
    final errorColor      = const Color(0xFFEF4444);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final isTablet = DemLayout.isTablet(ctx);
              return SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  isTablet ? 0 : 28, 20, isTablet ? 0 : 28, 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 44,
                    maxWidth: DemLayout.formMaxWidth(ctx),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 28 : 0),
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [

                      // ── Barre retour ──
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                              ),
                              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                            ),
                            child: Text(
                              widget.phone,
                              style: const TextStyle(
                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),

                      // ── Icône cadenas ──
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: isTablet ? 90.0 : 72.0,
                        height: isTablet ? 90.0 : 72.0,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _hasError
                                ? [errorColor.withValues(alpha: 0.40), errorColor.withValues(alpha: 0.20)]
                                : [
                                    Colors.white.withValues(alpha: 0.25),
                                    Colors.white.withValues(alpha: 0.10),
                                  ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _hasError
                                ? errorColor.withValues(alpha: 0.80)
                                : Colors.white.withValues(alpha: 0.40),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          _hasError ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                          color: Colors.white, size: isTablet ? 40.0 : 32.0,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Titre ──
                      Text(
                        'Vérification',
                        style: TextStyle(
                          color: Colors.white, fontSize: isTablet ? 32.0 : 28.0,
                          fontWeight: FontWeight.w800, letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Code envoyé au ${widget.phone}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 36),

                      // ── Cases OTP ──
                      PinCodeTextField(
                        appContext: context,
                        length: 6,
                        keyboardType: TextInputType.number,
                        animationType: AnimationType.scale,
                        animationDuration: const Duration(milliseconds: 150),
                        backgroundColor: Colors.transparent,
                        pinTheme: PinTheme(
                          shape: PinCodeFieldShape.box,
                          borderRadius: BorderRadius.circular(14),
                          fieldHeight: isTablet ? 72.0 : 58.0,
                          fieldWidth:  isTablet ? 60.0 : 48.0,
                          activeFillColor: _hasError
                              ? errorColor.withValues(alpha: 0.20)
                              : Colors.white.withValues(alpha: 0.20),
                          inactiveFillColor: _hasError
                              ? errorColor.withValues(alpha: 0.10)
                              : Colors.white.withValues(alpha: 0.08),
                          selectedFillColor: Colors.white.withValues(alpha: 0.25),
                          activeColor: _hasError
                              ? errorColor.withValues(alpha: 0.80)
                              : Colors.white.withValues(alpha: 0.60),
                          inactiveColor: _hasError
                              ? errorColor.withValues(alpha: 0.50)
                              : Colors.white.withValues(alpha: 0.25),
                          selectedColor: Colors.white,
                          errorBorderColor: errorColor,
                          borderWidth: 1.5,
                        ),
                        enableActiveFill: true,
                        cursorColor: Colors.white,
                        textStyle: TextStyle(
                          color: Colors.white, fontSize: isTablet ? 32.0 : 28.0, fontWeight: FontWeight.w700,
                        ),
                        onChanged: (val) {
                          _code = val;
                          if (_hasError) setState(() => _hasError = false);
                        },
                        onCompleted: (_) => _verifyOtp(),
                      ),

                      // ── Message d'erreur sous les cases ──
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _hasError
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, color: errorColor, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Code incorrect. Vérifiez et réessayez.',
                                      style: TextStyle(
                                        color: errorColor, fontSize: 12, fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 28),

                      // ── Bouton Valider ──
                      GradientButton(
                        label: 'Valider',
                        loading: loading,
                        enabled: _code.length == 6 && !_hasError,
                        onTap: _verifyOtp,
                      ),
                      const SizedBox(height: 20),

                      // ── Renvoyer avec compte à rebours ──
                      Center(
                        child: _resending
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : TextButton(
                                onPressed: canResend ? _resend : null,
                                child: RichText(
                                  text: TextSpan(
                                    text: 'Pas reçu le code ? ',
                                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                                    children: [
                                      if (canResend)
                                        const TextSpan(
                                          text: 'Renvoyer',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            decoration: TextDecoration.underline,
                                            decorationColor: Colors.white,
                                          ),
                                        )
                                      else
                                        TextSpan(
                                          text: 'Renvoyer dans ${_secondsLeft}s',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.45),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),        // Column
                ),          // Padding
              ),            // ConstrainedBox
            ),              // Center
          );                // SingleChildScrollView
            },
          ),
        ),
      ),
    );
  }
}
