import 'package:dio/dio.dart';

class AmbassadorRepository {
  final Dio _dio;
  const AmbassadorRepository(this._dio);

  Future<Map<String, dynamic>> submitOnboarding({
    required String cniRecto,
    required String cniVerso,
    String? companyName,
    String? ninea,
    String? rccm,
  }) async {
    final res = await _dio.post('/ambassadors/onboarding', data: {
      'cniRecto': cniRecto,
      'cniVerso': cniVerso,
      if (companyName != null) 'companyName': companyName,
      if (ninea != null) 'ninea': ninea,
      if (rccm != null) 'rccm': rccm,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getStats() async {
    final res = await _dio.get('/ambassadors/me/stats');
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getDrivers({String? status}) async {
    final res = await _dio.get('/ambassadors/me/drivers',
      queryParameters: status != null ? {'status': status} : null);
    final list = res.data['drivers'] as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
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
    final res = await _dio.post('/ambassadors/me/drivers', data: {
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
  }

  Future<Map<String, dynamic>> requestFleetExtension({
    required int requestedSize,
    required String justification,
  }) async {
    final res = await _dio.post('/ambassadors/me/fleet-extension', data: {
      'requestedSize': requestedSize,
      'justification': justification,
    });
    return res.data as Map<String, dynamic>;
  }
}
