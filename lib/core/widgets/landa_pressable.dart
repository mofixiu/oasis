import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/landa_haptics.dart';

/// Wraps any tappable surface with the app's press behaviour: a small scale
/// dip on finger-down and a haptic tick on release.
///
/// Flutter's default is no press state at all, which is why untouched buttons
/// feel like pictures of buttons. The dip is deliberately shallow (3%) and
/// short — enough to acknowledge the touch, not enough to read as animation.
class LandaPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far to scale down while held.
  final double pressedScale;

  /// Set false for rows inside a list that already give their own feedback.
  final bool hapticOnTap;

  const LandaPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.hapticOnTap = true,
  });

  @override
  State<LandaPressable> createState() => _LandaPressableState();
}

class _LandaPressableState extends State<LandaPressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.hapticOnTap) LandaHaptics.tap();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              LandaHaptics.select();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The app's primary call to action: filled, full-width by default, with a
/// press dip, a commit-weight haptic and a built-in busy state so callers stop
/// hand-rolling "disabled + spinner" per screen.
class LandaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isBusy;
  final bool expand;
  final IconData? icon;
  final Color? color;
  final Color? foregroundColor;

  /// Outlined rather than filled — for the secondary option in a pair.
  final bool outlined;

  const LandaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isBusy = false,
    this.expand = true,
    this.icon,
    this.color,
    this.foregroundColor,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.actionColor;
    final enabled = onPressed != null && !isBusy;
    final background = outlined ? Colors.transparent : accent;
    final foreground =
        foregroundColor ?? (outlined ? accent : AppTheme.whiteColor);

    final content = AnimatedOpacity(
      opacity: enabled ? 1 : 0.55,
      duration: const Duration(milliseconds: 160),
      child: Container(
        height: 52,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 24),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppTheme.cornerMd,
          border: outlined ? Border.all(color: accent, width: 1.4) : null,
          boxShadow: outlined || !enabled
              ? null
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 16,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        // widthFactor 1 when not expanding: a plain Center fills whatever
        // width is offered, which silently stretched every compact button
        // back out to full width.
        child: Center(
          widthFactor: expand ? null : 1.0,
          child: isBusy
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: AppTheme.textMd,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    return LandaPressable(
      onTap: enabled
          ? () {
              LandaHaptics.commit();
              onPressed!();
            }
          : null,
      // The commit haptic above is the feedback; the generic tap would double it.
      hapticOnTap: false,
      child: content,
    );
  }
}
