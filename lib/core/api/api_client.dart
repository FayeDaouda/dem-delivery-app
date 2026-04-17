import 'package:dio/dio.dart';
import '../storage/auth_storage.dart';
import '../router/app_router.dart';

const _baseUrl = 'https://dem-delivery-backend.onrender.com';

class ApiClient {
  static final Dio _dio = _buildDio();

  static Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

    // Intercepteur : injecte le token JWT + gère les erreurs auth
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await AuthStorage.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (DioException e, handler) async {
        final status = e.response?.statusCode;
        final path   = e.requestOptions.path;

        // Endpoints qui opèrent sur l'utilisateur connecté (req.user.userId)
        // Un 404 ici = user inexistant en DB → session zombie → déconnexion forcée
        final userSelfPaths = [
          '/users/me',
          '/users/driver/phone-change',
          '/users/driver/availability',
          '/users/driver/onboarding',
          '/users/driver/documents',
        ];
        final isAuthEndpoint   = path.contains('/auth/');
        final isSelfUserPath   = userSelfPaths.any((p) => path.endsWith(p));

        if (!isAuthEndpoint && (status == 401 || (status == 404 && isSelfUserPath))) {
          await AuthStorage.clear();
          appRouter.go('/phone');
          return; // ne pas propager l'erreur — la redirection suffit
        }
        handler.next(e);
      },
    ));

    return dio;
  }

  static Dio get dio => _dio;
}
