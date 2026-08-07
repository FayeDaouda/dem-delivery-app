import '../../../core/api/api_client.dart';

class ReferralsRepository {
  /// { total, totalBonus, referrals: [{ referred: {name, createdAt}, bonus, isBonusApplied, createdAt }] }
  Future<Map<String, dynamic>> getMyReferrals() async {
    final res = await ApiClient.dio.get('/users/me/referrals');
    return res.data as Map<String, dynamic>;
  }
}
