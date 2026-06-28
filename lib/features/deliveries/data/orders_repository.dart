import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';

class OrdersRepository {
  final _dio = ApiClient.dio;

  Future<List<Map<String, dynamic>>> getAvailableOrders() async {
    try {
      final response = await _dio.get('/orders/available');
      return _parseList(response.data);
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les commandes.',
        e.response?.statusCode,
      );
    } catch (_) {
      throw const AppException('Impossible de charger les commandes.');
    }
  }

  Future<List<Map<String, dynamic>>> getMyOrders() async {
    try {
      final response = await _dio.get('/orders/my');
      return _parseList(response.data);
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger l\'historique.',
        e.response?.statusCode,
      );
    } catch (_) {
      throw const AppException('Impossible de charger l\'historique.');
    }
  }

  /// Parse sûre : accepte une liste directe ou un objet paginé { orders/data: [...] }.
  static List<Map<String, dynamic>> _parseList(dynamic data) {
    List<dynamic> raw;
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      final inner = data['orders'] ?? data['data'] ?? data['items'];
      raw = inner is List ? inner : [];
    } else {
      raw = [];
    }
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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

  Future<Map<String, dynamic>> confirmPayment(
      String id, String status, {String? note}) async {
    try {
      final response = await _dio.patch(
        '/orders/$id/confirm-payment',
        data: {'status': status, 'note': note},
      );
      final data = response.data as Map<String, dynamic>;
      return (data['order'] ?? data) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de la confirmation.',
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
      return 1.0;
    }
  }

  /// Estimation officielle depuis le backend (source de vérité unique).
  /// Retourne null si hors ligne — l'appelant affiche un fallback.
  Future<Map<String, dynamic>?> getEstimate({
    required double pickupLat, required double pickupLng,
    required double deliveryLat, required double deliveryLng,
    String orderType = 'DELIVERY',
  }) async {
    debugPrint('[getEstimate] CALLING pickup=($pickupLat,$pickupLng) delivery=($deliveryLat,$deliveryLng)');
    try {
      final res = await _dio.get('/orders/estimate', queryParameters: {
        'pickupLat':   pickupLat,
        'pickupLng':   pickupLng,
        'deliveryLat': deliveryLat,
        'deliveryLng': deliveryLng,
        'orderType':   orderType,
      });
      debugPrint('[getEstimate] OK: ${res.data}');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint('[getEstimate] ERROR ${e.response?.statusCode} ${e.response?.data} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[getEstimate] UNEXPECTED: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getHeatmap() async {
    try {
      final response = await _dio.get('/orders/heatmap');
      return _parseList(response.data);
    } catch (_) {
      return [];
    }
  }

  Future<void> rateDriver({
    required String orderId,
    required String driverId,
    required int score,
    String? comment,
  }) async {
    try {
      await _dio.post('/ratings', data: {
        'orderId': orderId,
        'ratedId': driverId,
        'score': score,
        'comment': comment,
      });
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'envoyer la note.',
        e.response?.statusCode,
      );
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

  Future<Map<String, dynamic>?> getActiveBatch() async {
    try {
      final response = await _dio.get('/orders/batch/driver/active');
      final data = response.data;
      if (data == null) return null;
      return data as Map<String, dynamic>;
    } on DioException {
      return null;
    }
  }

  Future<Map<String, dynamic>> acceptBatch(String batchId) async {
    try {
      final response = await _dio.patch('/orders/batch/$batchId/accept');
      final data = response.data as Map<String, dynamic>;
      return (data['batch'] ?? data) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'accepter la tournée.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> declineBatch(String batchId) async {
    try {
      await _dio.patch('/orders/batch/$batchId/decline');
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de refuser la tournée.',
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

  Future<Map<String, dynamic>> driverCancelOrder(String id) async {
    try {
      final response = await _dio.patch('/orders/$id/driver-cancel');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'annuler la course.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> updateDriverLocation(double lat, double lng) async {
    try {
      await _dio.patch('/users/driver/location', data: {'lat': lat, 'lng': lng});
    } catch (_) {}
  }

  Future<bool> checkFreeCourse() async {
    try {
      final response = await _dio.get('/orders/free-course-check');
      return response.data['eligible'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Signale un problème pendant une course.
  /// Retourne { message, support: { phone, whatsapp } }
  Future<Map<String, dynamic>> reportIssue(
    String orderId, {
    required String type,
    String? message,
  }) async {
    try {
      final response = await _dio.post(
        '/orders/$orderId/report',
        data: { 'type': type, if (message != null && message.isNotEmpty) 'message': message },
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'envoyer le signalement.',
        e.response?.statusCode,
      );
    }
  }
}
