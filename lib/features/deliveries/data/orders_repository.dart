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
      // Backend retourne { message, order } — on extrait l'objet order
      final data = response.data as Map<String, dynamic>;
      return (data['order'] ?? data) as Map<String, dynamic>;
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
      final data = response.data as Map<String, dynamic>;
      return (data['order'] ?? data) as Map<String, dynamic>;
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
      final data = response.data as Map<String, dynamic>;
      return (data['order'] ?? data) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de la livraison.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> body) async {
    try {
      final response = await _dio.post('/orders', data: body);
      final data = response.data as Map<String, dynamic>;
      return (data['order'] ?? data) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de créer la commande.',
        e.response?.statusCode,
      );
    }
  }

  Future<double> getSurgeMultiplier(double lat, double lng) async {
    try {
      final response = await _dio.get('/orders/surge', queryParameters: {'lat': lat, 'lng': lng});
      return ((response.data['surgeMultiplier'] as num?) ?? 1.0).toDouble();
    } on DioException {
      return 1.0; // fallback silencieux
    }
  }

  Future<List<Map<String, dynamic>>> getHeatmap() async {
    try {
      final response = await _dio.get('/orders/heatmap');
      return List<Map<String, dynamic>>.from(response.data as List);
    } on DioException {
      return [];
    }
  }

  Future<void> declineOrder(String id) async {
    try {
      await _dio.patch('/orders/$id/decline');
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de refuser la course.',
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
