import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/storage/auth_storage.dart';

class AuthService {
  static final _dio = ApiClient.dio;

  static Future<void> sendOtp(String phone) async {
    await _dio.post('/auth/send-otp', data: {'phone': phone});
  }

  static Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final response = await _dio.post('/auth/verify-otp', data: {
      'phone': phone,
      'code': code,
    });
    final data = response.data as Map<String, dynamic>;
    await AuthStorage.saveToken(data['token']);
    await AuthStorage.saveUser(data['user']);
    return data;
  }

  /// Appelé depuis l'écran de choix de rôle (nouveaux utilisateurs).
  /// Retourne un nouveau token avec le bon rôle.
  static Future<Map<String, dynamic>> setupProfile({
    required String role,
    String? vehicleType,
  }) async {
    final body = <String, dynamic>{'role': role};
    if (vehicleType != null) body['vehicleType'] = vehicleType;

    final response = await _dio.patch('/users/me/setup', data: body);
    final data = response.data as Map<String, dynamic>;
    await AuthStorage.saveToken(data['token']);
    await AuthStorage.saveUser(data['user']);
    return data;
  }

  static Future<void> logout() async {
    await AuthStorage.clear();
  }
}
