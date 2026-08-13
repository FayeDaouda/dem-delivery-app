import 'dart:io';

import 'package:dio/dio.dart';
import '../../../core/error/app_exception.dart';

// Mêmes champs que DOC_FIELDS côté backend (chefs_de_flotte.service.js).
const List<String> kDriverDocFields = [
  'idCardFront',
  'idCardBack',
  'licenseFront',
  'licenseBack',
  'vehiclePhoto',
  'carteGrise',
  'carteGriseBack',
  'assurance',
  'casquePhoto',
];

class ChefDeFlotteRepository {
  final Dio _dio;
  const ChefDeFlotteRepository(this._dio);

  Future<Map<String, dynamic>> submitOnboarding({
    required String name,
    required String cniRecto,
    required String cniVerso,
    String? companyName,
    String? ninea,
    String? rccm,
  }) async {
    try {
      final res = await _dio.post(
        '/chefs-de-flotte/onboarding',
        data: {
          'name': name,
          'cniRecto': cniRecto,
          'cniVerso': cniVerso,
          if (companyName != null) 'companyName': companyName,
          if (ninea != null) 'ninea': ninea,
          if (rccm != null) 'rccm': rccm,
        },
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de l\'envoi du dossier.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final res = await _dio.get('/chefs-de-flotte/me/stats');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ??
            'Impossible de charger les statistiques.',
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getDrivers({String? status}) async {
    try {
      final res = await _dio.get(
        '/chefs-de-flotte/me/drivers',
        queryParameters: status != null ? {'status': status} : null,
      );
      final list = res.data['drivers'] as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les livreurs.',
        e.response?.statusCode,
      );
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
      final res = await _dio.post(
        '/chefs-de-flotte/me/drivers',
        data: {
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
        },
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'ajouter le livreur.',
        e.response?.statusCode,
      );
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
      final res = await _dio.post(
        '/chefs-de-flotte/onboarding/resubmit',
        data: {
          'cniRecto': cniRecto,
          'cniVerso': cniVerso,
          if (companyName != null) 'companyName': companyName,
          if (ninea != null) 'ninea': ninea,
          if (rccm != null) 'rccm': rccm,
        },
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Erreur lors de la re-soumission.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> requestFleetExtension({
    required int requestedSize,
    required String justification,
  }) async {
    try {
      final res = await _dio.post(
        '/chefs-de-flotte/me/fleet-extension',
        data: {'requestedSize': requestedSize, 'justification': justification},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ??
            'Impossible d\'envoyer la demande d\'extension.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getDriverDetail(String id) async {
    try {
      final res = await _dio.get('/chefs-de-flotte/me/drivers/$id');
      return res.data['driver'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger ce livreur.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> updateDriver(
    String id, {
    required String name,
  }) async {
    try {
      final res = await _dio.patch(
        '/chefs-de-flotte/me/drivers/$id',
        data: {'name': name},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de modifier ce livreur.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> suspendDriver(
    String id, {
    String? reason,
  }) async {
    try {
      final res = await _dio.patch(
        '/chefs-de-flotte/me/drivers/$id/suspend',
        data: {
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de suspendre ce livreur.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> activateDriver(String id) async {
    try {
      final res = await _dio.patch('/chefs-de-flotte/me/drivers/$id/activate');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de réactiver ce livreur.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> resubmitDriver(String id) async {
    try {
      final res = await _dio.patch('/chefs-de-flotte/me/drivers/$id/resubmit');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de resoumettre ce dossier.',
        e.response?.statusCode,
      );
    }
  }

  /// [files] : clé = champ (parmi kDriverDocFields) → fichier local choisi.
  Future<Map<String, dynamic>> uploadDriverDocuments(
    String id, {
    required Map<String, File> files,
    DateTime? insuranceExpiry,
  }) async {
    try {
      final formData = FormData.fromMap({
        for (final entry in files.entries)
          entry.key: await MultipartFile.fromFile(
            entry.value.path,
            filename: entry.value.path.split('/').last,
          ),
        if (insuranceExpiry != null)
          'insuranceExpiry': insuranceExpiry.toIso8601String(),
      });
      final res = await _dio.patch(
        '/chefs-de-flotte/me/drivers/$id/documents',
        data: formData,
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible d\'envoyer les documents.',
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getMyDriversLive() async {
    try {
      final res = await _dio.get('/chefs-de-flotte/me/drivers/live');
      return (res.data['drivers'] as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ??
            'Impossible de charger la position des livreurs.',
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getMyFleetExtensions() async {
    try {
      final res = await _dio.get('/chefs-de-flotte/me/fleet-extension');
      return (res.data['requests'] as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ??
            'Impossible de charger l\'historique des demandes.',
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> getMyIncidents() async {
    try {
      final res = await _dio.get('/chefs-de-flotte/me/incidents');
      return (res.data['incidents'] as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ?? 'Impossible de charger les incidents.',
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> updateMyIncident(
    String id, {
    String? status,
    String? notes,
  }) async {
    try {
      final res = await _dio.patch(
        '/chefs-de-flotte/me/incidents/$id',
        data: {
          if (status != null) 'status': status,
          if (notes != null) 'notes': notes,
        },
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AppException(
        e.response?.data?['message'] ??
            'Impossible de mettre à jour cet incident.',
        e.response?.statusCode,
      );
    }
  }
}
