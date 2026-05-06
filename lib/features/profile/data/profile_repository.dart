import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/storage/auth_storage.dart';

class ProfileRepository {
  final _dio = ApiClient.dio;

  Future<Map<String, dynamic>> getMe() async {
    try {
      final response = await _dio.get('/users/me');
      final user = response.data as Map<String, dynamic>;
      await AuthStorage.saveUser(user);
      return user;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger le profil.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> completeOnboarding({
    required String name,
    String? vehiclePlate,
  }) async {
    try {
      final response = await _dio.post('/users/driver/onboarding', data: {
        'name': name,
        if (vehiclePlate != null && vehiclePlate.isNotEmpty) 'vehiclePlate': vehiclePlate,
      });
      final user = response.data['user'] as Map<String, dynamic>;
      await AuthStorage.saveUser(user);
      return user;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de l\'enregistrement.',
        e.response?.statusCode,
      );
    }
  }

  Future<bool> toggleAvailability() async {
    try {
      final response = await _dio.patch('/users/driver/availability');
      return response.data['isAvailable'] as bool;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors du changement de disponibilité.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>?> getForfaitStatus() async {
    try {
      final response = await _dio.get('/users/driver/forfait-status');
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getBadgesConfig() async {
    try {
      final response = await _dio.get('/users/badges/config');
      final list = response.data['badges'] as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return null; // Fallback sur les valeurs hardcodées dans BadgeService
    }
  }
}
