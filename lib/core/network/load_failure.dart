import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Shared failure bookkeeping for controllers.
///
/// Every controller used to keep its own `_errorMessage` string, which meant a
/// screen could tell *that* a load failed but not *why*. Screens need the
/// distinction: a dropped connection deserves "You're offline / Try again",
/// while a backend rejection deserves the backend's own wording. Mixing this
/// in keeps `errorMessage` working exactly as before and adds
/// [errorIsConnection] alongside it.
mixin LoadFailureState on ChangeNotifier {
  String? _errorMessage;
  bool _errorIsConnection = false;
  bool _errorNeedsPayoutAccount = false;

  String? get errorMessage => _errorMessage;

  /// True when the last failure was "could not reach the server" rather than
  /// "the server said no".
  bool get errorIsConnection => _errorIsConnection;

  /// True when the backend blocked the action because the landlord has no
  /// verified payout account. Screens should offer payout setup and retry the
  /// original action rather than showing a dead-end error.
  bool get errorNeedsPayoutAccount => _errorNeedsPayoutAccount;

  bool get hasError => _errorMessage != null;

  /// Records a caught error and returns its user-facing message.
  ///
  /// Does not notify: callers are already inside a load that notifies once it
  /// settles, and an extra notification mid-flight causes a visible flicker.
  @protected
  String captureFailure(Object error) {
    _errorMessage = friendlyErrorMessage(error);
    _errorIsConnection = isConnectionError(error);
    _errorNeedsPayoutAccount = error is PayoutAccountRequiredException;
    return _errorMessage!;
  }

  /// Records a failure the controller composed itself rather than caught.
  @protected
  void setFailureMessage(String message, {bool isConnection = false}) {
    _errorMessage = message;
    _errorIsConnection = isConnection;
    _errorNeedsPayoutAccount = false;
  }

  @protected
  void clearFailure() {
    _errorMessage = null;
    _errorIsConnection = false;
    _errorNeedsPayoutAccount = false;
  }
}

/// Tracks which fetches a controller has *finished at least once*.
///
/// Exists because of a bug that showed up on nearly every list in the app:
/// a controller starts with an empty list and `isLoading == false`, so the
/// first frame, painted before the screen's post-frame fetch has even
/// started, matches the "loaded, and there is nothing here" branch. Stays
/// announced "No short stays yet", Fix announced "no artisans", and a moment
/// later the real content arrived. Users read the first state as the truth
/// and the second as a glitch.
///
/// `isLoading` cannot fix this on its own: it is false both *before* a load
/// starts and *after* it finishes, and those two mean opposite things to an
/// empty list. This mixin supplies the missing third state, so screens can
/// branch on "has this ever come back?" rather than guessing.
///
/// Keyed, because one controller often owns several independent fetches: a
/// landlord's own listings and a tenant's browse results are both on
/// [ShortLetController] and neither says anything about the other.
mixin LoadedOnceState on ChangeNotifier {
  final Set<String> _loadedKeys = {};

  /// Whether the fetch under [key] has completed at least once this session,
  /// successfully or not. False means "not asked yet": show a skeleton, not
  /// an empty state.
  bool hasLoaded([String key = 'default']) => _loadedKeys.contains(key);

  /// Records that [key] has been fetched. Called in the `finally` of a load,
  /// so a failed fetch still counts as answered: the screen then shows the
  /// error state rather than a skeleton that never resolves.
  @protected
  void markLoaded([String key = 'default']) => _loadedKeys.add(key);

  /// Forgets one fetch, so the next screen to read it shows a skeleton again.
  ///
  /// For state that is scoped to something narrower than the session: an open
  /// message thread is loaded per conversation, and leaving one must not
  /// leave the next conversation looking already-answered with the previous
  /// thread's (now cleared) messages.
  @protected
  void forgetLoaded([String key = 'default']) => _loadedKeys.remove(key);

  /// Forgets every fetch. Belongs in `resetSessionState()`: the next user's
  /// screens must show skeletons, not the previous user's "nothing here".
  @protected
  void resetLoadedState() => _loadedKeys.clear();
}
