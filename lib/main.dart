import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'core/config/app_config.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[DEM] main() started');

  // ── Firebase + Crashlytics ─────────────────────────────────────────────────
  await AppConfig.init();

  debugPrint('[DEM] Firebase.initializeApp starting...');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[DEM] Firebase.initializeApp done');
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[DEM FATAL ERROR] $error\n$stack');
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // ── Écran de secours en production — jamais d'écran rouge/blanc pour le grand public ──
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const _FriendlyErrorScreen();
  }

  // ── Push notifications (canaux + listeners uniquement, sans dialog de permission) ─
  NotificationService.setup().timeout(const Duration(seconds: 5)).catchError((_) {});

  // ── Google Maps (Android) ──────────────────────────────────────────────────
  final mapsImplementation = GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    mapsImplementation.useAndroidViewSurface = true;
  }

  debugPrint('[DEM] runApp() about to be called');
  runApp(const ProviderScope(child: DemApp()));
}

/// Remplace l'écran rouge/blanc de Flutter en production par un message
/// neutre — affiché si un widget plante de façon inattendue.
class _FriendlyErrorScreen extends StatelessWidget {
  const _FriendlyErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Text(
        'Une erreur est survenue. Veuillez réessayer.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
    );
  }
}

class DemApp extends StatefulWidget {
  const DemApp({super.key});

  @override
  State<DemApp> createState() => _DemAppState();
}

class _DemAppState extends State<DemApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.clearBadge();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DEM',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      routerConfig: appRouter,
    );
  }
}
