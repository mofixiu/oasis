import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_constants.dart';
import 'auth_token_storage.dart';

/// One event pushed down the realtime socket.
///
/// Deliberately thin: the socket does not know what a message or a
/// notification is, only that the server named a `type` and attached a
/// `data` object. Feature controllers decode their own payloads, exactly as
/// they already do for REST responses, which means a new server event can be
/// added without touching this file.
@immutable
class RealtimeEvent {
  /// The server's name for what happened, e.g. `message.created`.
  final String type;

  /// The payload. Shaped like the REST representation of the same object, so
  /// a controller can reuse its existing `fromJson`.
  final Map<String, dynamic> data;

  const RealtimeEvent({required this.type, this.data = const {}});

  /// Parses a frame, tolerating the two shapes a server realistically sends:
  /// `{"type": ..., "data": {...}}` and a flat object with `type` alongside
  /// the fields themselves.
  static RealtimeEvent? tryParse(dynamic frame) {
    if (frame is! String || frame.isEmpty) return null;
    try {
      final decoded = jsonDecode(frame);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['type']?.toString();
      if (type == null || type.isEmpty) return null;
      final payload = decoded['data'];
      if (payload is Map<String, dynamic>) {
        return RealtimeEvent(type: type, data: payload);
      }
      // Flat shape: the fields sit beside `type`. Copied rather than aliased
      // so removing the discriminator cannot disturb the caller's map.
      final flat = Map<String, dynamic>.from(decoded)..remove('type');
      return RealtimeEvent(type: type, data: flat);
    } catch (_) {
      // A frame we cannot read is not worth an error state: the socket is a
      // freshness optimisation, and every screen behind it still polls.
      return null;
    }
  }

  @override
  String toString() => 'RealtimeEvent($type)';
}

/// How the app is currently getting its updates. Surfaced so a screen can
/// say "reconnecting" rather than silently going stale.
enum RealtimeStatus {
  /// Never asked to connect, or deliberately shut down (sign-out, background).
  idle,

  connecting,

  /// Live. Features may stand their polling timers down.
  connected,

  /// Dropped, and a reconnect is scheduled. Polling is the fallback.
  reconnecting,
}

/// The app's single WebSocket to the backend.
///
/// Everything live in Oasis (a message landing in an open thread, a
/// notification being raised) arrives here. One socket rather than one per
/// feature, because a phone on mobile data pays for every connection it
/// holds, and both of those events are the same thing to the user: something
/// happened while they were looking elsewhere.
///
/// Three properties matter more than the plumbing:
///
/// * **It is never load-bearing.** Every screen that reads from it also
///   fetches over REST and, where it matters, polls. If the socket never
///   connects (an old backend, a captive portal, a corporate proxy that
///   eats upgrades) the app behaves exactly as it did before, just less
///   promptly. That is why a failure here is logged and not shown.
/// * **It reconnects on its own,** with backoff, and gives up on nothing.
///   Mobile data drops constantly; a socket that needs the user to notice is
///   worse than no socket.
/// * **It authenticates with a header, not a query string.** A JWT in a URL
///   is a credential written into every proxy log between here and Render.
class RealtimeSocket {
  RealtimeSocket._();

  /// Process-wide, like [ApiClient]: there is one backend and one user.
  static final RealtimeSocket instance = RealtimeSocket._();

  /// Reconnect delays, in order. Fast enough that a tunnel or a lift is
  /// invisible, slow enough that a backend with no socket at all is not
  /// hammered by every phone that installed the app.
  static const List<Duration> _backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 2),
  ];

  /// How long a silent socket is trusted before it is treated as dead.
  ///
  /// A TCP connection through a mobile NAT can be gone for minutes without
  /// either end being told, so silence is the only symptom the app ever gets.
  /// The server's heartbeat is every 25 seconds, which makes this window
  /// nearly three missed beats: long enough not to churn the connection on
  /// one slow moment, short enough that a dead socket is not left looking
  /// connected while delivering nothing.
  static const Duration _silenceTimeout = Duration(seconds: 70);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _silenceTimer;
  int _attempt = 0;
  bool _wantsConnection = false;

  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();

  /// Every event the server has pushed since the app started. Broadcast, so
  /// any number of controllers can listen without coordinating.
  Stream<RealtimeEvent> get events => _events.stream;

  final ValueNotifier<RealtimeStatus> status = ValueNotifier(
    RealtimeStatus.idle,
  );

  /// True while the socket is live and features may stand their polling down.
  bool get isConnected => status.value == RealtimeStatus.connected;

  /// Opens the socket, or does nothing if it is already open or opening.
  ///
  /// Safe to call repeatedly: sign-in, app resume and a manual retry all
  /// call it, and none of them knows what the others have done.
  Future<void> connect() async {
    _wantsConnection = true;
    if (_channel != null || status.value == RealtimeStatus.connecting) return;
    await _open();
  }

  /// Closes the socket and stops reconnecting.
  ///
  /// Called on sign-out (the token is gone) and when the app is backgrounded
  /// (the OS will freeze the connection anyway, and a socket held across a
  /// suspension wakes up believing it is alive).
  Future<void> disconnect() async {
    _wantsConnection = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _attempt = 0;
    await _teardown();
    status.value = RealtimeStatus.idle;
  }

  Future<void> _open() async {
    final token = await AuthTokenStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      // Nothing to authenticate with. Not an error: this is the ordinary
      // state before sign-in, and connect() is called again once there is a
      // session.
      status.value = RealtimeStatus.idle;
      return;
    }
    if (!_wantsConnection) return;

    status.value = _attempt == 0
        ? RealtimeStatus.connecting
        : RealtimeStatus.reconnecting;

    final uri = ApiConstants.realtimeUri();
    debugPrint('[REALTIME] Connecting to $uri (attempt ${_attempt + 1})');

    try {
      // IOWebSocketChannel rather than the platform-agnostic constructor:
      // only the dart:io implementation can send headers on the opening
      // handshake, and the header is where the token belongs. Oasis ships to
      // iOS and Android, so this is the implementation that runs.
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      if (!_wantsConnection) {
        await socket.close();
        return;
      }

      final channel = IOWebSocketChannel(socket);
      _channel = channel;
      _attempt = 0;
      status.value = RealtimeStatus.connected;
      debugPrint('[REALTIME] Connected.');

      _subscription = channel.stream.listen(
        _handleFrame,
        onError: (Object error) {
          debugPrint('[REALTIME] Stream error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint(
            '[REALTIME] Closed by server '
            '(code=${channel.closeCode}, reason=${channel.closeReason}).',
          );
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      _armSilenceTimer();
    } catch (e) {
      debugPrint('[REALTIME] Could not connect: $e');
      _scheduleReconnect();
    }
  }

  void _handleFrame(dynamic frame) {
    // Any frame at all is proof of life, the heartbeat included.
    _armSilenceTimer();

    final event = RealtimeEvent.tryParse(frame);
    if (event == null) return;

    // The heartbeat runs server-first: it sends `ping` every 25 seconds and
    // expects `pong` back (API guide 18). A client that stays silent is a
    // client the server is entitled to consider gone, so this reply is not
    // optional politeness: it is what keeps the socket open.
    if (event.type == 'ping') {
      send('pong');
      return;
    }
    // Consumed here rather than pushed at every controller in the app.
    if (event.type == 'pong') return;

    debugPrint('[REALTIME] ${event.type}');
    if (!_events.isClosed) _events.add(event);
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceTimeout, () {
      debugPrint(
        '[REALTIME] Silent for ${_silenceTimeout.inSeconds}s, '
        'assuming the connection is dead.',
      );
      _scheduleReconnect();
    });
  }

  void _scheduleReconnect() {
    if (!_wantsConnection) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _teardown();
    status.value = RealtimeStatus.reconnecting;

    final delay = _backoff[_attempt.clamp(0, _backoff.length - 1)];
    _attempt++;
    debugPrint('[REALTIME] Reconnecting in ${delay.inSeconds}s.');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _open();
    });
  }

  /// Drops the current connection without touching the reconnect intent.
  Future<void> _teardown() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    await channel?.sink.close();
  }

  /// Sends a frame, if the socket happens to be up.
  ///
  /// Fire-and-forget by design: nothing the app sends up this wire is the
  /// only copy of anything. A message is sent over REST; this carries the
  /// heartbeat reply and, in future, hints like "I am reading this thread".
  void send(String type, [Map<String, dynamic> data = const {}]) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'type': type, ...data}));
    } catch (e) {
      debugPrint('[REALTIME] Send failed: $e');
    }
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    await disconnect();
    _attempt = 0;
  }
}
