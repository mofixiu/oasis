import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/messaging/controllers/messaging_controller.dart';
import '../../features/messaging/models/conversation_models.dart';
import '../../features/messaging/views/conversation_screen.dart';
import '../../features/messaging/views/conversations_screen.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../features/notifications/models/notification_model.dart';
import '../../features/notifications/views/notifications_screen.dart';
import '../network/realtime_socket.dart';
import '../utils/fade_page_route.dart';
import '../utils/oasis_navigator.dart';
import '../widgets/oasis_popup_notification.dart';

/// Turns socket frames into changes in the app.
///
/// [RealtimeSocket] knows how to hold a connection and nothing about Oasis;
/// the controllers know about messages and notifications and nothing about
/// sockets. This is the seam between them, and it lives beside [SessionScope]
/// for the same reason that does: it is composition-root wiring, not a
/// feature, and keeping it in one file is what stops "who updates the badge?"
/// from becoming an archaeology question.
///
/// It owns three things:
///
/// * **When the socket should be up.** Connected while somebody is signed in
///   and the app is in the foreground; closed otherwise. A socket held across
///   a suspension wakes believing it is alive and delivers nothing.
/// * **Where each event goes.** One `switch`, so the full list of things the
///   backend can push is readable in one screen.
/// * **What is worth interrupting the user for.** Popups are raised here
///   rather than inside the controllers, because whether to interrupt depends
///   on where the user *is*, which is a whole-app question.
class RealtimeHub {
  final MessagingController _messaging;
  final NotificationController _notifications;

  /// Set by the composition root once auth exists.
  ///
  /// Late rather than constructor-injected, because [AuthController] is built
  /// lazily by its provider and the hub has to be listening before that
  /// happens: an event can arrive during startup.
  AuthController? _auth;

  RealtimeHub({
    required MessagingController messaging,
    required NotificationController notifications,
  }) : _messaging = messaging,
       _notifications = notifications;

  // ignore: use_setters_to_change_properties
  void attachAuth(AuthController auth) => _auth = auth;

  /// How often the app asks for new notifications itself, while the socket
  /// is not carrying them.
  ///
  /// Deliberately slow. It is one small request for unread rows only, and it
  /// is the difference between popups working today and popups working once
  /// the backend ships its half, but a phone on Nigerian mobile data should
  /// not be paying for a fast poll to find out nothing happened.
  static const Duration fallbackPollInterval = Duration(seconds: 45);

  StreamSubscription<RealtimeEvent>? _subscription;
  VoidCallback? _statusListener;
  Timer? _fallbackTimer;

  /// Whether a session is signed in. The socket also needs the app to be in
  /// the foreground, so the two are tracked separately and the connection is
  /// derived from both.
  bool _hasSession = false;
  bool _isForeground = true;

  /// Starts listening. Idempotent: safe to call from the composition root
  /// without checking whether it already ran.
  void start() {
    _subscription ??= RealtimeSocket.instance.events.listen(_handle);
    // A reconnect can have missed events entirely: the server may or may not
    // replay, and the app must not depend on it doing so. Both badges are
    // re-read from the source of truth whenever the socket comes back up.
    _statusListener ??= () {
      if (RealtimeSocket.instance.status.value == RealtimeStatus.connected) {
        _messaging.refreshUnreadCount();
        _notifications.refreshUnreadCount();
      }
    };
    RealtimeSocket.instance.status.addListener(_statusListener!);
  }

  /// Called whenever the auth state changes. Connects on sign-in, tears down
  /// on sign-out: including the popup queue, which must never survive into
  /// the next user's session.
  void handleAuthChanged({required bool isAuthenticated}) {
    if (_hasSession == isAuthenticated) return;
    _hasSession = isAuthenticated;
    if (!isAuthenticated) OasisPopups.clear();
    _sync();
  }

  /// Called from the root widget's lifecycle observer.
  void handleAppLifecycle(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_isForeground == foreground) return;
    _isForeground = foreground;
    _sync();
  }

  void _sync() {
    if (_hasSession && _isForeground) {
      RealtimeSocket.instance.connect();
      _startFallbackPoll();
    } else {
      RealtimeSocket.instance.disconnect();
      _stopFallbackPoll();
    }
  }

  /// Arms the fallback poll.
  ///
  /// It runs whenever somebody is signed in and looking at the app, and each
  /// tick checks whether the socket is up before spending a request, so the
  /// two never both deliver, and a socket that drops is covered on the next
  /// tick without anything having to coordinate.
  void _startFallbackPoll() {
    _fallbackTimer ??= Timer.periodic(fallbackPollInterval, (_) async {
      if (RealtimeSocket.instance.isConnected) return;
      final fresh = await _notifications.pollForNewNotifications();
      for (final notification in fresh.take(_maxPopupsPerPoll)) {
        _showNotificationPopup(notification);
      }
      // The Messages dot is derived from a different count, and a poll is the
      // only thing that moves it while the socket is down.
      await _messaging.refreshUnreadCount();
    });
  }

  /// A burst larger than this is a backlog arriving, not news. The rest are
  /// still in the list behind the bell, which is where a backlog belongs.
  static const int _maxPopupsPerPoll = 2;

  void _stopFallbackPoll() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  void dispose() {
    _stopFallbackPoll();
    _subscription?.cancel();
    _subscription = null;
    if (_statusListener != null) {
      RealtimeSocket.instance.status.removeListener(_statusListener!);
      _statusListener = null;
    }
  }

  // ---------------------------------------------------------------- routing

  void _handle(RealtimeEvent event) {
    switch (event.type) {
      case 'message.created':
        _handleMessage(event.data);
      case 'conversation.updated':
        // Wrapped, per API guide 18: `{"conversation": {...}}`. Handing the
        // wrapper to `Conversation.fromJson` reads no id and drops the event
        // silently, which is the worst possible failure for a thread closing.
        final conversation = event.data['conversation'];
        _messaging.applyConversationUpdate(
          conversation is Map<String, dynamic> ? conversation : event.data,
        );
      case 'notification.created':
        _handleNotification(event.data);
      case 'unread.counts':
        // The server's own reconciliation, sent after a reconnect. Cheaper
        // and more authoritative than the app guessing what it missed.
        _messaging.refreshUnreadCount();
        _notifications.refreshUnreadCount();
      default:
        // An event type this build has never heard of. Logged, not dropped
        // silently, so a backend that ships ahead of the app is visible in a
        // debug session rather than mysteriously doing nothing.
        debugPrint('[REALTIME] Unhandled event: ${event.type}');
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final payload = data['message'];
    final json = payload is Map<String, dynamic> ? payload : data;
    final conversationId =
        (data['conversation_id'] ??
                data['conversation'] ??
                json['conversation'])
            ?.toString() ??
        '';
    final message = Message.fromJson(json);

    final conversation = _messaging.applyIncomingMessage(
      conversationId: conversationId,
      message: message,
    );
    // Null means the thread is already on screen, or the app does not hold
    // the conversation yet. Either way there is nothing worth interrupting
    // for: the first case is already visible, the second has no thread to
    // open.
    if (conversation == null || message.isSystem) return;

    OasisPopups.show(
      OasisPopup(
        title: conversation.counterparty.displayName,
        body: message.body,
        icon: Icons.forum_rounded,
        // One banner per thread, not per message: a host answering three
        // questions in a row is one interruption.
        collapseKey: 'conversation:$conversationId',
        onTap: () => oasisNavigatorKey.currentState?.push(
          FadePageRoute(page: ConversationScreen(conversation: conversation)),
        ),
      ),
    );
  }

  void _handleNotification(Map<String, dynamic> data) {
    final payload = data['notification'];
    final json = payload is Map<String, dynamic> ? payload : data;

    final notification = _notifications.applyIncomingNotification(json);
    if (notification == null) return;
    _showNotificationPopup(notification);
  }

  /// Verification finishing is the one notification that changes what the app
  /// *is*, not just what is in a list.
  ///
  /// Every product screen is gated behind `VERIFIED`: `MainScaffold` shows
  /// the verification screen until the profile says so, and until these
  /// notifications existed the only way to learn it had happened was to poll
  /// `GET /verify/status/`. A user could sit looking at "we are checking your
  /// documents" for minutes after being cleared.
  ///
  /// Re-reading the profile is enough: `MainScaffold` watches it, so the app
  /// lets them in on the next frame.
  static const Set<NotificationType> _verificationOutcomes = {
    NotificationType.verificationSucceeded,
    NotificationType.verificationFailed,
  };

  void _showNotificationPopup(NotificationItemModel notification) {
    if (_verificationOutcomes.contains(notification.type)) {
      _auth?.refreshProfile();
    }

    const messageTypes = {
      NotificationType.messageReceived,
      NotificationType.shortLetMessageReceived,
    };
    final isMessage = messageTypes.contains(notification.type);

    // While the socket is up, a message notification is a duplicate: the
    // backend raises both, because a notification is also a row in the list,
    // and `message.created` has already popped the better of the two. It
    // carries the sender's name and opens the thread itself.
    //
    // While the socket is *down*, this notification is the only trace of that
    // message the app will see, so it is shown, and it goes to the inbox
    // rather than the bell.
    if (isMessage && RealtimeSocket.instance.isConnected) return;

    OasisPopups.show(
      OasisPopup(
        title: notification.headline,
        body: notification.message,
        icon: notification.type.icon,
        accent: notification.type.accentColor,
        collapseKey: 'notification:${notification.type.name}',
        onTap: () => oasisNavigatorKey.currentState?.push(
          FadePageRoute(
            page: isMessage
                ? const ConversationsScreen()
                : const NotificationsScreen(),
          ),
        ),
      ),
    );
  }
}
