import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/core/network/realtime_socket.dart';
import 'package:oasis_app/core/session/realtime_hub.dart';
import 'package:oasis_app/features/messaging/controllers/messaging_controller.dart';
import 'package:oasis_app/features/messaging/services/messaging_service.dart';
import 'package:oasis_app/features/notifications/controllers/notification_controller.dart';
import 'package:oasis_app/features/notifications/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The socket against a real WebSocket server.
///
/// Everything else about realtime can be tested by handing a controller a
/// decoded map, and is. The transport cannot: the things that break it are
/// the handshake, the heartbeat and the reconnect, and none of those exist
/// until there is a server on the other end refusing to play along.
///
/// The three pinned here are the three that would each silently disable the
/// whole feature in production, with no error anywhere:
///
/// * the token going in the wrong place, so every connection is rejected;
/// * the heartbeat running the wrong way round, so the server drops a client
///   it considers gone, which is exactly what the app did until API guide 18
///   documented that the server pings and the client answers;
/// * a token in the URL, which would put a credential in every proxy log
///   between the phone and Render.
void main() {
  late HttpServer server;
  late String originalBaseUrl;

  /// Handshakes seen by the server, so the auth header can be inspected.
  final handshakes = <HttpHeaders>[];

  /// Everything the app has sent up the wire.
  final received = <String>[];

  /// The live socket, so a test can push frames down it.
  WebSocket? clientSocket;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthTokenStorage.clear();
    await AuthTokenStorage.saveTokens(
      access: 'test-access-token',
      refresh: 'test-refresh-token',
    );

    handshakes.clear();
    received.clear();
    clientSocket = null;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      handshakes.add(request.headers);
      final socket = await WebSocketTransformer.upgrade(request);
      clientSocket = socket;
      socket.listen(
        (frame) => received.add(frame.toString()),
        onError: (_) {},
        cancelOnError: true,
      );
    });

    originalBaseUrl = ApiConstants.baseUrl;
    // http, so `realtimeUri()` derives `ws` rather than `wss`.
    ApiConstants.baseUrl =
        'http://${server.address.address}:${server.port}/api/users';
  });

  tearDown(() async {
    await RealtimeSocket.instance.resetForTest();
    await server.close(force: true);
    ApiConstants.baseUrl = originalBaseUrl;
  });

  /// Waits for [check] to pass, or gives up. Real sockets settle across event
  /// loop turns, so there is nothing here to `pump`.
  Future<void> until(
    bool Function() check, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!check()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for the socket to settle.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('the token travels in a header, never in the URL', () async {
    await RealtimeSocket.instance.connect();
    await until(() => handshakes.isNotEmpty);

    expect(
      handshakes.single.value(HttpHeaders.authorizationHeader),
      'Bearer test-access-token',
    );

    // The other half of the rule, and the reason the header was chosen: a URL
    // is written to every proxy and access log between the phone and Render,
    // and a JWT in one is a credential sitting on somebody else's disk.
    final uri = ApiConstants.realtimeUri();
    expect(uri.query, isEmpty);
    expect(uri.toString(), isNot(contains('test-access-token')));
    expect(uri.path, '/ws/realtime/');
    expect(uri.scheme, 'ws');
  });

  test('a server ping is answered with a pong', () async {
    await RealtimeSocket.instance.connect();
    await until(() => RealtimeSocket.instance.isConnected);

    // The heartbeat runs server-first (API guide 18): it pings every 25
    // seconds and expects an answer. The app used to ping *and* ignore the
    // server's, which meant a server entitled to consider a silent client
    // gone would drop a connection the app believed was fine.
    clientSocket!.add(jsonEncode({'type': 'ping'}));
    await until(() => received.isNotEmpty);

    expect(jsonDecode(received.single)['type'], 'pong');
  });

  test('the heartbeat is not delivered to the app as an event', () async {
    final seen = <String>[];
    final subscription = RealtimeSocket.instance.events.listen(
      (event) => seen.add(event.type),
    );
    addTearDown(subscription.cancel);

    await RealtimeSocket.instance.connect();
    await until(() => RealtimeSocket.instance.isConnected);

    clientSocket!
      ..add(jsonEncode({'type': 'ping'}))
      ..add(jsonEncode({'type': 'pong'}))
      ..add(
        jsonEncode({
          'type': 'notification.created',
          'data': {
            'notification': {'id': 'n1'},
          },
        }),
      );
    await until(() => seen.isNotEmpty);
    // A beat later, so a ping arriving after would have been caught.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Keep-alive is transport business. Waking every controller in the app
    // twice a minute for it would be the socket costing more than it saves.
    expect(seen, ['notification.created']);
  });

  test('events arrive decoded, in order', () async {
    final seen = <RealtimeEvent>[];
    final subscription = RealtimeSocket.instance.events.listen(seen.add);
    addTearDown(subscription.cancel);

    await RealtimeSocket.instance.connect();
    await until(() => RealtimeSocket.instance.isConnected);

    clientSocket!
      ..add(jsonEncode({'type': 'unread.counts'}))
      ..add(
        jsonEncode({
          'type': 'message.created',
          'data': {
            'conversation_id': 'conv-1',
            'message': {'id': 'm1', 'body': 'Hello', 'sender_role': 'TENANT'},
          },
        }),
      )
      // Junk on the wire must cost nothing: the socket is a freshness
      // optimisation and every screen behind it still fetches.
      ..add('not json at all');
    await until(() => seen.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(seen.map((e) => e.type), ['unread.counts', 'message.created']);
    expect(seen.last.data['conversation_id'], 'conv-1');
  });

  test('a dropped connection is reconnected, not given up on', () async {
    await RealtimeSocket.instance.connect();
    await until(() => handshakes.length == 1);

    // What a mobile network does several times an hour.
    await clientSocket!.close();

    // The first backoff step is a second, so this is the app healing itself
    // rather than waiting for the user to notice anything.
    await until(
      () => handshakes.length == 2,
      timeout: const Duration(seconds: 8),
    );
    await until(() => RealtimeSocket.instance.isConnected);
  });

  test('disconnecting stays disconnected', () async {
    await RealtimeSocket.instance.connect();
    await until(() => handshakes.length == 1);

    await RealtimeSocket.instance.disconnect();
    expect(RealtimeSocket.instance.status.value, RealtimeStatus.idle);

    // Sign-out and backgrounding both come through here, and a socket that
    // reconnected itself after either would be holding a connection for a
    // user who has gone.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(handshakes, hasLength(1));
  });

  test('a wrapped conversation.updated reaches the inbox', () async {
    // The payload is `{"conversation": {...}}` per API guide 18. Handing the
    // wrapper to `Conversation.fromJson` reads no id and drops the event in
    // silence: the worst possible failure for a thread being closed,
    // because the app would go on offering a composer that cannot send.
    const conversationJson = {
      'id': 'conv-1',
      'status': 'OPEN',
      'context_type': 'APPLICATION',
      'counterparty': {'full_name': 'Ada Okafor', 'role': 'TENANT'},
      'unread_count': 2,
    };

    final messaging = MessagingController(
      service: MessagingService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode([conversationJson]),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );
    final notifications = NotificationController(
      notificationService: NotificationService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );
    final hub = RealtimeHub(messaging: messaging, notifications: notifications)
      ..start();
    addTearDown(hub.dispose);

    await messaging.loadConversations();
    expect(messaging.conversations.single.status.isClosed, isFalse);

    hub.handleAuthChanged(isAuthenticated: true);
    await until(() => RealtimeSocket.instance.isConnected);

    clientSocket!.add(
      jsonEncode({
        'type': 'conversation.updated',
        'data': {
          'conversation': {...conversationJson, 'status': 'CLOSED'},
        },
      }),
    );

    await until(() => messaging.conversations.single.status.isClosed);
  });

  test('no session means no connection attempt', () async {
    await AuthTokenStorage.clear();

    await RealtimeSocket.instance.connect();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The ordinary state before sign-in. Not an error, and not something to
    // retry in a loop against a server that would only refuse it.
    expect(handshakes, isEmpty);
    expect(RealtimeSocket.instance.status.value, RealtimeStatus.idle);
  });
}
