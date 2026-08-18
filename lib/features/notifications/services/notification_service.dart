import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/notification_model.dart';

class NotificationService {
  final ApiClient _apiClient;

  NotificationService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// Fetch notifications for authenticated user.
  ///
  /// [type] and [isRead] map to the backend's `?type=` / `?is_read=` filters.
  /// Filtering server-side keeps the list correct even once the backend
  /// starts paginating.
  Future<List<NotificationItemModel>> getNotifications({
    NotificationType? type,
    bool? isRead,
  }) async {
    final filters = <String, String?>{
      'type': type?.queryValue,
      'is_read': isRead?.toString(),
    };
    debugPrint(
      '🔔 [NOTIFICATION SERVICE] Fetching notifications GET ${ApiConstants.notificationsEndpoint} '
      '(type=${type?.queryValue ?? 'any'}, is_read=${isRead ?? 'any'})',
    );
    final response = await _apiClient.get(
      ApiConstants.notificationsEndpoint,
      queryParameters: filters,
    );
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
