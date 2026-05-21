import 'package:dio/dio.dart';
import '../../../core/error/app_exception.dart';

class ChefDeFlotteRepository {
  final Dio _dio;
  const ChefDeFlotteRepository(this._dio);

  Future<Map<String, dynamic>> submitOnboarding({
    required String cniRecto,
    required String cniVerso,
    String? companyName,
    String? ninea,
    String? rccm,
  }) async {
    try {
      final res = await _dio.post('/chefs-de-flotte/onboarding', data: {
        'cniRecto': cniRecto,
        'cniVerso': cniVerso,
        if (companyName != null) 'companyName': companyName,
        if (ninea != null) 'ninea': ninea,
        if (rccm != null) 'rccm': rccm,
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Erreur lors de l\'envoi du dossier.', e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final res = await _dio.get('/chefs-de-flotte/me/stats');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Impossible de charger les statistiques.', e.response?.statusCode);
    }
  }

  Future<List<Map<String, dynamic>>> getDrivers({String? status}) async {
    try {
      final res = await _dio.get('/chefs-de-flotte/me/drivers',
        queryParameters: status != null ? {'status': status} : null);
      final list = res.data['drivers'] as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Impossible de charger les livreurs.', e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> createDriver({
    required String phone,
    required String name,
    String vehicleType = 'MOTO',
    String? licenseFront,
    String? licenseBack,
    String? vehiclePhoto,
    String? carteGrise,
    String? assurance,
    String? insuranceExpiry,
    String? casquePhoto,
  }) async {
    try {
      final res = await _dio.post('/chefs-de-flotte/me/drivers', data: {
        'phone': phone,
        'name': name,
        'vehicleType': vehicleType,
        if (licenseFront != null) 'licenseFront': licenseFront,
        if (licenseBack != null) 'licenseBack': licenseBack,
        if (vehiclePhoto != null) 'vehiclePhoto': vehiclePhoto,
        if (carteGrise != null) 'carteGrise': carteGrise,
        if (assurance != null) 'assurance': assurance,
        if (insuranceExpiry != null) 'insuranceExpiry': insuranceExpiry,
        if (casquePhoto != null) 'casquePhoto': casquePhoto,
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Impossible d\'ajouter le livreur.', e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> resubmitOnboarding({
    required String cniRecto,
    required String cniVerso,
    String? companyName,
    String? ninea,
    String? rccm,
  }) async {
    try {
      final res = await _dio.post('/chefs-de-flotte/onboarding/resubmit', data: {
        'cniRecto': cniRecto,
        'cniVerso': cniVerso,
        if (companyName != null) 'companyName': companyName,
        if (ninea != null) 'ninea': ninea,
        if (rccm != null) 'rccm': rccm,
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Erreur lors de la re-soumission.', e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> requestFleetExtension({
    required int requestedSize,
    required String justification,
  }) async {
    try {
      final res = await _dio.post('/chefs-de-flotte/me/fleet-extension', data: {
        'requestedSize': requestedSize,
        'justification': justification,
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(e.response?.data?['message'] ?? 'Impossible d\'envoyer la demande d\'extension.', e.response?.statusCode);
    }
  }
}
