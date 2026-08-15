import 'package:flutter/foundation.dart';
import '../notifications/notification_service.dart';
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
  bool _isLoggedIn = false;
  bool _onboardingSeen = false;
  bool _disclosureSeen = false;
  bool _locationGranted = false;

  bool get isLoggedIn => _isLoggedIn;
  bool get onboardingSeen => _onboardingSeen;
  bool get disclosureSeen => _disclosureSeen;
  bool get locationGranted => _locationGranted;

  // ── Données utilisateur (connecté) ──────────────────────────────────────────
  String? role;
  String? vehicleType;
  bool isActive = true;
  String? chefStatus;
  String? proStatus;
  bool proOnboarded = false;

  // ── Initialisation asynchrone complète ──────────────────────────────────────
  Future<void> initialize() async {
    // 1. Connexion
    _isLoggedIn = await AuthStorage.isLoggedIn();

    // 2. Flags onboarding / divulgation
    _onboardingSeen = await AuthStorage.isOnboardingSeen();
    _disclosureSeen = await AuthStorage.isLocationDisclosureSeen();

    // 3. Permission localisation — vérifiée plus tard par LocationDisclosureScreen,
    //    pas ici (checker .status sur iOS déclenche le dialog système au démarrage).

    // 4. Si connecté, résoudre le rôle (rapide : cache d'abord)
    if (_isLoggedIn) {
      Map<String, dynamic>? user;
      try {
        user = await ProfileRepository().getMe().timeout(
          const Duration(seconds: 8),
        );
      } catch (_) {
        user = await AuthStorage.getUser();
      }
      role = user?['role'] as String?;
      vehicleType = user?['vehicleType'] as String?;
      isActive = user?['isActive'] as bool? ?? true;
      chefStatus = user?['chefDeFlotteStatus'] as String?;
      proStatus = user?['proStatus'] as String?;
      proOnboarded = (user?['proBusinessName'] as String?)?.isNotEmpty == true;

      if (role == null) {
        await AuthStorage.clear();
        _isLoggedIn = false;
      } else {
        NotificationService.requestPermissionAndToken();
      }
    }

    _isReady = true;
    notifyListeners(); // ← déclenche GoRouter.redirect
  }

  // ── Mutations appelées depuis les écrans ─────────────────────────────────────
  void markOnboardingSeen() {
    _onboardingSeen = true;
    notifyListeners();
  }

  void markDisclosureSeen() {
    _disclosureSeen = true;
    notifyListeners();
  }

  void markLocationGranted() {
    _locationGranted = true;
    notifyListeners();
  }

  void markLoggedIn({
    required String userRole,
    String? vehicle,
    bool active = true,
    String? chef,
    String? pro,
    bool proDone = false,
  }) {
    _isLoggedIn = true;
    role = userRole;
    vehicleType = vehicle;
    isActive = active;
    chefStatus = chef;
    proStatus = pro;
    proOnboarded = proDone;
    notifyListeners();
  }

  void markLoggedOut() {
    _isLoggedIn = false;
    role = null;
    vehicleType = null;
    isActive = true;
    chefStatus = null;
    proStatus = null;
    proOnboarded = false;
    notifyListeners();
  }

  /// Recharge le statut DEM Pro depuis l'API (bouton "Actualiser" de l'écran
  /// d'attente) — déclenche une réévaluation de [homeForRole] par GoRouter.
  Future<void> refreshProStatus() async {
    try {
      final user = await ProfileRepository().getMe();
      isActive = user['isActive'] as bool? ?? true;
      proStatus = user['proStatus'] as String?;
      proOnboarded = (user['proBusinessName'] as String?)?.isNotEmpty == true;
      notifyListeners();
    } catch (_) {}
  }

  // ── Destination pour utilisateur connecté ───────────────────────────────────
  String get homeForRole {
    if (role == 'DRIVER') {
      if (!isActive) return '/driver/suspended';
      return '/driver/home';
    }
    if (role == 'CLIENT') return '/client/home';
    if (role == 'CHEF_DE_FLOTTE') {
      if (!isActive) return '/chef-de-flotte/suspended';
      if (chefStatus == 'ACTIVE') return '/chef-de-flotte/dashboard';
      if (chefStatus == 'PENDING') return '/chef-de-flotte/pending';
      if (chefStatus == 'REJECTED') return '/chef-de-flotte/rejected';
      return '/chef-de-flotte/onboarding';
    }
    if (role == 'DEM_PRO') {
      // Vérifié en premier, avant même le statut de validation — un compte
      // suspendu (isActive: false) garde son proStatus tel quel (voir
      // admin.dem_pro.controller.js:setProActive, qui ne touche jamais
      // proStatus), donc sans cette vérification en tête un compte ACTIVE
      // suspendu retombait silencieusement sur /dem-pro/home.
      if (!isActive) return '/dem-pro/suspended';
      if (!proOnboarded) return '/dem-pro/onboarding';
      if (proStatus == 'PENDING') return '/dem-pro/pending';
      if (proStatus == 'REJECTED') return '/dem-pro/rejected';
      if (proStatus == 'ACTIVE') return '/dem-pro/home';
      return '/dem-pro/onboarding';
    }
    // Ne jamais retourner '/phone' ici — créerait une boucle redirect infinie
    // L'état corrompu est nettoyé dans initialize() avant d'arriver ici
    return '/client/home';
  }
}

/// Singleton global accessible partout dans l'app.
final appStartupNotifier = AppStartupNotifier();
