import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../models/conversation_models.dart';

/// Talks to the conversation endpoints.
///
/// Either party may open a thread, but only against a live application or
/// tenancy: the backend derives the counterparty from that relationship, so
/// no request here ever names a user directly.
class MessagingService {
  final ApiClient _apiClient;

  MessagingService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  /// The inbox, newest activity first.
  Future<List<Conversation>> getConversations({
    ConversationStatus? status,
  }) async {
    debugPrint(
      '[MESSAGING SERVICE] Fetching conversations GET ${ApiConstants.conversationsEndpoint}',
    );
    final response = await _apiClient.get(
      ApiConstants.conversationsEndpoint,
      queryParameters: {
        'status': status == null ? null : (status.isClosed ? 'CLOSED' : 'OPEN'),
      },
    );

    // Cursor envelope per the spec, bare list tolerated so the screen still
    // works against a simpler first implementation.
    final rows = response is Map<String, dynamic>
        ? response['results']
        : response;
    if (rows is List) {
      final conversations = rows
          .whereType<Map<String, dynamic>>()
          .map(Conversation.fromJson)
          .toList();
      debugPrint(
        '[MESSAGING SERVICE] Loaded ${conversations.length} conversations',
      );
      return conversations;
    }
    return const [];
  }

  /// Opens (or re-opens) the thread for a relationship.
  ///
  /// Exactly one of [unitId], [applicationId], [agreementId] or
  /// [shortLetBookingId] identifies it. A landlord must pass an application or
  /// agreement, since a unit can have several applicants and the backend will
  /// not guess which one is meant.
  ///
  /// [shortLetBookingId] is the stays equivalent, and the backend only opens
  /// one for a booking that has been paid for: an unpaid request is not yet a
  /// relationship, and a channel to a host before then is a channel to a
  /// stranger.
  ///
  /// Idempotent server-side: tapping "Message" twice returns the same thread.
  Future<Conversation> startConversation({
    String? unitId,
    String? applicationId,
    String? agreementId,
    String? shortLetBookingId,
  }) async {
    assert(
      unitId != null ||
          applicationId != null ||
          agreementId != null ||
          shortLetBookingId != null,
      'A conversation needs a relationship to hang off.',
    );
    debugPrint(
      '[MESSAGING SERVICE] Starting conversation POST ${ApiConstants.conversationsEndpoint}',
    );
    final response = await _apiClient.post(
      ApiConstants.conversationsEndpoint,
      body: {
        if (unitId != null) 'unit': unitId,
        if (applicationId != null) 'application': applicationId,
        if (agreementId != null) 'agreement': agreementId,
        if (shortLetBookingId != null) 'short_let_booking': shortLetBookingId,
      },
    );
    return Conversation.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Message history, or just what is new.
  ///
  /// [afterMessageId] fetches only messages newer than one already held:
  /// this is the polling path, and it is deliberately the cheapest request
  /// this feature makes.
  ///
  /// The parameters are named `since_message_id` and `before_message_id` on
  /// the wire, per API guide 18. They were sent as `after`/`before` until
  /// then, which the backend had never documented and silently ignored, so
  /// every poll re-downloaded the whole thread instead of asking for the two
  /// lines that were new.
  Future<List<Message>> getMessages(
    String conversationId, {
    String? afterMessageId,
    String? beforeCursor,
    int limit = 50,
  }) async {
    final endpoint = ApiConstants.conversationMessagesEndpoint(conversationId);
    final response = await _apiClient.get(
      endpoint,
      queryParameters: {
        'since_message_id': afterMessageId,
        'before_message_id': beforeCursor,
        'limit': '$limit',
      },
    );

    final rows = response is Map<String, dynamic>
        ? response['results']
        : response;
    if (rows is List) {
      return rows
          .whereType<Map<String, dynamic>>()
          .map(Message.fromJson)
          .toList();
    }
    return const [];
  }

  /// Sends a message.
  ///
  /// [clientMessageId] is generated on the device and echoed back, so a retry
  /// after a dropped connection reconciles with the original rather than
  /// posting the same sentence twice.
  Future<Message> sendMessage({
    required String conversationId,
    required String body,
    required String clientMessageId,
  }) async {
    final endpoint = ApiConstants.conversationMessagesEndpoint(conversationId);
    debugPrint('[MESSAGING SERVICE] Sending message POST $endpoint');
    final response = await _apiClient.post(
      endpoint,
      body: {'body': body, 'client_message_id': clientMessageId},
    );
    return Message.fromJson(
      response is Map<String, dynamic> ? response : const {},
    );
  }

  /// Marks the counterparty's messages read up to [upToMessageId].
  Future<void> markRead(String conversationId, {String? upToMessageId}) async {
    final endpoint = ApiConstants.conversationReadEndpoint(conversationId);
    await _apiClient.post(
      endpoint,
      body: {if (upToMessageId != null) 'up_to_message_id': upToMessageId},
    );
  }

  /// Blocks the other person in [conversationId]: the thread closes and
  /// they can no longer message this user (spec v16 §6).
  Future<void> blockConversation(String conversationId, {String? reason}) =>
      _apiClient.post(
        ApiConstants.blockConversationEndpoint(conversationId),
        body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );

  /// Total unread across every thread, for the badge.
  Future<int> getUnreadCount() async {
    final response = await _apiClient.get(
      ApiConstants.conversationsUnreadCountEndpoint,
    );
    if (response is Map<String, dynamic>) {
      return int.tryParse(response['unread_count']?.toString() ?? '') ?? 0;
    }
    return 0;
  }
}
