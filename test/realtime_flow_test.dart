import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/core/network/realtime_socket.dart';
import 'package:oasis_app/features/messaging/controllers/messaging_controller.dart';
import 'package:oasis_app/features/messaging/models/conversation_models.dart';
import 'package:oasis_app/features/messaging/services/messaging_service.dart';
import 'package:oasis_app/features/notifications/controllers/notification_controller.dart';
import 'package:oasis_app/features/notifications/models/notification_model.dart';
import 'package:oasis_app/features/notifications/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Realtime is the difference between a chat people use and one they close.
///
/// The three things pinned here are the three that were actually wrong, and
/// none of them is visible in a screenshot of a working conversation:
///
/// * a thread with nothing in it never fetched its **first** message, so the
///   only way to see one was to leave the screen and come back;
/// * the Messages badge was derived from a list that is empty until the inbox
///   has been opened, so the dot only appeared after visiting the screen it
///   exists to advertise;
/// * an open thread and an unfetched one rendered identically, so a thread
///   with forty messages greeted the user with "Say hello".
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

  const conversationJson = {
    'id': 'conv-1',
    'status': 'OPEN',
    'context_type': 'APPLICATION',
    'property': {'name': 'Sunset House'},
    'unit': {'unit_number': 'A1'},
    'counterparty': {'full_name': 'Ada Okafor', 'role': 'TENANT'},
    'unread_count': 0,
  };

  group('the socket frame contract', () {
    test('a nested payload and a flat one both decode', () {
      final nested = RealtimeEvent.tryParse(
        jsonEncode({
          'type': 'message.created',
          'data': {'conversation_id': 'conv-1'},
        }),
      );
      expect(nested?.type, 'message.created');
      expect(nested?.data['conversation_id'], 'conv-1');

      // A server that puts the fields beside the discriminator rather than
      // under a `data` key is still readable: the app must not need the
      // backend to pick one of two equally reasonable shapes.
      final flat = RealtimeEvent.tryParse(
        jsonEncode({'type': 'message.created', 'conversation_id': 'conv-2'}),
      );
      expect(flat?.type, 'message.created');
      expect(flat?.data['conversation_id'], 'conv-2');
      // The discriminator is not left in the payload for a model to trip on.
      expect(flat?.data.containsKey('type'), isFalse);
    });

    test('junk on the wire is dropped, not thrown', () {
      // The socket is a freshness optimisation and every screen behind it
      // still fetches. A frame the app cannot read must cost nothing.
      expect(RealtimeEvent.tryParse('not json'), isNull);
      expect(RealtimeEvent.tryParse(''), isNull);
      expect(RealtimeEvent.tryParse(jsonEncode({'no': 'type'})), isNull);
      expect(RealtimeEvent.tryParse(jsonEncode([1, 2, 3])), isNull);
    });
  });

  group('an open thread', () {
    test('is a skeleton until it has answered, never an empty state', () async {
      final controller = MessagingController(
        service: MessagingService(
          apiClient: ApiClient(
            client: MockClient(
              (_) async => _jsonList([
                {'id': 'm1', 'body': 'Hello', 'sender_role': 'TENANT'},
              ]),
            ),
          ),
        ),
      );

      // Before anything is asked for: no messages *and* not loading, which is
      // exactly the state that used to render "Say hello".
      expect(controller.hasLoaded(MessagingController.kThreadKey), isFalse);

      await controller.openConversation(
        Conversation.fromJson(conversationJson),
      );
      expect(controller.hasLoaded(MessagingController.kThreadKey), isTrue);
      expect(controller.messages, hasLength(1));

      // Leaving forgets it, so the next thread opened shows its own skeleton
      // rather than inheriting this one's answered state.
      controller.closeConversation();
      expect(controller.hasLoaded(MessagingController.kThreadKey), isFalse);
    });

    test('a thread that failed to load still counts as answered', () async {
      final controller = MessagingController(
        service: MessagingService(
          apiClient: ApiClient(
            client: MockClient(
              (_) async => http.Response('{"detail":"Nope."}', 500),
            ),
          ),
        ),
      );

      await controller.openConversation(
        Conversation.fromJson(conversationJson),
      );
      // Otherwise the screen shimmers for ever over an error it could have
      // offered a retry for.
      expect(controller.hasLoaded(MessagingController.kThreadKey), isTrue);
      expect(controller.hasError, isTrue);
    });
  });

  group('a message arriving over the socket', () {
    test('lands in the thread that is open', () async {
      final controller = MessagingController(
        service: MessagingService(
          apiClient: ApiClient(client: MockClient((_) async => _jsonList([]))),
        ),
      );
      await controller.openConversation(
        Conversation.fromJson(conversationJson),
      );

      final popup = controller.applyIncomingMessage(
        conversationId: 'conv-1',
        message: Message.fromJson({
          'id': 'm9',
          'body': 'Can I see it Saturday?',
          'sender_role': 'TENANT',
        }),
      );

      expect(controller.messages.single.id, 'm9');
      // Null means "do not interrupt": the user is looking at this thread.
      expect(popup, isNull);
    });

    test('bumps the badge on a thread that is not', () async {
      final controller = MessagingController(
        service: MessagingService(
          apiClient: ApiClient(
            client: MockClient((_) async => _jsonList([conversationJson])),
          ),
        ),
      );
      await controller.loadConversations();
      expect(controller.unreadCount, 0);

      final popup = controller.applyIncomingMessage(
        conversationId: 'conv-1',
        message: Message.fromJson({
          'id': 'm9',
          'body': 'Can I see it Saturday?',
          'sender_role': 'TENANT',
        }),
      );

      expect(controller.unreadCount, 1);
      expect(controller.conversations.single.unreadCount, 1);
      expect(controller.conversations.single.lastMessage?.id, 'm9');
      // Worth a popup: the user is somewhere else in the app.
      expect(popup?.counterparty.displayName, 'Ada Okafor');
    });

    test('the echo of a sent message replaces its optimistic bubble', () async {
      var messagePosts = 0;
      final controller = MessagingController(
        service: MessagingService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.method == 'GET') return _jsonList([]);
              messagePosts++;
              return _jsonObject({
                'id': 'server-1',
                'body': 'On my way.',
                'sender_role': 'OWNER',
                'client_message_id':
                    (jsonDecode(request.body)
                        as Map<String, dynamic>)['client_message_id'],
              }, status: 201);
            }),
          ),
        ),
      );
      await controller.openConversation(
        Conversation.fromJson(conversationJson),
      );
      await controller.sendMessage('On my way.');
      expect(messagePosts, 1);
      expect(controller.messages, hasLength(1));

      // The server also pushes it down the socket. Matched on the client id,
      // so the sender does not watch their own sentence appear twice.
      controller.applyIncomingMessage(
        conversationId: 'conv-1',
        message: controller.messages.single,
      );
      expect(controller.messages, hasLength(1));
    });
  });

  group('the fallback poll', () {
    test('fetches the first message of an empty thread', () async {
      // The bug, exactly: an empty thread has no message to anchor `after=`
      // to, so the poll used to give up on every tick and the counterparty's
      // opening line only appeared if the user left the screen and came back.
      final requests = <Uri>[];
      var replied = false;
      final controller = MessagingController(
        service: MessagingService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              if (request.method != 'GET') return _jsonList([]);
              requests.add(request.url);
              if (!replied) {
                replied = true;
                return _jsonList([]);
              }
              return _jsonList([
                {
                  'id': 'm1',
                  'body': 'Yes, Saturday works.',
                  'sender_role': 'OWNER',
                },
              ]);
            }),
          ),
        ),
      );

      await controller.openConversation(
        Conversation.fromJson(conversationJson),
      );
      expect(controller.messages, isEmpty);

      await controller.pollNow();

      expect(controller.messages.single.id, 'm1');
      // Asked from the top rather than from an anchor it does not have.
      expect(
        requests.last.queryParameters.containsKey('since_message_id'),
        isFalse,
      );
    });

    test('asks only for what is newer once there is an anchor', () async {
      final requests = <Uri>[];
      final controller = MessagingController(
        service: MessagingService(
          apiClient: ApiClient(
            client: MockClient((request) async {
              requests.add(request.url);
              if (requests.length == 1) {
                return _jsonList([
                  {'id': 'm1', 'body': 'Hello', 'sender_role': 'TENANT'},
                ]);
              }
              return _jsonList([]);
            }),
          ),
        ),
      );

      await controller.openConversation(
        Conversation.fromJson(conversationJson),
      );
      await controller.pollNow();

      // The whole reason polling is affordable: the ordinary tick is a
      // request for nothing, not a re-download of the thread.
      expect(requests.last.queryParameters['since_message_id'], 'm1');
    });
  });

  test('the Messages badge is known before the inbox is opened', () async {
    var unreadCountRequests = 0;
    final controller = MessagingController(
      service: MessagingService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            unreadCountRequests++;
            expect(request.url.path, endsWith('/conversations/unread-count/'));
            return _jsonObject({'unread_count': 3});
          }),
        ),
      ),
    );

    // No inbox fetch anywhere in this test: this is the dashboard's path.
    await controller.refreshUnreadCount();

    expect(unreadCountRequests, 1);
    expect(controller.unreadCount, 3);
    // The derived number is still zero, which is precisely why the badge
    // cannot be read from it.
    expect(controller.inboxUnreadCount, 0);
  });

  group('a notification arriving over the socket', () {
    NotificationController build() => NotificationController(
      notificationService: NotificationService(
        apiClient: ApiClient(client: MockClient((_) async => _jsonList([]))),
      ),
    );

    Map<String, dynamic> payload(String id) => {
      'id': id,
      'notification_type': 'SHORT_LET_BOOKING_REQUESTED',
      'message': 'Ada asked for 12–14 March.',
      'is_read': false,
      'created_at': '2026-09-05T09:00:00Z',
    };

    test('is filed and counted without a refetch', () {
      final controller = build();
      final filed = controller.applyIncomingNotification(payload('n1'));

      expect(filed?.id, 'n1');
      expect(controller.notifications.single.id, 'n1');
      expect(controller.unreadCount, 1);
    });

    test('a replayed one is not counted twice', () {
      // Sockets reconnect, and a server that replays what it believes was
      // missed will resend. The same id is one event.
      final controller = build();
      controller.applyIncomingNotification(payload('n1'));
      final again = controller.applyIncomingNotification(payload('n1'));

      expect(again, isNull);
      expect(controller.notifications, hasLength(1));
      expect(controller.unreadCount, 1);
    });

    test('the first poll of a session seeds, it does not shout', () async {
      // Opening the app to eleven unread notifications must not produce
      // eleven banners. The first poll only records what is already there.
      var rows = [payload('n1'), payload('n2')];
      final controller = NotificationController(
        notificationService: NotificationService(
          apiClient: ApiClient(
            client: MockClient((_) async => _jsonList(rows)),
          ),
        ),
      );

      expect(await controller.pollForNewNotifications(), isEmpty);
      // The badge is still correct: it is the *interruption* that is held
      // back, not the count.
      expect(controller.unreadCount, 2);

      rows = [payload('n3'), ...rows];
      final fresh = await controller.pollForNewNotifications();

      expect(fresh.map((n) => n.id), ['n3']);
      expect(controller.unreadCount, 3);
    });

    test('does not appear in a list it has been filtered out of', () async {
      final controller = build();
      await controller.applyFilters(type: NotificationType.rentDue);

      final filed = controller.applyIncomingNotification(payload('n1'));

      // Still returned, so it can still raise a popup, and still counted:
      // the badge counts everything. But it does not silently break the
      // filter the user is looking at.
      expect(filed?.id, 'n1');
      expect(controller.unreadCount, 1);
      expect(controller.notifications, isEmpty);
    });
  });
}

http.Response _jsonObject(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _jsonList(List<Map<String, dynamic>> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
