import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[DEM] main() started');

  // ── Firebase + Crashlytics ─────────────────────────────────────────────────
  debugPrint('[DEM] Firebase.initializeApp starting...');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[DEM] Firebase.initializeApp done');
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[DEM FATAL ERROR] $error\n$stack');
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

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

class DemApp extends StatelessWidget {
  const DemApp({super.key});

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
