import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';

class LocationDisclosureScreen extends StatelessWidget {
  const LocationDisclosureScreen({super.key});

  // Continuer : demande toujours la permission système (guideline 5.1.1.iv Apple).
  // L'utilisateur choisit d'autoriser ou refuser dans la dialog système iOS/Android.
  // Pas de bouton "Plus tard" — Apple exige que la dialog système apparaisse toujours.
  Future<void> _continue(BuildContext context) async {
    await Permission.locationWhenInUse.request();
    await Permission.locationAlways.request();
    // Android uniquement : demande l'exemption batterie pour que le foreground
    // service GPS survive aux optimisations agressives (Xiaomi, Samsung, Huawei…)
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    await AuthStorage.setLocationDisclosureSeen();
    await AuthStorage.setOnboardingSeen();
    await NotificationService.requestPermissionAndToken();
    appStartupNotifier.markDisclosureSeen();  // → GoRouter redirect → /phone
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // ── Icône ──────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.30),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 60,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF40F0C0),
                      size: 52,
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // ── Titre ──────────────────────────────────────────────────
                const Text(
                  'Suivi de livraison\nen temps réel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),

                const SizedBox(height: 32),

                // ── Divulgation (encadrée) ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF40F0C0).withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF40F0C0).withValues(alpha: 0.40)),
                            ),
                            child: const Text(
                              'OBLIGATOIRE',
                              style: TextStyle(
                                color: Color(0xFF40F0C0),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'DEM utilise votre localisation pour permettre le suivi des livraisons en direct, même lorsque l\'application fonctionne en arrière-plan.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 15,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── Bouton principal ───────────────────────────────────────
                // Texte neutre "Continuer" requis par Apple guideline 5.1.1.iv.
                // Pas de bouton "Plus tard" — la dialog système doit toujours apparaître.
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => _continue(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF04317C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Continuer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Liens légaux ───────────────────────────────────────────
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 12,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(text: 'En continuant, vous acceptez notre\n'),
                        TextSpan(
                          text: 'Politique de confidentialité',
                          style: const TextStyle(
                            color: Colors.white70,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: TapGestureRecognizer()..onTap = () {
                            launchUrl(Uri.parse(AppConfig.privacyPolicyUrl), mode: LaunchMode.inAppBrowserView);
                          },
                        ),
                        const TextSpan(text: ' et nos '),
                        TextSpan(
                          text: 'Conditions d\'utilisation',
                          style: const TextStyle(
                            color: Colors.white70,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: TapGestureRecognizer()..onTap = () {
                            launchUrl(Uri.parse(AppConfig.termsUrl), mode: LaunchMode.inAppBrowserView);
                          },
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
