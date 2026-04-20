import 'package:dio/dio.dart';

const _baseUrl = 'https://api.dem.sn';

class AdminSession {
  static String? token;
  static Map<String, dynamic>? admin;
  static Dio? _dio;

  static bool get isLoggedIn => token != null;

  static void set(String t, Map<String, dynamic> a) {
    token = t;
    admin = a;
    _dio = _buildDio();
  }

  static void clear() {
    token = null;
    admin = null;
    _dio = null;
  }

  static Dio get dio => _dio ??= _buildDio();

  static Dio _buildDio() => Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
  ));
}
