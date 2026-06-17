import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../data/dem_pro_repository.dart';

final demProRepositoryProvider = Provider<DemProRepository>((_) => DemProRepository(ApiClient.dio));

class DemProState {
  final bool isLoading;
  final String? error;

  const DemProState({this.isLoading = false, this.error});

  DemProState copyWith({bool? isLoading, String? error}) {
    return DemProState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class DemProNotifier extends Notifier<DemProState> {
  @override
  DemProState build() => const DemProState();

  DemProRepository get _repo => ref.read(demProRepositoryProvider);

  Future<Map<String, dynamic>> submitOnboarding({
    required String firstName,
    required String lastName,
    required String businessName,
    required String sector,
    String? email,
    required String weeklyVolume,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _repo.submitOnboarding(
        firstName: firstName,
        lastName: lastName,
        businessName: businessName,
        sector: sector,
        email: email,
        weeklyVolume: weeklyVolume,
      );
      state = state.copyWith(isLoading: false);
      return data;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: friendlyError(e));
      rethrow;
    }
  }
}

final demProProvider = NotifierProvider<DemProNotifier, DemProState>(DemProNotifier.new);
