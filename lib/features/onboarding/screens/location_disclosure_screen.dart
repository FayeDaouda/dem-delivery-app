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
import '../../../core/utils/dem_layout.dart';

class LocationDisclosureScreen extends StatefulWidget {
  const LocationDisclosureScreen({super.key});

  @override
  State<LocationDisclosureScreen> createState() => _LocationDisclosureScreenState();
}

class _LocationDisclosureScreenState extends State<LocationDisclosureScreen> {
  bool _loading = false;

  // Guideline 5.1.1.iv — demande la permission système (l'utilisateur choisit dans le dialog).
  // On ne demande que "whenInUse" ici : iOS interdit de demander "Always" directement
  // (l'utilisateur doit passer par les Paramètres système). Demander "Always" ici
  // bloque l'app indéfiniment sur iOS 14+.
  Future<void> _continue() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      await Permission.locationWhenInUse.request();
      // Android uniquement : exemption batterie pour le foreground service GPS.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}

    await AuthStorage.setLocationDisclosureSeen();
    await AuthStorage.setOnboardingSeen();

    // Permission notif + token FCM en arrière-plan — ne bloque pas la navigation.
    // La dialog système iOS apparaît après la navigation vers /phone, ce qui est
    // acceptable et évite que le reviewer voie un spinner de 10-20 s sans réaction.
    NotificationService.requestPermissionAndToken()
        .timeout(const Duration(seconds: 20))
        .catchError((_) {});

    if (!mounted) return;
    appStartupNotifier.markDisclosureSeen(); // → GoRouter redirect → /phone
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = DemLayout.isTablet(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: DemLayout.formMaxWidth(context)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // ── Icône ──────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: isTablet ? 130.0 : 100.0,
                    height: isTablet ? 130.0 : 100.0,
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
                    child: Icon(
                      Icons.location_on_rounded,
                      color: AppColors.accentMint,
                      size: isTablet ? 65.0 : 52.0,
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // ── Titre ──────────────────────────────────────────────────
                Text(
                  'Suivi de livraison\nen temps réel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isTablet ? 36.0 : 30.0,
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
                              color: AppColors.accentMint.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.accentMint.withValues(alpha: 0.40)),
                            ),
                            child: const Text(
                              'OBLIGATOIRE',
                              style: TextStyle(
                                color: AppColors.accentMint,
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
                SizedBox(
                  width: double.infinity,
                  height: isTablet ? 60.0 : 56.0,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryDark,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primaryDark,
                            ),
                          )
                        : const Text(
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
            ),       // Column
          ),         // Padding
        ),           // ConstrainedBox
      ),             // Center
        ),           // SafeArea
      ),             // Container
    );
  }
}
