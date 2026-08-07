import '../../../core/error/app_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/profile_repository.dart';
import '../../../core/storage/auth_storage.dart';

// ─── Repository provider ───────────────────────────────────────────────────
final profileRepositoryProvider = Provider<ProfileRepository>((_) => ProfileRepository());

// ─── Profile state ─────────────────────────────────────────────────────────
class ProfileState {
  final Map<String, dynamic>? user;
  final bool isLoading;
  final String? error;

  const ProfileState({this.user, this.isLoading = false, this.error});

  // Par défaut en ligne — évite le flash "Hors ligne" au démarrage
  bool get isAvailable => user?['isAvailable'] as bool? ?? true;
  String get name => user?['name'] as String? ?? '';
  String get vehicleType => user?['vehicleType'] as String? ?? 'MOTO';

  ProfileState copyWith({
    Map<String, dynamic>? user,
    bool? isLoading,
    String? error,
  }) {
    return ProfileState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ─── Profile notifier ──────────────────────────────────────────────────────
class ProfileNotifier extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    _loadFromStorage();
    return const ProfileState();
  }

  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  Future<void> _loadFromStorage() async {
    final user = await AuthStorage.getUser();
    if (user != null) {
      // Le driver est toujours mis en ligne au démarrage
      final userOnline = Map<String, dynamic>.from(user)
        ..['isAvailable'] = true;
      await AuthStorage.saveUser(userOnline);
      state = state.copyWith(user: userOnline);
    }
  }

  Future<void> fetchProfile({bool goOnlineIfOffline = false}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _repo.getMe();
      state = state.copyWith(user: user, isLoading: false);
      // Mise en ligne automatique à la connexion — seulement si le livreur a
      // une passe valide (si le blocage dispatch est actif). Appel direct au
      // repo (pas toggleAvailability() de ce notifier) pour pouvoir avaler le
      // 402 sans le faire remonter en state.error : ce n'est pas une vraie
      // erreur technique, juste "reste hors ligne, pas de passe" — le
      // bandeau d'accueil (_NormalSheet) explique déjà pourquoi.
      if (goOnlineIfOffline && !(user['isAvailable'] as bool? ?? false)) {
        try {
          final isAvailable = await _repo.toggleAvailability();
          final updatedUser = Map<String, dynamic>.from(user)..['isAvailable'] = isAvailable;
          await AuthStorage.saveUser(updatedUser);
          state = state.copyWith(user: updatedUser);
        } on AppException catch (e) {
          if (e.statusCode != 402) rethrow;
        }
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: friendlyError(e));
    }
  }

  Future<bool> toggleAvailability() async {
    // Ignore un appel concurrent (double-tap) plutôt que de laisser deux
    // requêtes de toggle se chevaucher et désynchroniser l'état réel côté
    // serveur de ce que l'app affiche.
    if (state.isLoading) return state.isAvailable;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final isAvailable = await _repo.toggleAvailability();
      final updatedUser = Map<String, dynamic>.from(state.user ?? {})
        ..['isAvailable'] = isAvailable;
      await AuthStorage.saveUser(updatedUser);
      state = state.copyWith(user: updatedUser, isLoading: false);
      return isAvailable;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: friendlyError(e));
      rethrow;
    }
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);
