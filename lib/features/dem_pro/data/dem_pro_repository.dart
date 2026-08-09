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
  Future<List<Map<String, dynamic>>> getMyOrders({int page = 1, int limit = 50}) async {
    try {
      final res = await _dio.get('/orders/my', queryParameters: {'page': page, 'limit': limit});
      final data = res.data;
      if (data is List) return data.cast<Map<String, dynamic>>();
      if (data is Map && data['orders'] is List) return (data['orders'] as List).cast<Map<String, dynamic>>();
      return [];
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les livraisons.',
        e.response?.statusCode,
      );
    }
  }

  /// CRM léger — clients agrégés sur tout l'historique livré (nom,
  /// téléphone, nombre de commandes, total dépensé, dernière commande).
  Future<List<Map<String, dynamic>>> getClients() async {
    try {
      final res = await _dio.get('/dem-pro/me/clients');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les clients.',
        e.response?.statusCode,
      );
    }
  }

  /// Multi-point de vente — commandes livrées agrégées par point de vente
  /// (voir Order.proAddressId). Les adresses jamais utilisées comme pickup
  /// via le catalogue n'apparaissent pas dans la liste (aucune stat).
  Future<List<Map<String, dynamic>>> getAddressStats() async {
    try {
      final res = await _dio.get('/dem-pro/me/addresses/stats');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (_) {
      return []; // best-effort — jamais bloquant pour l'écran Adresses
    }
  }

  /// Abonnement DEM Pro (palier, statut, fonctionnalités incluses).
  Future<Map<String, dynamic>> getMyPlan() async {
    try {
      final res = await _dio.get('/dem-pro/me/plan');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger l\'abonnement.',
        e.response?.statusCode,
      );
    }
  }

  /// Active/désactive le paiement intégré (voir pilier Wallet DEM Pro).
  Future<Map<String, dynamic>> setInAppPaymentEnabled(bool enabled) async {
    try {
      final res = await _dio.patch(
        '/dem-pro/me/payment-settings',
        data: {'inAppPaymentEnabled': enabled},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de mettre à jour ce réglage.',
        e.response?.statusCode,
      );
    }
  }

  /// Solde + transactions récentes du wallet DEM Pro.
  Future<Map<String, dynamic>> getWalletSummary() async {
    try {
      final res = await _dio.get('/users/dem-pro/wallet');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger le portefeuille.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getWalletTransactions({int page = 1}) async {
    try {
      final res = await _dio.get(
        '/users/dem-pro/wallet/transactions',
        queryParameters: {'page': page},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger l\'historique.',
        e.response?.statusCode,
      );
    }
  }

  /// Requis uniquement si [destinationPhone] diffère du numéro du compte.
  Future<Map<String, dynamic>> requestCashoutOtp(String destinationPhone) async {
    try {
      final res = await _dio.post(
        '/users/dem-pro/wallet/cashout/request-otp',
        data: {'destinationPhone': destinationPhone},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'envoyer le code de confirmation.',
        e.response?.statusCode,
      );
    }
  }

  /// Retrait du solde vers Wave/Orange Money.
  Future<Map<String, dynamic>> requestCashout({
    required int amount,
    required String operatorName,
    String? destinationPhone,
    String? destinationName,
    String? otp,
  }) async {
    try {
      final res = await _dio.post('/users/dem-pro/wallet/cashout', data: {
        'amount': amount,
        'operatorName': operatorName,
        if (destinationPhone != null) 'destinationPhone': destinationPhone,
        if (destinationName != null) 'destinationName': destinationName,
        if (otp != null) 'otp': otp,
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Le retrait a échoué.',
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

  // ── Catalogue produits ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      final res = await _dio.get('/dem-pro/products');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger le catalogue.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> data) async {
    try {
      final res = await _dio.post('/dem-pro/products', data: data);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de créer le produit.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> updateProduct(String id, Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch('/dem-pro/products/$id', data: data);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de modifier le produit.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _dio.delete('/dem-pro/products/$id');
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de supprimer le produit.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> incrementProductUsage(String id) async {
    try {
      await _dio.post('/dem-pro/products/$id/use');
    } on DioException catch (_) {}
  }

  // ── Demandes reçues (lien de commande public) ─────────────────────────────

  Future<List<Map<String, dynamic>>> getOrderRequests({String? status}) async {
    try {
      final res = await _dio.get('/dem-pro/order-requests',
          queryParameters: status != null ? {'status': status} : null);
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les demandes.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> confirmOrderRequest(String id, String orderId) async {
    try {
      final res = await _dio.post('/dem-pro/order-requests/$id/confirm', data: {'orderId': orderId});
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de confirmer la demande.',
        e.response?.statusCode,
      );
    }
  }

  Future<void> rejectOrderRequest(String id) async {
    try {
      await _dio.post('/dem-pro/order-requests/$id/reject');
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de rejeter la demande.',
        e.response?.statusCode,
      );
    }
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

  Future<Map<String, dynamic>> getBusinessInsights(String period) async {
    try {
      final res = await _dio.get('/dem-pro/me/insights', queryParameters: {'period': period});
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les indicateurs.',
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

  Future<void> cancelBatch(String id) async {
    try {
      await _dio.delete('/dem-pro/batch/$id');
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'annuler la tournée.',
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

  Future<List<Map<String, dynamic>>> getRecentDestinations() async {
    try {
      final res = await _dio.get('/dem-pro/me/recent-destinations');
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les destinations récentes.',
        e.response?.statusCode,
      );
    }
  }
}
