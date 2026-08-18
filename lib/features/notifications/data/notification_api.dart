import '../../../core/network/api_client.dart';
import '../domain/app_notification.dart';

class NotificationApi {
  NotificationApi(this._client);

  final ApiClient _client;

  Future<void> registerDevice({
    required String deviceToken,
    required String platform,
  }) async {
    await _client.dio.post<Map<String, dynamic>>(
      '/users/register-device',
      data: {
        'deviceToken': deviceToken,
        'platform': platform,
      },
    );
  }

  Future<NotificationListResult> list() async {
    final res = await _client.dio.get<Map<String, dynamic>>('/notifications');
    return NotificationListResult.fromJson(res.data ?? const {});
  }

  Future<void> markRead(String id) async {
    await _client.dio.put<void>('/notifications/$id/read');
  }

  Future<void> delete(String id) async {
    await _client.dio.delete<void>('/notifications/$id');
  }

  Future<void> clearAll() async {
    await _client.dio.delete<void>('/notifications');
  }
}
