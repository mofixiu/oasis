import 'package:flutter/material.dart';

/// A number or short label that changes without snapping.
///
/// The values that move in this app are the ones people watch: a vault
/// balance after a top-up, rent outstanding after a payment, an unread count,
/// the number of applications waiting. Every one of them used to be replaced
/// between two frames: the old figure simply stopped existing and a new one
/// was there instead, which reads as a redraw rather than as something having
/// happened.
///
/// This crossfades and lifts the new value into place. It is a small
/// animation on purpose: the point is to make the change *noticed*, not to
/// perform it. Anything longer than a couple of hundred milliseconds turns a
/// balance into a slot machine.
class OasisAnimatedValue extends StatelessWidget {
  /// The rendered value. Its text is what decides whether anything animates,
  /// so callers pass the formatted string they were already showing.
  final String value;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;
  final Duration duration;

  const OasisAnimatedValue({
    super.key,
    required this.value,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.duration = const Duration(milliseconds: 260),
  });

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: duration,
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeIn,
    // Laid out so the row around it does not jump while two values are on
    // screen together: the switcher takes the size of whichever is larger,
    // and both sit in the same place.
    layoutBuilder: (currentChild, previousChildren) => Stack(
      alignment: textAlign == TextAlign.center
          ? Alignment.center
          : AlignmentDirectional.centerStart,
      children: [...previousChildren, if (currentChild != null) currentChild],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        // Upward for the arriving value, which is the direction a figure
        // being replaced reads as: the old one leaves, the new one rises.
        position: Tween<Offset>(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: Text(
      value,
      // Keyed on the text, so an identical value never re-animates: a
      // rebuild is not an event, and animating one is how a screen starts
      // twitching every time anything above it changes.
      key: ValueKey(value),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
