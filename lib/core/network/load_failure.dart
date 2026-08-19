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

  String? get errorMessage => _errorMessage;

  /// True when the last failure was "could not reach the server" rather than
  /// "the server said no".
  bool get errorIsConnection => _errorIsConnection;

  bool get hasError => _errorMessage != null;

  /// Records a caught error and returns its user-facing message.
  ///
  /// Does not notify: callers are already inside a load that notifies once it
  /// settles, and an extra notification mid-flight causes a visible flicker.
  @protected
  String captureFailure(Object error) {
    _errorMessage = friendlyErrorMessage(error);
    _errorIsConnection = isConnectionError(error);
    return _errorMessage!;
  }

  /// Records a failure the controller composed itself rather than caught.
  @protected
  void setFailureMessage(String message, {bool isConnection = false}) {
    _errorMessage = message;
    _errorIsConnection = isConnection;
  }

  @protected
  void clearFailure() {
    _errorMessage = null;
    _errorIsConnection = false;
  }
}
