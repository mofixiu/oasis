import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:landa_app/core/network/api_client.dart';
import 'package:landa_app/core/network/api_constants.dart';
import 'package:landa_app/core/network/auth_token_storage.dart';
import 'package:landa_app/features/notifications/controllers/notification_controller.dart';
import 'package:landa_app/features/notifications/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reminder-email switch decides whether someone is warned that rent is
/// coming. These cover the ways it could quietly lie: showing "off" when the
/// backend never said so, and moving before the backend agreed.
void main() {
  late String originalBaseUrl;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(
      access: 'test-access-token',
      refresh: 'test-refresh-token',
    );
    originalBaseUrl = ApiConstants.baseUrl;
    ApiConstants.baseUrl = 'https://api.example.test/api/users';
  });

  tearDown(() => ApiConstants.baseUrl = originalBaseUrl);

  test('the preference round-trips on its own path', () async {
    final paths = <String>[];
    final methods = <String>[];
    Map<String, dynamic>? sentBody;
    final service = NotificationService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          paths.add(request.url.path);
          methods.add(request.method);
          if (request.method == 'PATCH') {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return _json({'early_rent_reminder_emails_enabled': false});
        }),
      ),
    );

    expect((await service.getPreferences()).earlyRentReminderEmails, isFalse);
    expect(
      (await service.setPreferences(earlyRentReminderEmails: false))
          .earlyRentReminderEmails,
      isFalse,
    );

    expect(paths, [
      '/api/users/notification-preferences/',
      '/api/users/notification-preferences/',
    ]);
    expect(methods, ['GET', 'PATCH']);
    expect(sentBody, {'early_rent_reminder_emails_enabled': false});
  });

  test('a missing flag means on, not off', () async {
    // These emails are opt-out. Reading a missing field as "off" would show
    // someone they had unsubscribed from reminders they never turned off.
    final service = NotificationService(
      apiClient: ApiClient(client: MockClient((_) async => _json({}))),
    );

    final preferences = await service.getPreferences();
    expect(preferences.earlyRentReminderEmails, isTrue);
    // Push is opt-out for the same reason, and is absent from this payload
    // exactly as it is from a backend that predates API guide 19.
    expect(preferences.pushNotifications, isTrue);
  });

  test('a preference save sends only the switch that moved', () async {
    // A PATCH that echoed both values back would overwrite a change made on
    // another device between this app reading the settings and writing them.
    Map<String, dynamic>? sentBody;
    final service = NotificationService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          if (request.method == 'PATCH') {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return _json({'push_notifications_enabled': false});
        }),
      ),
    );

    final saved = await service.setPreferences(pushNotifications: false);

    expect(sentBody, {'push_notifications_enabled': false});
    expect(saved.pushNotifications, isFalse);
    // Untouched by this request, so it keeps the opt-out default.
    expect(saved.earlyRentReminderEmails, isTrue);
  });

  test('the switch does not move until the backend agrees', () async {
    // An optimistic flip that then failed would leave someone believing they
    // had unsubscribed while the emails kept arriving.
    final controller = NotificationController(
      notificationService: NotificationService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({'detail': 'Server error.'}, status: 500),
          ),
        ),
      ),
    );

    expect(await controller.setEarlyRentReminderEmails(false), isFalse);
    expect(
      controller.earlyRentReminderEmails,
      isNull,
      reason:
          'unknown, not "off": the screen falls back to the opt-out default',
    );
    expect(controller.errorMessage, isNotNull);
  });

  test('a failed read is quiet, not an error over the profile', () async {
    // This is a settings row, not the reason anyone opened the screen.
    final controller = NotificationController(
      notificationService: NotificationService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({'detail': 'Server error.'}, status: 500),
          ),
        ),
      ),
    );

    await controller.loadPreferences();

    expect(controller.earlyRentReminderEmails, isNull);
    expect(controller.errorMessage, isNull);
  });

  test('signing out forgets the preference', () async {
    final controller = NotificationController(
      notificationService: NotificationService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => _json({'early_rent_reminder_emails_enabled': false}),
          ),
        ),
      ),
    );

    await controller.loadPreferences();
    expect(controller.earlyRentReminderEmails, isFalse);

    controller.resetSessionState();
    expect(
      controller.earlyRentReminderEmails,
      isNull,
      reason: "one user's choice must not become the next user's switch",
    );
  });
}

http.Response _json(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
