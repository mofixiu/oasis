import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/notification_model.dart';

class NotificationService {
  final ApiClient _apiClient;

  NotificationService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Fetch notifications for authenticated user
  Future<List<NotificationItemModel>> getNotifications() async {
    debugPrint('🔔 [NOTIFICATION SERVICE] Fetching notifications GET ${ApiConstants.notificationsEndpoint}');
    final response = await _apiClient.get(ApiConstants.notificationsEndpoint);
    if (response is List) {
      final notifications = response.map((item) => NotificationItemModel.fromJson(item)).toList();
      debugPrint('🔔 [NOTIFICATION SERVICE] Loaded ${notifications.length} notifications');
      return notifications;
    }
    return [];
  }

  /// Mark notification as read
  Future<NotificationItemModel> markNotificationRead(String notificationId) async {
    final endpoint = ApiConstants.markNotificationReadEndpoint(notificationId);
    debugPrint('🔔 [NOTIFICATION SERVICE] Marking notification read PATCH $endpoint');
    final response = await _apiClient.patch(
      endpoint,
      body: {},
    );
    final notification = NotificationItemModel.fromJson(response);
    debugPrint('🔔 [NOTIFICATION SERVICE] Notification marked as read: ID=${notification.id}');
    return notification;
  }
}
