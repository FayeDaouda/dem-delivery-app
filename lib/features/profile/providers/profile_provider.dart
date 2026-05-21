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
      // Mise en ligne automatique à la connexion
      if (goOnlineIfOffline && !(user['isAvailable'] as bool? ?? false)) {
        await toggleAvailability();
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: friendlyError(e));
    }
  }

  Future<bool> toggleAvailability() async {
    try {
      final isAvailable = await _repo.toggleAvailability();
      final updatedUser = Map<String, dynamic>.from(state.user ?? {})
        ..['isAvailable'] = isAvailable;
      await AuthStorage.saveUser(updatedUser);
      state = state.copyWith(user: updatedUser);
      return isAvailable;
    } catch (e) {
      state = state.copyWith(error: friendlyError(e));
      rethrow;
    }
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);
