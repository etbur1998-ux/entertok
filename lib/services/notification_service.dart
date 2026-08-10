import 'api_client.dart';
export 'api_client.dart';

class NotificationService {
  // Use singleton ApiClient - no need for setToken as it shares the same instance
  final ApiClient _apiClient = ApiClient();

  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Get all notifications
  Future<Map<String, dynamic>> getNotifications({int page = 1, int pageSize = 20}) async {
    final response = await _apiClient.get('/notifications', queryParams: {
      'page': page.toString(),
      'page_size': pageSize.toString(),
    });
    return {
      'notifications': response['notifications'],
      'unread_count': response['unread_count'],
    };
  }

  // Get unread notification count
  Future<int> getUnreadCount() async {
    final response = await _apiClient.get('/notifications/unread');
    return response['unread_count'];
  }

  // Mark notification as read
  Future<void> markAsRead(int notificationId) async {
    await _apiClient.post('/notifications/$notificationId/read');
  }

  // Mark all notifications as read
  Future<void> markAllAsRead() async {
    await _apiClient.post('/notifications/read-all');
  }

  // Delete a notification
  Future<void> deleteNotification(int notificationId) async {
    await _apiClient.delete('/notifications/$notificationId');
  }
}
