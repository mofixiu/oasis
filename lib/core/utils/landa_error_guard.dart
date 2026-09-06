import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Catches the errors Flutter would otherwise turn into a dead screen.
///
/// There are two kinds and they fail differently:
///
/// * **A build error**: a widget throws while being laid out. Flutter's
///   default is [ErrorWidget], the grey-on-red box with a stack trace in it,
///   and in a release build that box is what the user sees. One bad row in a
///   list takes over the page.
/// * **An uncaught async error**: a `Future` nobody awaited, a callback that
///   throws after its screen has gone. These reach the zone and, in release,
///   vanish without a trace, which is why "it crashed" arrives as a bug
///   report with nothing attached to it.
///
/// The commonest source of both in this app is a `BuildContext` used after
/// the widget holding it has left the tree: a sheet reporting a result after
/// popping itself, a callback firing after a screen was closed. Those trip
/// *"Looking up a deactivated widget's ancestor is unsafe"*, which is an
/// assertion, so it is a hard stop in debug and a subtler wrongness in
/// release.
///
/// This does not make those bugs correct. It makes them **legible**: every
/// one is logged under a single searchable tag, and it stops one of them
/// destroying the whole screen when it does happen.
class LandaErrorGuard {
  LandaErrorGuard._();

  /// Errors seen this session, newest last. Debug builds only; a release
  /// build has nowhere to show them and no reason to hold them.
  static final List<FlutterErrorDetails> recent = [];

  /// How many to keep. Enough to see a pattern, few enough to be free.
  static const int _maxRecorded = 20;

  /// Installs the handlers. Called once, first thing in `main()`.
  static void install() {
    final previous = FlutterError.onError;

    FlutterError.onError = (details) {
      _record(details);
      // Still presented in debug: the red screen and the console trace are
      // how this gets fixed, and hiding them would trade a visible bug for
      // an invisible one.
      previous?.call(details);
    };

    // Anything that escapes the widget layer entirely: an unawaited Future,
    // a platform callback. Returning true marks it handled, which stops the
    // engine treating it as fatal.
    PlatformDispatcher.instance.onError = (error, stack) {
      _record(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'landa',
          context: ErrorDescription('in an uncaught asynchronous callback'),
        ),
      );
      return true;
    };

    // What replaces the red box. In debug it stays red, that is the signal,
    // and in release it becomes something a user can read and move past.
    if (kReleaseMode) {
      ErrorWidget.builder = (details) => const _LandaErrorPlaceholder();
    }
  }

  static void _record(FlutterErrorDetails details) {
    debugPrint('[LANDA ERROR] ${details.exceptionAsString()}');
    if (!kDebugMode) return;
    recent.add(details);
    if (recent.length > _maxRecorded) recent.removeAt(0);
  }

  @visibleForTesting
  static void clearRecorded() => recent.clear();
}

/// What a failed widget leaves behind in a release build.
///
/// Deliberately small and quiet. It sits where the broken widget was, so the
/// rest of the page (the navigation, the other cards, the way out) keeps
/// working. A full-screen apology would be a bigger failure than the one it
/// is reporting.
class _LandaErrorPlaceholder extends StatelessWidget {
  const _LandaErrorPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.disputeColor.withValues(alpha: 0.06),
      borderRadius: AppTheme.cornerSm,
      border: Border.all(color: AppTheme.disputeColor.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 18,
          color: AppTheme.disputeColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "This part didn't load. Pull down to try again.",
            style: AppTheme.labelText(context, color: AppTheme.disputeColor),
          ),
        ),
      ],
    ),
  );
}
