import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/storage/auth_storage.dart';

class AuthRepository {
  final _dio = ApiClient.dio;

  Future<void> sendOtp(String phone) async {
    try {
      await _dio.post('/auth/send-otp', data: {'phone': phone});
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'envoyer le code.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
  }) async {
    try {
      final response = await _dio.post('/auth/verify-otp', data: {
        'phone': phone,
        'code': code,
      });
      final data = response.data as Map<String, dynamic>;
      await AuthStorage.saveToken(data['token']);
      await AuthStorage.saveUser(data['user']);
      return data;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Code invalide ou expiré.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> setupProfile({
    required String role,
    String? vehicleType,
  }) async {
    try {
      final body = <String, dynamic>{'role': role};
      if (vehicleType != null) body['vehicleType'] = vehicleType;

      final response = await _dio.patch('/users/me/setup', data: body);
      final data = response.data as Map<String, dynamic>;
      await AuthStorage.saveToken(data['token']);
      await AuthStorage.saveUser(data['user']);
      return data;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de la configuration du profil.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> logout() => AuthStorage.clear();
}
