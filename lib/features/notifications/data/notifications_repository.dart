import '../../../core/api/api_client.dart';

/// Le backend expose déjà tout (voir dem-backend/src/modules/notifications/)
/// — chaque notif push est aussi persistée en base (voir utils/notifications.js
/// :notify) ; seul le centre consultable côté app manquait jusqu'ici.
class NotificationsRepository {
  Future<List<Map<String, dynamic>>> getMyNotifications() async {
    final res = await ApiClient.dio.get('/notifications');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<int> getUnreadCount() async {
    final res = await ApiClient.dio.get('/notifications/unread-count');
    return (res.data['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) async {
    await ApiClient.dio.patch('/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await ApiClient.dio.patch('/notifications/read-all');
  }
}
