import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/notification_model.dart';

class NotificationService {
  final ApiClient _apiClient;

  NotificationService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

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
      '[NOTIFICATION SERVICE] Fetching notifications GET ${ApiConstants.notificationsEndpoint} '
      '(type=${type?.queryValue ?? 'any'}, is_read=${isRead ?? 'any'})',
    );
    final response = await _apiClient.get(
      ApiConstants.notificationsEndpoint,
      queryParameters: filters,
    );

    // A bare array is what API guide 18 documents. The `results` envelope is
    // tolerated because every other list in this API grew one the moment it
    // started paginating, and the failure mode here is silent: an envelope
    // read as "not a list" empties the bell and the badge with it, which
    // looks exactly like having no notifications at all.
    final rows = response is Map<String, dynamic>
        ? response['results']
        : response;
    if (rows is List) {
      final notifications = rows
          .whereType<Map<String, dynamic>>()
          .map(NotificationItemModel.fromJson)
          .toList();
      debugPrint(
        '[NOTIFICATION SERVICE] Loaded ${notifications.length} notifications',
      );
      return notifications;
    }
    debugPrint(
      '[NOTIFICATION SERVICE] Unexpected notifications payload: '
      '${response.runtimeType}',
    );
    return [];
  }

  /// Whether the user wants the optional early rent reminder emails.
  ///
  /// Only the 180, 90 and 30-day ones are switchable. The reminders that
  /// actually matter (in-app, 7-day, due-today and overdue) are sent either
  /// way, which is why the setting is one switch rather than a list.
  Future<bool> getEarlyRentReminderEmailsEnabled() async {
    debugPrint(
      '[NOTIFICATION SERVICE] Fetching preferences GET '
      '${ApiConstants.notificationPreferencesEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.notificationPreferencesEndpoint,
    );
    // Absent means on: these emails are opt-out, so treating a missing field
    // as "off" would silently stop reminders the user never turned off.
    return response is Map<String, dynamic>
        ? response['early_rent_reminder_emails_enabled'] != false
        : true;
  }

  Future<bool> setEarlyRentReminderEmailsEnabled(bool enabled) async {
    debugPrint(
      '[NOTIFICATION SERVICE] Saving preferences PATCH '
      '${ApiConstants.notificationPreferencesEndpoint} (enabled=$enabled)',
    );
    final response = await _apiClient.patch(
      ApiConstants.notificationPreferencesEndpoint,
      body: {'early_rent_reminder_emails_enabled': enabled},
    );
    return response is Map<String, dynamic>
        ? response['early_rent_reminder_emails_enabled'] != false
        : enabled;
  }

  /// Mark notification as read
  Future<NotificationItemModel> markNotificationRead(
    String notificationId,
  ) async {
    final endpoint = ApiConstants.markNotificationReadEndpoint(notificationId);
    debugPrint(
      '[NOTIFICATION SERVICE] Marking notification read PATCH $endpoint',
    );
    final response = await _apiClient.patch(endpoint, body: {});
    final notification = NotificationItemModel.fromJson(response);
    debugPrint(
      '[NOTIFICATION SERVICE] Notification marked as read: ID=${notification.id}',
    );
    return notification;
  }
}
