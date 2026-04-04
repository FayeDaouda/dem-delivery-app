import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';

class OrdersRepository {
  final _dio = ApiClient.dio;

  Future<List<Map<String, dynamic>>> getAvailableOrders() async {
    try {
      final response = await _dio.get('/orders/available');
      return List<Map<String, dynamic>>.from(response.data as List);
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les commandes.',
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getMyOrders() async {
    try {
      final response = await _dio.get('/orders/my');
      return List<Map<String, dynamic>>.from(response.data as List);
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger l\'historique.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getOrderById(String id) async {
    try {
      final response = await _dio.get('/orders/$id');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Commande introuvable.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> acceptOrder(String id) async {
    try {
      final response = await _dio.patch('/orders/$id/accept');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'accepter la commande.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> pickupOrder(String id) async {
    try {
      final response = await _dio.patch('/orders/$id/pickup');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de la récupération.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> deliverOrder(String id) async {
    try {
      final response = await _dio.patch('/orders/$id/deliver');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de la livraison.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> cancelOrder(String id) async {
    try {
      final response = await _dio.patch('/orders/$id/cancel');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'annuler la commande.',
        e.response?.statusCode,
      );
    }
  }
}
