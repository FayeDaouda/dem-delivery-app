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
  Future<Map<String, dynamic>> payForfaitOnline(String operatorName) async {
    try {
      final response = await _dio.post('/users/driver/forfait/pay-online', data: {
        'operatorName': operatorName,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de lancer le paiement de la passe.',
        e.response?.statusCode,
      );
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
