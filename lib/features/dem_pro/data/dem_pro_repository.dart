import 'package:dio/dio.dart';
import '../../../core/error/app_exception.dart';

class DemProRepository {
  final Dio _dio;
  const DemProRepository(this._dio);

  /// Soumet (ou resoumet après refus) le profil entreprise DEM Pro.
  Future<Map<String, dynamic>> submitOnboarding({
    required String firstName,
    required String lastName,
    required String businessName,
    required String sector,
    String? email,
    required String weeklyVolume,
  }) async {
    try {
      final res = await _dio.post('/dem-pro/onboarding', data: {
        'firstName': firstName,
        'lastName': lastName,
        'businessName': businessName,
        'sector': sector,
        if (email != null && email.isNotEmpty) 'email': email,
        'weeklyVolume': weeklyVolume,
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de l\'envoi du profil entreprise.',
        e.response?.statusCode,
      );
    }
  }

  /// Liste complète des commandes du compte DEM Pro (clientId = userId).
  Future<List<Map<String, dynamic>>> getMyOrders() async {
    try {
      final res = await _dio.get('/orders/my');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les livraisons.',
        e.response?.statusCode,
      );
    }
  }

  /// Statistiques du tableau de bord (livraisons du jour, dépenses, etc.)
  Future<Map<String, dynamic>> getMyStats() async {
    try {
      final res = await _dio.get('/dem-pro/me/stats');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les statistiques.',
        e.response?.statusCode,
      );
    }
  }

  // ── Adresses Pro ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAddresses() async {
    try {
      final res = await _dio.get('/dem-pro/addresses');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les adresses.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> createAddress(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/dem-pro/addresses', data: data);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de créer l\'adresse.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> updateAddress(String id, Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch('/dem-pro/addresses/$id', data: data);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de modifier l\'adresse.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteAddress(String id) async {
    try {
      await _dio.delete('/dem-pro/addresses/$id');
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de supprimer l\'adresse.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> setDefaultAddress(String id) async {
    try {
      final res = await _dio.patch('/dem-pro/addresses/$id/default');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de définir l\'adresse par défaut.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> incrementAddressUsage(String id) async {
    try {
      await _dio.post('/dem-pro/addresses/$id/use');
    } on DioException catch (_) {}
  }

  Future<Map<String, dynamic>> getMyFinances(String period) async {
    try {
      final res = await _dio.get('/dem-pro/me/finances', queryParameters: {'period': period});
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les finances.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getBatchById(String id) async {
    try {
      final res = await _dio.get('/dem-pro/batch/$id');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Tournée introuvable.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> createBatch(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/dem-pro/batch', data: data);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de créer la tournée.',
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getMyBatches() async {
    try {
      final res = await _dio.get('/dem-pro/batch');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les tournées.',
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getRecentPickups() async {
    try {
      final res = await _dio.get('/dem-pro/me/recent-pickups');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les adresses récentes.',
        e.response?.statusCode,
      );
    }
  }
}
