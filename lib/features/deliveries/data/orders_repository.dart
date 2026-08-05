import 'dart:io';

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

  /// Comme [getMyOrders] mais paginé — le backend supporte déjà `page`/`limit`
  /// (réponse `{ orders, page, totalPages }`), utilisé par l'écran d'historique
  /// pour éviter de charger tout l'historique du client d'un coup.
  Future<({List<Map<String, dynamic>> orders, bool hasMore})> getMyOrdersPage({
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final response = await _dio.get(
        '/orders/my',
        queryParameters: {'page': page, 'limit': limit},
      );
      final data = response.data;
      final orders = _parseList(data);
      if (data is Map) {
        final currentPage = (data['page'] as num?)?.toInt();
        final totalPages = (data['totalPages'] as num?)?.toInt();
        final hasMore =
            currentPage != null &&
            totalPages != null &&
            currentPage < totalPages;
        return (orders: orders, hasMore: hasMore);
      }
      return (orders: orders, hasMore: false);
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
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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

  // Preuve de livraison (photo optionnelle) — appel indépendant de
  // deliverOrder pour ne jamais bloquer la confirmation de livraison sur un
  // échec d'upload.
  Future<Map<String, dynamic>> uploadProofPhoto(String id, File file) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: 'proof.jpg'),
      });
      final response = await _dio.post('/orders/$id/proof-photo', data: form);
      final data = response.data as Map<String, dynamic>;
      return (data['order'] ?? data) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de l\'envoi de la photo.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> confirmPayment(
    String id,
    String status, {
    String? note,
  }) async {
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
      final response = await _dio.get(
        '/orders/surge',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      return ((response.data['surgeMultiplier'] as num?) ?? 1.0).toDouble();
    } on DioException {
      return 1.0;
    }
  }

  /// Estimation officielle depuis le backend (source de vérité unique).
  /// Retourne null si hors ligne — l'appelant affiche un fallback.
  Future<Map<String, dynamic>?> getEstimate({
    required double pickupLat,
    required double pickupLng,
    required double deliveryLat,
    required double deliveryLng,
    String orderType = 'DELIVERY',
    String priority = 'NORMAL',
  }) async {
    debugPrint(
      '[getEstimate] CALLING pickup=($pickupLat,$pickupLng) delivery=($deliveryLat,$deliveryLng)',
    );
    try {
      final res = await _dio.get(
        '/orders/estimate',
        queryParameters: {
          'pickupLat': pickupLat,
          'pickupLng': pickupLng,
          'deliveryLat': deliveryLat,
          'deliveryLng': deliveryLng,
          'orderType': orderType,
          'priority': priority,
        },
      );
      debugPrint('[getEstimate] OK: ${res.data}');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      debugPrint(
        '[getEstimate] ERROR ${e.response?.statusCode} ${e.response?.data} ${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint('[getEstimate] UNEXPECTED: $e');
      return null;
    }
  }

  /// Aperçu de la promo applicable à cette commande, AVANT création — la
  /// vraie source de vérité reste toujours createOrder côté serveur, qui
  /// refait le calcul indépendamment (jamais fait confiance à ce que
  /// renverrait un preview manipulé). Sans [code] : meilleure campagne
  /// auto-appliquée (peut renvoyer null, ce n'est pas une erreur). Avec
  /// [code] : throw une [AppException] si le code n'est pas valide/éligible.
  Future<Map<String, dynamic>?> getPromoPreview({
    required int price,
    required int demFee,
    String? code,
  }) async {
    try {
      final res = await _dio.get(
        '/orders/promo/preview',
        queryParameters: {
          'price': price,
          'demFee': demFee,
          if (code != null && code.isNotEmpty) 'code': code,
        },
      );
      final data = res.data as Map<String, dynamic>;
      return data['discountAmount'] != null &&
              (data['discountAmount'] as num) > 0
          ? data
          : null;
    } on DioException catch (e) {
      if (code != null && code.isNotEmpty) {
        throw AppException(
          e.response?.data?['message'] ?? 'Code promo invalide.',
          e.response?.statusCode,
        );
      }
      return null; // aperçu silencieux (auto-apply) — jamais bloquant
    }
  }

  /// Validation "à froid" d'un code — sans commande en cours (voir écran
  /// dédié "Code promo"). Confirme juste que le code existe et est éligible,
  /// sans calculer de montant précis (aucun prix connu à ce stade).
  Future<Map<String, dynamic>> validatePromoCode(String code) async {
    try {
      final res = await _dio.get(
        '/promo/validate',
        queryParameters: {'code': code},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Code promo invalide.',
        e.response?.statusCode,
      );
    }
  }

  /// Promo à mettre en avant à l'ouverture de l'app (popup d'accueil) —
  /// `null` si aucune, ce n'est pas une erreur (jamais bloquant).
  Future<Map<String, dynamic>?> getHighlightPromo() async {
    try {
      final res = await _dio.get('/promo/highlight');
      return res.data as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Tournée groupée (1 collecte, 2-3 destinations, -20%) ──────────────────
  // Même moteur que les tournées DEM Pro côté serveur (voir
  // dem_pro/batch.service.js), exposé ici sous /orders/batch pour un client
  // normal — plafond d'arrêts et réduction déjà appliqués côté serveur, cet
  // écran ne fait qu'afficher ce qui revient.

  /// Aperçu de prix live (sans créer la tournée) pendant que le client ajoute
  /// ses arrêts — `AppException` si moins de 2 ou plus de 3 arrêts.
  Future<Map<String, dynamic>> estimateBatch({
    required double pickupLatitude,
    required double pickupLongitude,
    required List<Map<String, dynamic>> stops,
  }) async {
    try {
      final res = await _dio.post(
        '/orders/batch/estimate',
        data: {
          'pickupLatitude': pickupLatitude,
          'pickupLongitude': pickupLongitude,
          'stops': stops,
        },
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de calculer le prix.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> createBatch(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/orders/batch', data: data);
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
      final res = await _dio.get('/orders/batch/mine');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les tournées.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getBatchById(String id) async {
    try {
      final res = await _dio.get('/orders/batch/mine/$id');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Tournée introuvable.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> cancelBatch(String id) async {
    try {
      await _dio.delete('/orders/batch/mine/$id');
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'annuler la tournée.',
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getHeatmap({
    int hours = 24,
    String? type,
  }) async {
    try {
      final response = await _dio.get(
        '/orders/heatmap',
        queryParameters: {'hours': hours, 'type': ?type},
      );
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
      await _dio.post(
        '/ratings',
        data: {
          'orderId': orderId,
          'ratedId': driverId,
          'score': score,
          'comment': comment,
        },
      );
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

  /// Lance un paiement en ligne (SamirPay) pour cette commande — alternative
  /// optionnelle au cash à la livraison. Le QR affiché est l'image fournie
  /// par SamirPay pour Orange Money, ou généré côté app à partir du lien
  /// pour Wave (voir SamirpayPaymentSheet) — les deux apps ont un scanner
  /// intégré capable de lire ce type de QR.
  Future<Map<String, dynamic>> payOnline(String id, String operatorName) async {
    try {
      final response = await _dio.post(
        '/orders/$id/pay',
        data: {'operatorName': operatorName},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ??
            'Impossible de lancer le paiement en ligne.',
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

  /// Propage l'échec (pas de catch silencieux) — [LocationQueueService] s'en
  /// sert pour distinguer succès/échec et gérer la mise en file d'attente.
  Future<void> updateDriverLocation(double lat, double lng) async {
    await _dio.patch('/users/driver/location', data: {'lat': lat, 'lng': lng});
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
    double? lat,
    double? lng,
  }) async {
    try {
      final response = await _dio.post(
        '/orders/$orderId/report',
        data: {
          'type': type,
          if (message != null && message.isNotEmpty) 'message': message,
          if (lat != null && lng != null) 'lat': lat,
          if (lat != null && lng != null) 'lng': lng,
        },
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
