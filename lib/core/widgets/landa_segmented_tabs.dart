import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/landa_haptics.dart';

/// One option in a [LandaSegmentedTabs] control.
class LandaSegment {
  final String label;

  /// Shown as a small terracotta pill after the label. Zero hides it.
  final int badgeCount;

  const LandaSegment(this.label, {this.badgeCount = 0});
}

/// A sliding-pill segmented control driven by a [TabController].
///
/// Material's [TabBar] marks the selection with a two-pixel underline, which
/// on a two-option control reads as a browser tab strip rather than a choice.
/// This draws the selection as a raised pill inside a recessed track: the
/// selected option looks like it is sitting on top of the surface and the
/// other like it is sunk into it, so the state is legible without colour
/// alone.
///
/// The thumb is positioned from the controller's *animation* rather than its
/// index, so it tracks a swipe across the [TabBarView] frame by frame instead
/// of snapping once the gesture settles.
class LandaSegmentedTabs extends StatelessWidget {
  final TabController controller;
  final List<LandaSegment> segments;
  final EdgeInsetsGeometry padding;

  const LandaSegmentedTabs({
    super.key,
    required this.controller,
    required this.segments,
    this.padding = EdgeInsets.zero,
  });

  static const double _height = 46;

  /// Gap between the track and the thumb. Also the difference between the
  /// outer and inner corner radii, which is what keeps the two curves
  /// concentric instead of merely both-rounded.
  static const double _inset = 4;

  void _select(int index) {
    if (controller.index == index && !controller.indexIsChanging) return;
    LandaHaptics.select();
    controller.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDarkMode(context);
    final animation = controller.animation ?? kAlwaysDismissedAnimation;

    return Padding(
      padding: padding,
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth - _inset * 2;
            final segmentWidth = trackWidth / segments.length;

            return DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.subtleSurfaceColor(context),
                borderRadius: AppTheme.cornerMd,
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(_inset),
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    // Fractional while a swipe is in flight, whole once it
                    // settles.
                    final position = animation.value.clamp(
                      0.0,
                      (segments.length - 1).toDouble(),
                    );

                    return Stack(
                      children: [
                        Positioned(
                          left: position * segmentWidth,
                          top: 0,
                          bottom: 0,
                          width: segmentWidth,
                          child: _Thumb(dark: dark),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < segments.length; i++)
                              Expanded(
                                child: _SegmentLabel(
                                  segment: segments[i],
                                  // 1 when this segment holds the thumb, 0
                                  // when the thumb is a full segment away.
                                  selection: (1 - (position - i).abs()).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  onTap: () => _select(i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final bool dark;

  const _Thumb({required this.dark});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTheme.elevatedSurfaceColor(context),
      borderRadius: BorderRadius.circular(
        AppTheme.radiusMd - LandaSegmentedTabs._inset,
      ),
      // In dark mode the lift has to come from a hairline edge: a shadow on a
      // near-black track is invisible, so the pill would float unbounded.
      border: dark
          ? Border.all(color: Colors.white.withValues(alpha: 0.08))
          : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.35 : 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.28 : 0.06),
          blurRadius: 10,
          spreadRadius: -3,
          offset: const Offset(0, 4),
        ),
      ],
    ),
  );
}

class _SegmentLabel extends StatelessWidget {
  final LandaSegment segment;

  /// 0 = fully unselected, 1 = fully selected. Interpolated so a half-finished
  /// swipe shows a half-lit label rather than a colour that pops at the end.
  final double selection;
  final VoidCallback onTap;

  const _SegmentLabel({
    required this.segment,
    required this.selection,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(
      AppTheme.secondaryTextColor(context),
      AppTheme.actionColor,
      selection,
    )!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Weight is fixed rather than interpolated: reflowing the text
                // mid-swipe makes the label shuffle under the thumb.
                style: AppTheme.cardTitle(context, color: color),
              ),
            ),
            if (segment.badgeCount > 0) ...[
              const SizedBox(width: 7),
              _Badge(count: segment.badgeCount),
            ],
          ],
        ),
      ),
    );
  }
}

/// Always full-strength terracotta, selected or not: a count here means
/// somebody is waiting on the host, and dimming it with the tab would hide
/// exactly the thing worth walking over to.
class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    height: 20,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: AppTheme.actionColor,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: AppTheme.labelText(context, color: Colors.white),
    ),
  );
}
