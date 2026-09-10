import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/oasis_haptics.dart';
import '../utils/oasis_navigator.dart';

/// One in-app popup: what happened, and where it goes if tapped.
@immutable
class OasisPopup {
  /// Heading: usually who it is from, or the notification's own title.
  final String title;

  /// The line underneath. A message body, or the notification's sentence.
  final String body;

  final IconData icon;

  /// Tint for the icon chip. Defaults to the brand action colour.
  final Color? accent;

  /// Where tapping the popup takes the user. Null makes it read-only, which
  /// is right for anything with nowhere useful to go.
  final VoidCallback? onTap;

  /// Collapses repeats. A second popup arriving with a key already on screen
  /// replaces it instead of stacking: five messages in one thread are one
  /// interruption, not five.
  final String? collapseKey;

  const OasisPopup({
    required this.title,
    required this.body,
    required this.icon,
    this.accent,
    this.onTap,
    this.collapseKey,
  });
}

/// In-app popup notifications: the banner that drops from the top of the
/// screen when something arrives while the user is looking at something else.
///
/// Distinct from [OasisToast], and the difference is who started it. A toast
/// is the *result of an action the user just took*, "Photo added", so it
/// belongs to the screen that took it and is shown with that screen's
/// context. A popup is an *interruption*: a message from the other party, a
/// booking request landing. Nobody on this device asked for it, there is no
/// screen in the call stack, and it has to be able to appear over any of
/// them. That is why this class owns a queue and reaches the overlay through
/// [oasisNavigatorKey] rather than taking a `BuildContext`.
///
/// It is deliberately *not* a system notification. Oasis has no push
/// certificate yet, and the app only raises these while it is in the
/// foreground, which is also the only time an in-app banner is worth
/// anything.
class OasisPopups {
  OasisPopups._();

  /// How long a popup stays before it withdraws itself.
  static const Duration visibleFor = Duration(seconds: 4);

  /// At most this many wait behind the one on screen. A backlog longer than
  /// this is a sync catching up, not a conversation, and showing all of it
  /// would lock the top of the screen for a minute.
  static const int _maxQueued = 3;

  static final Queue<OasisPopup> _pending = Queue<OasisPopup>();
  static OverlayEntry? _entry;
  static _OasisPopupBannerState? _current;

  /// How many screens have asked for silence. A count rather than a flag,
  /// because a popup can push a conversation over a conversation: tapping a
  /// banner from inside another thread, and the inner one closing must not
  /// un-silence the outer one that is still open.
  static int _suppressions = 0;

  /// Whether a popup is on screen right now.
  static bool get isShowing => _entry != null;

  /// Stops popups being raised until [resume] is called.
  ///
  /// Used by the conversation screen: a banner announcing a message the user
  /// is watching arrive, in the thread they already have open, is noise about
  /// something they can already see.
  static void suppress() => _suppressions++;

  static void resume() {
    if (_suppressions > 0) _suppressions--;
  }

  /// Queues a popup, or shows it straight away if nothing is on screen.
  ///
  /// Silently does nothing before the first frame: the socket can deliver an
  /// event during startup, and an interruption with no app behind it is not
  /// worth crashing over.
  static void show(OasisPopup popup) {
    if (_suppressions > 0) return;
    final overlay = _overlay();
    if (overlay == null) return;

    // A repeat of what is already showing updates it in place, so a second
    // message in the same thread refreshes the banner instead of queueing
    // behind itself.
    if (popup.collapseKey != null &&
        _current?.widget.popup.collapseKey == popup.collapseKey) {
      _current?.replaceWith(popup);
      return;
    }
    _pending.removeWhere((queued) => queued.collapseKey == popup.collapseKey);

    if (_entry != null) {
      if (_pending.length >= _maxQueued) _pending.removeFirst();
      _pending.add(popup);
      return;
    }
    _present(overlay, popup);
  }

  /// Drops everything queued and dismisses what is on screen.
  /// Called on sign-out: the next user is owed none of this.
  static void clear() {
    _pending.clear();
    _current?.dismiss();
    // A sign-out can happen from anywhere, including from under a screen
    // that had asked for silence and will never get to lift it.
    _suppressions = 0;
  }

  /// Drops every trace of the queue, synchronously.
  ///
  /// [clear] animates the current banner out, which is right in the app and
  /// useless between tests: the overlay it was inserted into is gone by then,
  /// and the leftover entry would make the next `show` queue behind a banner
  /// that can never retire.
  @visibleForTesting
  static void resetForTest() {
    _pending.clear();
    _entry = null;
    _current = null;
    _suppressions = 0;
  }

  static OverlayState? _overlay() => oasisRootOverlay;

  static void _present(OverlayState overlay, OasisPopup popup) {
    OasisHaptics.arrival();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _OasisPopupBanner(
        popup: popup,
        onRetired: () {
          if (entry.mounted) entry.remove();
          if (identical(_entry, entry)) {
            _entry = null;
            _current = null;
          }
          // Whatever piled up while this one was on screen gets its turn.
          if (_pending.isNotEmpty) {
            final next = _pending.removeFirst();
            final overlay = _overlay();
            if (overlay != null) _present(overlay, next);
          }
        },
        onMounted: (state) => _current = state,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

/// The banner itself: drops in, waits, withdraws. Swipe up to dismiss early.
class _OasisPopupBanner extends StatefulWidget {
  final OasisPopup popup;
  final VoidCallback onRetired;
  final void Function(_OasisPopupBannerState state) onMounted;

  const _OasisPopupBanner({
    required this.popup,
    required this.onRetired,
    required this.onMounted,
  });

  @override
  State<_OasisPopupBanner> createState() => _OasisPopupBannerState();
}

class _OasisPopupBannerState extends State<_OasisPopupBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );

  late OasisPopup _popup = widget.popup;
  Timer? _timer;
  bool _retiring = false;

  /// Vertical drag offset while the user is flicking it away.
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    widget.onMounted(this);
    _controller.forward();
    _armTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(OasisPopups.visibleFor, dismiss);
  }

  /// Swaps the content without re-animating, and restarts the clock: used
  /// when a second event collapses into the banner already on screen.
  void replaceWith(OasisPopup popup) {
    if (!mounted) return;
    setState(() => _popup = popup);
    _armTimer();
  }

  Future<void> dismiss() async {
    if (_retiring || !mounted) return;
    _retiring = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onRetired();
  }

  void _handleTap() {
    final onTap = _popup.onTap;
    dismiss();
    // After the banner has begun leaving, so a pushed route does not animate
    // in underneath a banner that is still sliding out.
    if (onTap != null) onTap();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _popup.accent ?? AppTheme.actionColor;
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: Transform.translate(
            offset: Offset(0, _dragY),
            child: GestureDetector(
              onTap: _handleTap,
              // Vertical only: a horizontal swipe on the banner would fight
              // whatever the screen underneath does with one.
              onVerticalDragUpdate: (details) => setState(() {
                // Downward drag is resisted: there is nothing below to pull
                // it towards, and letting it follow the finger down makes it
                // look like a sheet that can be opened.
                final delta = details.delta.dy;
                _dragY = (_dragY + (delta < 0 ? delta : delta * 0.2)).clamp(
                  -200.0,
                  24.0,
                );
              }),
              onVerticalDragEnd: (details) {
                if (_dragY < -28 || (details.primaryVelocity ?? 0) < -320) {
                  dismiss();
                } else {
                  setState(() => _dragY = 0);
                }
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: AppTheme.cornerMd,
                    border: Border.all(color: AppTheme.borderColor(context)),
                    boxShadow: AppTheme.raisedShadow(context),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 38,
                        width: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: AppTheme.cornerSm,
                        ),
                        child: Icon(_popup.icon, size: 20, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _popup.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.cardTitle(context),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _popup.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyText(
                                context,
                                color: AppTheme.secondaryTextColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_popup.onTap != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppTheme.mutedTextColor(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
