import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/load_failure.dart';
import '../../../core/network/realtime_socket.dart';
import '../../../core/session/session_scope.dart';
import '../models/conversation_models.dart';
import '../services/messaging_service.dart';
import '../../../core/network/api_client.dart';

/// Holds the inbox and the currently open thread.
///
/// Messages arrive two ways, and the order matters:
///
/// 1. **The realtime socket**, when it is up. A message the other party sends
///    is on screen in well under a second, and nothing has to be refetched.
/// 2. **Polling**, when it is not. The app asks for anything newer than the
///    last message it holds, every few seconds, only while a thread is open.
///
/// The second is a fallback rather than a mode: [startPolling] keeps its
/// timer running the whole time and simply skips the request while the socket
/// is connected, so a socket that drops mid-conversation is covered on the
/// next tick without anything having to notice.
class MessagingController extends ChangeNotifier
    with LoadFailureState, LoadedOnceState
    implements SessionScopedController {
  final MessagingService _service;

  MessagingController({MessagingService? service})
    : _service = service ?? MessagingService();

  /// [LoadedOnceState] keys. The inbox and an open thread answer different
  /// questions and neither says anything about the other: a loaded inbox
  /// must not make an unfetched thread look like an empty one.
  static const String kInboxKey = 'inbox';
  static const String kThreadKey = 'thread';

  /// How often an open thread checks for new messages, when the socket is
  /// not carrying them.
  static const Duration pollInterval = Duration(seconds: 4);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isSending = false;
  bool get isSending => _isSending;

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  Conversation? _activeConversation;
  Conversation? get activeConversation => _activeConversation;

  List<Message> _messages = [];
  List<Message> get messages => _messages;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  Timer? _pollTimer;

  /// Total unread across the inbox, for the badge.
  int get inboxUnreadCount =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  @override
  void resetSessionState() {
    stopPolling();
    _conversations = [];
    _activeConversation = null;
    _messages = [];
    _unreadCount = 0;
    _isLoading = false;
    _isSending = false;
    resetLoadedState();
    clearFailure();
    notifyListeners();
  }

  Future<void> loadConversations() async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _conversations = await _service.getConversations();
      _unreadCount = inboxUnreadCount;
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      markLoaded(kInboxKey);
      notifyListeners();
    }
  }

  /// Blocks the other person in [conversation] and closes the thread here
  /// straight away. False, with [errorMessage] set, when it could not be done;
  /// a 404 means the backend has not shipped blocking yet.
  Future<bool> blockConversation(
    Conversation conversation, {
    String? reason,
  }) async {
    clearFailure();
    try {
      await _service.blockConversation(conversation.id, reason: reason);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        captureFailure(
          ApiException('Blocking is not available yet.', statusCode: 404),
        );
      } else {
        captureFailure(e);
      }
      notifyListeners();
      return false;
    } catch (e) {
      captureFailure(e);
      notifyListeners();
      return false;
    }

    final closed = conversation.copyWith(status: ConversationStatus.closed);
    _conversations = [
      for (final item in _conversations)
        if (item.id == conversation.id) closed else item,
    ];
    if (_activeConversation?.id == conversation.id) {
      _activeConversation = closed;
    }
    notifyListeners();
    return true;
  }

  /// Refreshes only the badge number, without pulling the whole inbox.
  ///
  /// This is what puts the dot on the Messages button for somebody who has
  /// never opened the inbox. [inboxUnreadCount] is derived from
  /// [conversations], so before the list has been fetched it is zero, which
  /// is why the badge used to appear only *after* visiting the screen it was
  /// supposed to be advertising. Both dashboards call this on load.
  ///
  /// Quiet on failure: a badge is not worth an error state, and the previous
  /// number is a better answer than a zero the app cannot vouch for.
  Future<void> refreshUnreadCount() async {
    try {
      final count = await _service.getUnreadCount();
      if (count == _unreadCount) return;
      _unreadCount = count;
      notifyListeners();
    } catch (e) {
      debugPrint('[MESSAGING] Could not read the unread count: $e');
    }
  }

  /// Opens a thread and loads its history.
  Future<void> openConversation(Conversation conversation) async {
    _activeConversation = conversation;
    _messages = [];
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      _messages = await _service.getMessages(conversation.id);
      await _markReadLocally();
    } catch (e) {
      captureFailure(e);
    } finally {
      _isLoading = false;
      // Marked here rather than on success, so a thread that failed to load
      // shows its error state instead of a skeleton that never resolves.
      markLoaded(kThreadKey);
      notifyListeners();
    }
  }

  /// Starts (or re-opens) a thread for a relationship, then loads it.
  ///
  /// Returns null on failure; the caller shows [errorMessage], which for the
  /// common refusals is already a sentence worth reading: "You can only
  /// message a landlord after applying for one of their units."
  Future<Conversation?> startConversation({
    String? unitId,
    String? applicationId,
    String? agreementId,
    String? shortLetBookingId,
  }) async {
    _isLoading = true;
    clearFailure();
    notifyListeners();

    try {
      final conversation = await _service.startConversation(
        unitId: unitId,
        applicationId: applicationId,
        agreementId: agreementId,
        shortLetBookingId: shortLetBookingId,
      );
      // Replace rather than prepend: the backend returns the existing thread
      // when there is one, and a duplicate row in the inbox would be a bug.
      _conversations = [
        conversation,
        ..._conversations.where((c) => c.id != conversation.id),
      ];
      await openConversation(conversation);
      return conversation;
    } catch (e) {
      captureFailure(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sends a message, showing it immediately and reconciling when it lands.
  ///
  /// The optimistic bubble carries the same `client_message_id` the request
  /// does, so the server's copy replaces it instead of appearing beside it.
  Future<void> sendMessage(String body) async {
    final conversation = _activeConversation;
    final trimmed = body.trim();
    if (conversation == null || trimmed.isEmpty) return;

    final clientMessageId = _newClientMessageId();
    // A conversation is always exactly one landlord and one tenant, so the
    // counterparty's role determines this device's role. Cheaper and more
    // reliable than reaching into AuthController from here, and it stays
    // correct for a user who holds both roles on different accounts.
    final myRole = conversation.counterparty.role.toUpperCase() == 'TENANT'
        ? 'OWNER'
        : 'TENANT';

    final optimistic = Message(
      id: clientMessageId,
      body: trimmed,
      senderRole: myRole,
      clientMessageId: clientMessageId,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      isPending: true,
    );
    _messages = [..._messages, optimistic];
    _isSending = true;
    clearFailure();
    notifyListeners();

    try {
      final sent = await _service.sendMessage(
        conversationId: conversation.id,
        body: trimmed,
        clientMessageId: clientMessageId,
      );
      _replaceMessage(clientMessageId, sent);
    } catch (e) {
      captureFailure(e);
      // Left in place and marked failed rather than dropped: losing what
      // somebody typed is worse than showing that it did not send.
      _replaceMessage(
        clientMessageId,
        optimistic.copyWith(isPending: false, hasFailed: true),
      );
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  /// Re-sends a message that failed, and drops the failed copy.
  Future<void> retry(Message message) async {
    _messages = _messages
        .where((m) => m.clientMessageId != message.clientMessageId)
        .toList();
    notifyListeners();
    await sendMessage(message.body);
  }

  /// Begins the fallback poll on the open thread.
  ///
  /// The timer runs for as long as the thread is open even when the socket is
  /// up: each tick checks and does nothing. Keeping it armed is what makes a
  /// socket that drops mid-conversation self-healing: the very next tick
  /// takes over, with no reconnect logic anywhere near this class.
  void startPolling() {
    stopPolling();
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollForNewMessages());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Asks for whatever the thread does not already hold.
  ///
  /// Failures here are deliberately silent: a poll that misses is retried in
  /// four seconds, and turning a transient blip into an error banner over a
  /// conversation that is working would be worse than saying nothing.
  Future<void> _pollForNewMessages() async {
    final conversation = _activeConversation;
    if (conversation == null || _isSending) return;
    // The socket is carrying them. Nothing to do.
    if (RealtimeSocket.instance.isConnected) return;

    // Skip optimistic messages: their ids are local and mean nothing server-side.
    final lastServerMessage = _messages.lastWhere(
      (m) => !m.isPending && !m.hasFailed,
      orElse: () => const Message(id: '', body: '', senderRole: ''),
    );
    // No server message yet: an empty thread, or one holding nothing but an
    // unsent bubble. `after=` has nothing to anchor to, so this asks for the
    // thread from the top instead of returning.
    //
    // Returning is what it used to do, and it meant the *first* message the
    // other party ever sent never arrived: an empty thread had no anchor, so
    // the poll bailed out on every tick and the only way to see the message
    // was to leave the screen and come back. That is the "you have to reload
    // before the messages show" bug.
    final isFirstFetch = lastServerMessage.id.isEmpty;

    try {
      final fresh = await _service.getMessages(
        conversation.id,
        afterMessageId: isFirstFetch ? null : lastServerMessage.id,
      );
      if (fresh.isEmpty) return;
      if (_mergeIncoming(fresh)) {
        await _markReadLocally();
        notifyListeners();
      }
    } catch (_) {
      // Intentionally ignored: see above.
    }
  }

  /// Runs one fallback poll immediately.
  ///
  /// Exists so the fallback path can be pinned by a test without waiting out
  /// [pollInterval]: the bug it covers (an empty thread never fetching its
  /// first message) is precisely the one that only shows up on a tick.
  @visibleForTesting
  Future<void> pollNow() => _pollForNewMessages();

  // ------------------------------------------------------------- realtime

  /// True when [conversationId] is the thread currently on screen.
  bool isThreadOpen(String conversationId) =>
      _activeConversation?.id == conversationId;

  /// Applies a `message.created` event pushed down the socket.
  ///
  /// Two quite different things happen depending on where the user is:
  ///
  /// * **The thread is open**: the bubble is appended and the thread is
  ///   marked read, exactly as a poll would have done, only sooner.
  /// * **It is not**: the inbox row's badge goes up and so does the app-bar
  ///   count, so the dot appears wherever the user actually is.
  ///
  /// Returns the conversation the message belongs to when it is one the user
  /// is *not* reading, so the caller can decide whether to interrupt them
  /// with a popup. Null means "already on screen, say nothing".
  Conversation? applyIncomingMessage({
    required String conversationId,
    required Message message,
  }) {
    if (conversationId.isEmpty || message.id.isEmpty) return null;

    if (isThreadOpen(conversationId)) {
      if (_mergeIncoming([message])) {
        // Fire-and-forget: the receipt is not worth blocking the frame, and
        // a failed one is retried the next time the thread is opened.
        _markReadLocally();
        notifyListeners();
      }
      return null;
    }

    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) {
      // A thread this device has never listed: the counterparty just opened
      // it. The badge still has to move; the row arrives with the next inbox
      // fetch, which the inbox screen makes on its own poll.
      _unreadCount++;
      notifyListeners();
      return null;
    }

    final conversation = _conversations[index];
    _conversations = [
      conversation.copyWith(
        lastMessage: message,
        unreadCount: conversation.unreadCount + 1,
      ),
      // Newest activity first, matching the order the backend serves.
      for (final c in _conversations)
        if (c.id != conversationId) c,
    ];
    _unreadCount = inboxUnreadCount;
    notifyListeners();
    return _conversations.first;
  }

  /// Applies a `conversation.updated` event: a thread closing, or its badge
  /// being cleared because the user read it on another device.
  void applyConversationUpdate(Map<String, dynamic> json) {
    final updated = Conversation.fromJson(json);
    if (updated.id.isEmpty) return;

    final index = _conversations.indexWhere((c) => c.id == updated.id);
    if (index == -1) return;
    _conversations = [..._conversations]..[index] = updated;
    if (_activeConversation?.id == updated.id) _activeConversation = updated;
    _unreadCount = inboxUnreadCount;
    notifyListeners();
  }

  /// Folds server messages into the thread, ignoring ones already held and
  /// reconciling any that match an optimistic bubble still on screen.
  ///
  /// Returns whether anything actually changed: callers only notify when it
  /// did, so a poll that finds nothing does not rebuild the thread.
  bool _mergeIncoming(List<Message> incoming) {
    final knownIds = _messages.map((m) => m.id).toSet();
    final knownClientIds = _messages
        .map((m) => m.clientMessageId)
        .where((id) => id.isNotEmpty)
        .toSet();

    var changed = false;
    for (final message in incoming) {
      // The echo of something this device sent, arriving over the socket
      // before (or after) the POST returned. Replaces the optimistic copy
      // rather than sitting beside it.
      if (message.clientMessageId.isNotEmpty &&
          knownClientIds.contains(message.clientMessageId)) {
        _replaceMessage(message.clientMessageId, message);
        changed = true;
        continue;
      }
      if (knownIds.contains(message.id)) continue;
      _messages = [..._messages, message];
      knownIds.add(message.id);
      changed = true;
    }
    return changed;
  }

  /// Tells the backend everything on screen has been seen, and zeroes the
  /// local badge so the inbox does not keep claiming unread messages the user
  /// is currently looking at.
  Future<void> _markReadLocally() async {
    final conversation = _activeConversation;
    if (conversation == null || _messages.isEmpty) return;

    try {
      await _service.markRead(
        conversation.id,
        upToMessageId: _messages.last.id,
      );
    } catch (_) {
      // Read receipts are not worth an error state; the next open retries.
      return;
    }

    _conversations = [
      for (final c in _conversations)
        if (c.id == conversation.id) c.copyWith(unreadCount: 0) else c,
    ];
    _unreadCount = inboxUnreadCount;
  }

  /// Leaves the open thread.
  ///
  /// The thread's loaded flag is dropped with it: the next conversation
  /// opened must show a skeleton, not inherit "already answered" from this
  /// one and render its own empty messages as "no messages yet".
  ///
  /// Deliberately does not notify. It runs from `deactivate()`, while the
  /// screen that is reading this state is on its way out, and notifying a
  /// widget mid-teardown only makes it repaint the cleared state on the way.
  void closeConversation() {
    stopPolling();
    _activeConversation = null;
    _messages = [];
    forgetLoaded(kThreadKey);
  }

  void _replaceMessage(String clientMessageId, Message replacement) {
    _messages = [
      for (final m in _messages)
        if (m.clientMessageId == clientMessageId) replacement else m,
    ];
  }

  String _newClientMessageId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
