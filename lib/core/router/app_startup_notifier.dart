import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../storage/auth_storage.dart';
import '../../features/profile/data/profile_repository.dart';

/// Notifier chargé au démarrage.
/// GoRouter l'écoute via [refreshListenable] et réévalue les redirections
/// à chaque appel de [notifyListeners].
class AppStartupNotifier extends ChangeNotifier {

  // ── État de chargement ───────────────────────────────────────────────────────
  bool _isReady = false;
  bool get isReady => _isReady;

  // ── Flags de flux ────────────────────────────────────────────────────────────
  bool _isLoggedIn        = false;
  bool _onboardingSeen    = false;
  bool _disclosureSeen    = false;
  bool _locationGranted   = false;

  bool get isLoggedIn      => _isLoggedIn;
  bool get onboardingSeen  => _onboardingSeen;
  bool get disclosureSeen  => _disclosureSeen;
  bool get locationGranted => _locationGranted;

  // ── Données utilisateur (connecté) ──────────────────────────────────────────
  String? role;
  String? vehicleType;
  bool    isActive    = true;
  String? chefStatus;

  // ── Initialisation asynchrone complète ──────────────────────────────────────
  Future<void> initialize() async {
    // 1. Connexion
    _isLoggedIn = await AuthStorage.isLoggedIn();

    // 2. Flags onboarding / divulgation
    _onboardingSeen  = await AuthStorage.isOnboardingSeen();
    _disclosureSeen  = await AuthStorage.isLocationDisclosureSeen();

    // 3. Statut permission localisation arrière-plan
    final permStatus = await Permission.locationAlways.status;
    _locationGranted = permStatus.isGranted;

    // 4. Si connecté, résoudre le rôle (rapide : cache d'abord)
    if (_isLoggedIn) {
      Map<String, dynamic>? user;
      try {
        user = await ProfileRepository().getMe().timeout(const Duration(seconds: 8));
      } catch (_) {
        user = await AuthStorage.getUser();
      }
      role        = user?['role'] as String?;
      vehicleType = user?['vehicleType'] as String?;
      isActive    = user?['isActive'] as bool? ?? true;
      chefStatus  = user?['chefDeFlotteStatus'] as String?;

      // Si le rôle est null après fetch + cache → état corrompu (token sans profil complet)
      // On efface la session pour permettre une ré-authentification propre
      if (role == null) {
        await AuthStorage.clear();
        _isLoggedIn = false;
      }
    }

    _isReady = true;
    notifyListeners(); // ← déclenche GoRouter.redirect
  }

  // ── Mutations appelées depuis les écrans ─────────────────────────────────────
  void markOnboardingSeen()  { _onboardingSeen  = true; notifyListeners(); }
  void markDisclosureSeen()  { _disclosureSeen  = true; notifyListeners(); }
  void markLocationGranted() { _locationGranted = true; notifyListeners(); }
  void markLoggedIn({ required String userRole, String? vehicle, bool active = true, String? chef }) {
    _isLoggedIn = true;
    role = userRole; vehicleType = vehicle; isActive = active; chefStatus = chef;
    notifyListeners();
  }
  void markLoggedOut() {
    _isLoggedIn = false; role = null; vehicleType = null; isActive = true; chefStatus = null;
    notifyListeners();
  }

  // ── Destination pour utilisateur connecté ───────────────────────────────────
  String get homeForRole {
    if (role == 'DRIVER') {
      if (!isActive)             return '/driver/suspended';
      if (vehicleType == 'TAXI') return '/driver/thiak/home';
      return '/driver/home';
    }
    if (role == 'CLIENT') return '/client/home';
    if (role == 'CHEF_DE_FLOTTE') {
      if (!isActive)                return '/chef-de-flotte/suspended';
      if (chefStatus == 'ACTIVE')   return '/chef-de-flotte/dashboard';
      if (chefStatus == 'PENDING')  return '/chef-de-flotte/pending';
      if (chefStatus == 'REJECTED') return '/chef-de-flotte/rejected';
      return '/chef-de-flotte/onboarding';
    }
    // Ne jamais retourner '/phone' ici — créerait une boucle redirect infinie
    // L'état corrompu est nettoyé dans initialize() avant d'arriver ici
    return '/client/home';
  }
}

/// Singleton global accessible partout dans l'app.
final appStartupNotifier = AppStartupNotifier();
