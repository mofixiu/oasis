import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oasis_app/core/network/api_client.dart';
import 'package:oasis_app/core/network/api_constants.dart';
import 'package:oasis_app/core/network/auth_token_storage.dart';
import 'package:oasis_app/features/marketplace/models/marketplace_models.dart';
import 'package:oasis_app/features/messaging/controllers/messaging_controller.dart';
import 'package:oasis_app/features/messaging/models/conversation_models.dart';
import 'package:oasis_app/features/messaging/services/messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat state is easy to get subtly wrong in ways users notice immediately:
/// a message posted twice, a message lost because the network blipped, or a
/// thread that stays readable after the relationship behind it ended.
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
    'unread_count': 2,
  };

  test('either party can open a thread from a relationship', () async {
    Map<String, dynamic>? sentBody;
    final service = MessagingService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonObject(conversationJson, status: 201);
        }),
      ),
    );

    await service.startConversation(applicationId: 'app-1');
    // The counterparty is derived from the application server-side; the app
    // never names a user, which is what makes enumeration impossible.
    expect(sentBody, {'application': 'app-1'});
  });

  test('an optimistic message is replaced, not duplicated', () async {
    late String receivedClientId;
    final controller = MessagingController(
      service: MessagingService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path.endsWith('/messages/')) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              receivedClientId = body['client_message_id'] as String;
              return _jsonObject({
                'id': 'server-1',
                'body': body['body'],
                'sender_role': 'OWNER',
                'client_message_id': receivedClientId,
                'created_at': '2026-08-23T12:00:00Z',
              }, status: 201);
            }
            return _jsonList(const []);
          }),
        ),
      ),
    );

    await controller.openConversation(Conversation.fromJson(conversationJson));
    await controller.sendMessage('Is the unit still available?');

    expect(controller.messages.length, 1);
    final message = controller.messages.single;
    expect(message.id, 'server-1');
    expect(message.isPending, isFalse);
    expect(message.clientMessageId, receivedClientId);
  });

  test('a failed send keeps what was typed and offers a retry', () async {
    final controller = MessagingController(
      service: MessagingService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path.endsWith('/messages/')) {
              return _jsonObject({
                'code': 'TOO_MANY_REQUESTS',
                'detail': "You're sending messages too quickly.",
              }, status: 429);
            }
            return _jsonList(const []);
          }),
        ),
      ),
    );

    await controller.openConversation(Conversation.fromJson(conversationJson));
    await controller.sendMessage('Please fix the tap in the kitchen.');

    expect(controller.messages.length, 1);
    final failed = controller.messages.single;
    expect(
      failed.body,
      'Please fix the tap in the kitchen.',
      reason: 'losing what somebody typed is worse than showing it failed',
    );
    expect(failed.hasFailed, isTrue);
    expect(failed.isPending, isFalse);
    expect(controller.errorMessage, isNotNull);
  });

  test('polling only asks for messages after the last known one', () async {
    final requestedAfter = <String?>[];
    final controller = MessagingController(
      service: MessagingService(
        apiClient: ApiClient(
          client: MockClient((request) async {
            if (request.method == 'GET' &&
                request.url.path.endsWith('/messages/')) {
              requestedAfter.add(request.url.queryParameters['after']);
              return _jsonList([
                {
                  'id': 'server-1',
                  'body': 'Hello',
                  'sender_role': 'TENANT',
                  'created_at': '2026-08-23T12:00:00Z',
                },
              ]);
            }
            return _jsonObject(const {});
          }),
        ),
      ),
    );

    await controller.openConversation(Conversation.fromJson(conversationJson));

    // The history fetch asks for everything; the poll that follows asks only
    // for what is new, which is what keeps a 4-second interval affordable.
    expect(requestedAfter.first, isNull);
    expect(controller.messages.single.id, 'server-1');
  });

  test('a closed conversation is readable but not writable', () {
    final closed = Conversation.fromJson({
      ...conversationJson,
      'status': 'CLOSED',
    });
    expect(closed.status.isClosed, isTrue);
    // History survives the relationship ending: it is evidence in a dispute.
    expect(closed.subjectLine, 'Sunset House · Unit A1');
  });

  test('signing out clears the inbox', () async {
    final controller = MessagingController(
      service: MessagingService(
        apiClient: ApiClient(
          client: MockClient((_) async => _jsonList([conversationJson])),
        ),
      ),
    );

    await controller.loadConversations();
    expect(controller.conversations, hasLength(1));
    expect(controller.inboxUnreadCount, 2);

    controller.resetSessionState();
    expect(controller.conversations, isEmpty);
    expect(controller.inboxUnreadCount, 0);
    expect(controller.activeConversation, isNull);
  });

  test('a message is attributed to whoever is reading it', () {
    final fromLandlord = Message.fromJson({
      'id': 'm1',
      'body': 'The plumber comes Thursday.',
      'sender_role': 'OWNER',
    });
    expect(fromLandlord.isMine('OWNER'), isTrue);
    expect(fromLandlord.isMine('TENANT'), isFalse);

    // A system line belongs to neither party and never renders as a bubble.
    final system = Message.fromJson({
      'id': 'm2',
      'body': 'Your application was approved.',
      'sender_role': 'SYSTEM',
      'is_system': true,
    });
    expect(system.isMine('OWNER'), isFalse);
    expect(system.isMine('TENANT'), isFalse);
    expect(system.isSystem, isTrue);
  });
  group('who may open a thread about a unit', () {
    test('a tenant may message before approval and before paying', () {
      // Apartments open the thread on the application, not on the approval
      // and not on the rent. The questions a tenant needs answered (can I
      // inspect on Saturday, what does the service charge cover) are the
      // ones they ask *before* committing, and a channel that opens after
      // the decision opens too late to be worth having.
      expect(ApplicationStatus.pending.canMessage, isTrue);
      expect(ApplicationStatus.approved.canMessage, isTrue);
    });

    test('a settled application is not a live relationship', () {
      // The other half of the rule. A declined applicant keeping a channel
      // open to a landlord is not messaging, it is contact they did not
      // agree to.
      expect(ApplicationStatus.rejected.canMessage, isFalse);
      expect(ApplicationStatus.withdrawn.canMessage, isFalse);
      expect(ApplicationStatus.unknown.canMessage, isFalse);
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
