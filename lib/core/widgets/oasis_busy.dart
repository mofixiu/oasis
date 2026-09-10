import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// What "working" looks like in this app, in the two sizes it is needed.
///
/// Not a `CircularProgressIndicator`. A spinning wheel is the default answer
/// to every wait, which is exactly its problem: it appears at 20pt inside a
/// button, at 40pt in the middle of an empty screen and at 14pt beside a
/// label, and in all three places it says the same thing, *something is
/// happening somewhere*. It reports on the software rather than on the work.
/// Twenty-six of them across the app was twenty-six small admissions that the
/// screen had nothing better to show.
///
/// What replaces it is smaller and quieter, and always attached to the thing
/// it describes: a sweep along the bottom of the button that was pressed, or
/// three dots beside the row that is loading. Both read as *this, now*.
/// An indeterminate sweep, for the foot of a button that has been pressed.
///
/// The button keeps its label: the point is that the thing you asked for is
/// under way, not that the button has been replaced by machinery. Two logical
/// pixels tall so it reads as a state of the button rather than a separate
/// control.
class OasisBusyBar extends StatefulWidget {
  final Color color;
  final double height;

  const OasisBusyBar({super.key, required this.color, this.height = 2.5});

  @override
  State<OasisBusyBar> createState() => _OasisBusyBarState();
}

class _OasisBusyBarState extends State<OasisBusyBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.height),
    child: SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // A third of the track, travelling a full width and a third so it
            // enters and leaves cleanly rather than popping at the edges.
            final segment = width / 3;
            final travel = (width + segment) * _controller.value - segment;
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: widget.color.withValues(alpha: 0.18),
                  ),
                ),
                Positioned(
                  left: travel,
                  width: segment,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Soft at both ends: a hard-edged block sliding along a
                      // track looks mechanical, a gradient reads as motion.
                      gradient: LinearGradient(
                        colors: [
                          widget.color.withValues(alpha: 0),
                          widget.color,
                          widget.color.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Three dots that rise and fall in sequence, for a row or a chip that is
/// waiting on something small.
///
/// Sized to sit inside a line of text, so it can stand in for a word: "
/// Opening ⋯ ", rather than displacing the layout around it the way even a
/// small wheel does.
class OasisBusyDots extends StatefulWidget {
  final Color color;
  final double size;

  const OasisBusyDots({super.key, required this.color, this.size = 5});

  @override
  State<OasisBusyDots> createState() => _OasisBusyDotsState();
}

class _OasisBusyDotsState extends State<OasisBusyDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Opacity for the dot at [index], offset so the three of them read as a
  /// wave rather than a blink.
  double _opacityFor(int index) {
    final phase = (_controller.value + index * 0.22) % 1.0;
    // Up over the first half, down over the second.
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 0.28 + wave * 0.72;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < 3; index++) ...[
          if (index > 0) SizedBox(width: widget.size * 0.7),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: _opacityFor(index)),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    ),
  );
}

/// A whole section that is waiting, said in words with dots after it.
///
/// For the places that used to centre a wheel in an empty box below content
/// that had already arrived. A sentence tells the reader what is coming; a
/// wheel only tells them to wait.
class OasisBusyLine extends StatelessWidget {
  final String label;

  const OasisBusyLine({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.mutedTextColor(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: AppTheme.labelText(context, color: color)),
        const SizedBox(width: 8),
        OasisBusyDots(color: color),
      ],
    );
  }
}
