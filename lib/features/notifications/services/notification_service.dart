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

  /// Both switchable notification preferences, in one request.
  ///
  /// `early_rent_reminder_emails_enabled` covers the 180, 90 and 30-day
  /// emails. The reminders that actually matter (in-app, 7-day, due-today
  /// and overdue) are sent either way, which is why it is one switch rather
  /// than a list. `push_notifications_enabled` (API guide 19 §2) governs
  /// phone push across the board.
  ///
  /// Both default to **on** when absent. They are opt-out settings, and
  /// reading a missing field as "off" would silently stop notifications
  /// nobody turned off.
  Future<NotificationPreferences> getPreferences() async {
    debugPrint(
      '[NOTIFICATION SERVICE] Fetching preferences GET '
      '${ApiConstants.notificationPreferencesEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.notificationPreferencesEndpoint,
    );
    return NotificationPreferences.fromJson(response);
  }

  /// Saves whichever preferences were named. Omitted ones are left alone:
  /// this is a `PATCH`, and sending the other switch's current value back
  /// would overwrite a change made on another device between the read and
  /// the write.
  Future<NotificationPreferences> setPreferences({
    bool? earlyRentReminderEmails,
    bool? pushNotifications,
  }) async {
    final body = <String, dynamic>{
      if (earlyRentReminderEmails != null)
        'early_rent_reminder_emails_enabled': earlyRentReminderEmails,
      if (pushNotifications != null)
        'push_notifications_enabled': pushNotifications,
    };
    debugPrint(
      '[NOTIFICATION SERVICE] Saving preferences PATCH '
      '${ApiConstants.notificationPreferencesEndpoint} ($body)',
    );
    final response = await _apiClient.patch(
      ApiConstants.notificationPreferencesEndpoint,
      body: body,
    );
    return NotificationPreferences.fromJson(response);
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

/// The user's switchable notification settings.
class NotificationPreferences {
  final bool earlyRentReminderEmails;
  final bool pushNotifications;

  const NotificationPreferences({
    this.earlyRentReminderEmails = true,
    this.pushNotifications = true,
  });

  factory NotificationPreferences.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return const NotificationPreferences();
    return NotificationPreferences(
      earlyRentReminderEmails:
          json['early_rent_reminder_emails_enabled'] != false,
      pushNotifications: json['push_notifications_enabled'] != false,
    );
  }
}
