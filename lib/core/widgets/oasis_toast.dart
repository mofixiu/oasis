import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/oasis_haptics.dart';
import '../utils/oasis_navigator.dart';

enum OasisToastType { success, error, info }

/// Modern, floating top banner notification for Oasis
/// Replaces standard ScaffoldMessenger with overlay toasts
class OasisToast {
  static void show(
    BuildContext context, {
    required String message,
    OasisToastType type = OasisToastType.success,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = _resolveOverlay(context);
    if (overlay == null) return;

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return _OasisToastWidget(
          message: message,
          type: type,
          onDismiss: () {
            if (entry.mounted) {
              entry.remove();
            }
          },
        );
      },
    );

    overlay.insert(entry);

    Future.delayed(duration, () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  static void success(BuildContext context, String message) {
    // Outcome haptics live here so every success/failure in the app is felt
    // the same way without each screen remembering to fire one.
    OasisHaptics.success();
    show(context, message: message, type: OasisToastType.success);
  }

  static void error(BuildContext context, String message) {
    OasisHaptics.warning();
    show(context, message: message, type: OasisToastType.error);
  }

  static void info(BuildContext context, String message) {
    show(context, message: message, type: OasisToastType.info);
  }

  /// Finds an overlay to put the toast in, preferring one that cannot have
  /// gone stale.
  ///
  /// Almost every toast in the app is shown by a sheet reporting an outcome,
  /// and the overwhelmingly common shape of that is `Navigator.pop(context)`
  /// followed by `OasisToast.success(context, ...)`. The context handed in is
  /// therefore, quite often, one belonging to a widget on its way out of the
  /// tree, and an ancestor lookup on a deactivated element does not return
  /// null: it trips an assertion. *"Looking up a deactivated widget's
  /// ancestor is unsafe"*, which in a debug build takes the whole screen
  /// down over a confirmation message.
  ///
  /// The app's own navigator outlives every screen inside it, so it is asked
  /// first. The passed context stays as the fallback, because it is the only
  /// thing that works in a widget test that pumps a bare screen, and it is
  /// guarded so a stale one degrades to "no toast" rather than a crash.
  static OverlayState? _resolveOverlay(BuildContext context) {
    final rootOverlay = oasisRootOverlay;
    if (rootOverlay != null) return rootOverlay;
    try {
      return Overlay.maybeOf(context, rootOverlay: true);
    } catch (_) {
      // A deactivated context. There is nowhere safe to render, and the
      // message is a courtesy: never the only record of anything.
      return null;
    }
  }
}

class _OasisToastWidget extends StatefulWidget {
  final String message;
  final OasisToastType type;
  final VoidCallback onDismiss;

  const _OasisToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_OasisToastWidget> createState() => _OasisToastWidgetState();
}

class _OasisToastWidgetState extends State<_OasisToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.type) {
      case OasisToastType.success:
        return Icons.check_circle_rounded;
      case OasisToastType.error:
        return Icons.error_outline_rounded;
      case OasisToastType.info:
        return Icons.info_outline_rounded;
    }
  }

  Color get _iconColor {
    switch (widget.type) {
      case OasisToastType.success:
        return AppTheme.successColor;
      case OasisToastType.error:
        return AppTheme.logoutColor;
      case OasisToastType.info:
        return AppTheme.profileColor;
    }
  }

  Color get _backgroundColor {
    switch (widget.type) {
      case OasisToastType.success:
        return AppTheme.successSurface(context);
      case OasisToastType.error:
        return AppTheme.logoutSurface(context);
      case OasisToastType.info:
        return AppTheme.slateSurface(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 16.0, left: 20.0, right: 20.0),
          child: SlideTransition(
            position: _slideAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _iconColor.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: _iconColor.withValues(alpha: 0.45),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_icon, color: _iconColor, size: 22),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: _iconColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: Icon(
                          Icons.close,
                          color: _iconColor.withValues(alpha: 0.7),
                          size: 18,
                        ),
                      ),
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
