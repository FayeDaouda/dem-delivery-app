import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';

class FavoriteAddressesRepository {
  final _dio = ApiClient.dio;

  Future<List<Map<String, dynamic>>> getAll() async {
    try {
      final res = await _dio.get('/me/favorite-addresses');
      return List<Map<String, dynamic>>.from(res.data['addresses'] as List);
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Impossible de charger les adresses.', e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/me/favorite-addresses', data: data);
      return res.data['address'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Impossible de créer l\'adresse.', e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data) async {
    try {
      final res = await _dio.put('/me/favorite-addresses/$id', data: data);
      return res.data['address'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Impossible de modifier l\'adresse.', e.response?.statusCode);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('/me/favorite-addresses/$id');
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Impossible de supprimer l\'adresse.', e.response?.statusCode);
    }
  }
}
