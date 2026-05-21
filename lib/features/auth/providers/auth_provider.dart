import '../../../core/error/app_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../../../core/storage/auth_storage.dart';

// ─── Repository provider ───────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>((_) => AuthRepository());

// ─── Auth state ────────────────────────────────────────────────────────────
class AuthState {
  final bool isLoading;
  final String? error;

  const AuthState({this.isLoading = false, this.error});

  AuthState copyWith({bool? isLoading, String? error}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ─── Auth notifier ─────────────────────────────────────────────────────────
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> sendOtp(String phone) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repo.sendOtp(phone);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: friendlyError(e));
      rethrow;
    }
    state = state.copyWith(isLoading: false);
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _repo.verifyOtp(phone: phone, code: code);
      state = state.copyWith(isLoading: false);
      return data;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: friendlyError(e));
      rethrow;
    }
  }

  Future<Map<String, dynamic>> setupProfile({
    required String role,
    String? vehicleType,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _repo.setupProfile(role: role, vehicleType: vehicleType);
      state = state.copyWith(isLoading: false);
      return data;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: friendlyError(e));
      rethrow;
    }
  }

  Future<void> logout() => _repo.logout();
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

// ─── Session provider (lecture seule) ─────────────────────────────────────
final currentUserProvider = FutureProvider<Map<String, dynamic>?>((ref) {
  return AuthStorage.getUser();
});

final isLoggedInProvider = FutureProvider<bool>((ref) {
  return AuthStorage.isLoggedIn();
});
