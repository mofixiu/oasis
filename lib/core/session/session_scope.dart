import 'package:flutter/foundation.dart';

/// Implemented by controllers that cache data belonging to the signed-in
/// user.
///
/// Providers in this app are created once at startup and live for the whole
/// process, so without an explicit reset a controller's data outlives the
/// session that produced it and is rendered to whoever signs in next.
abstract class SessionScopedController {
  /// Drops all per-user data, returning the controller to its initial state.
  ///
  /// Must not trigger network calls: it runs during sign-out, when the auth
  /// token has already been cleared.
  void resetSessionState();
}

/// Registry of every controller holding per-user state.
///
/// Registered from the composition root (`main.dart`) rather than from each
/// constructor, so the full set is visible in one place and repeated
/// construction in tests cannot accumulate stale entries.
class SessionScope {
  SessionScope._();

  static final List<SessionScopedController> _controllers = [];

  static void register(Iterable<SessionScopedController> controllers) {
    _controllers
      ..clear()
      ..addAll(controllers);
  }

  /// Clears cached data in every registered controller. Safe to call more than
  /// once, and safe to call when nothing is registered (e.g. in tests).
  static void resetAll() {
    debugPrint(
      '[SESSION] Clearing cached state in ${_controllers.length} controllers.',
    );
    for (final controller in _controllers) {
      controller.resetSessionState();
    }
  }

  @visibleForTesting
  static void clearRegistrations() => _controllers.clear();
}
