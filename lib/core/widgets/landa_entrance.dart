import 'package:flutter/material.dart';

/// Fade-and-rise entrance for list items and cards.
///
/// Content used to appear fully formed the instant a fetch resolved, which
/// reads as a jump cut. A short rise with a per-index delay makes the list
/// look like it assembled itself.
class LandaEntrance extends StatefulWidget {
  final Widget child;

  /// Position in the list. Later items start later, capped so a long list
  /// never leaves the reader waiting on the tail.
  final int index;

  final Duration duration;
  final Duration stagger;

  /// How far the child rises, in logical pixels.
  final double offset;

  const LandaEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 380),
    this.stagger = const Duration(milliseconds: 45),
    this.offset = 14,
  });

  @override
  State<LandaEntrance> createState() => _LandaEntranceState();
}

class _LandaEntranceState extends State<LandaEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    // Cap the cascade at ~8 items: past that the delay stops reading as
    // rhythm and starts reading as lag.
    final delay = widget.stagger * widget.index.clamp(0, 8);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Cross-fades between loading, error, empty and content states.
///
/// Swapping the subtree directly makes a skeleton snap into real content;
/// this dissolves it. Children must carry distinct keys for the switch to be
/// detected: pass [stateKey] rather than relying on widget type.
class LandaContentSwitcher extends StatelessWidget {
  final String stateKey;
  final Widget child;
  final Duration duration;

  const LandaContentSwitcher({
    super.key,
    required this.stateKey,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Default layout stacks children centred, which shifts full-height
      // lists during the cross-fade; top-left keeps them still.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}
