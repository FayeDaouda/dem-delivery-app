import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';

class WalletRepository {
  final _dio = ApiClient.dio;

  Future<Map<String, dynamic>> getWalletSummary() async {
    try {
      final response = await _dio.get('/users/driver/wallet');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger le portefeuille.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getWalletTransactions({int page = 1}) async {
    try {
      final response = await _dio.get('/users/driver/wallet/transactions', queryParameters: {'page': page});
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger l\'historique.',
        e.response?.statusCode,
      );
    }
  }

  /// Paie la passe journalière directement via SamirPay — pas de recharge
  /// générale au préalable, le montant exact de la passe est payé et la
  /// passe s'active automatiquement dès confirmation (voir
  /// forfait.service.js:activateForfaitFromDirectPayment côté serveur).
  /// [promoCode] optionnel — sinon la meilleure promo DRIVER auto-appliquée
  /// (s'il y en a une) est utilisée automatiquement.
  Future<Map<String, dynamic>> payForfaitOnline(String operatorName, {String? promoCode}) async {
    try {
      final response = await _dio.post('/users/driver/forfait/pay-online', data: {
        'operatorName': operatorName,
        if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de lancer le paiement de la passe.',
        e.response?.statusCode,
      );
    }
  }

  /// Aperçu du prix de la passe avec réduction éventuelle — sans code, tente
  /// juste l'auto-application (retourne null si aucune, jamais d'erreur) ;
  /// avec [code], throw une [AppException] si le code n'est pas valide/éligible.
  Future<Map<String, dynamic>?> getForfaitPromoPreview({String? code}) async {
    try {
      final response = await _dio.get('/users/driver/forfait/promo-preview', queryParameters: {
        if (code != null && code.isNotEmpty) 'code': code,
      });
      return response.data as Map<String, dynamic>;
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

  /// Demande l'envoi d'un code de confirmation — uniquement nécessaire si
  /// [destinationPhone] diffère du numéro du compte du livreur.
  Future<Map<String, dynamic>> requestCashoutOtp(String destinationPhone) async {
    try {
      final response = await _dio.post(
        '/users/driver/wallet/cashout/request-otp',
        data: {'destinationPhone': destinationPhone},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'envoyer le code de confirmation.',
        e.response?.statusCode,
      );
    }
  }

  /// Retrait du solde vers Wave/Orange Money. [destinationPhone]/[destinationName]/[otp]
  /// ne sont requis que si le livreur retire vers un numéro différent du sien.
  Future<Map<String, dynamic>> requestCashout({
    required int amount,
    required String operatorName,
    String? destinationPhone,
    String? destinationName,
    String? otp,
  }) async {
    try {
      final response = await _dio.post('/users/driver/wallet/cashout', data: {
        'amount': amount,
        'operatorName': operatorName,
        if (destinationPhone != null) 'destinationPhone': destinationPhone,
        if (destinationName != null) 'destinationName': destinationName,
        if (otp != null) 'otp': otp,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Le retrait a échoué.',
        e.response?.statusCode,
      );
    }
  }
}
