import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Smooth left-to-right sweeping Shimmer effect widget for loading states
/// Sweeps a highlight across whatever is inside it.
///
/// **Wrap the bars, never the card.** `BlendMode.srcATop` paints the gradient
/// over every opaque pixel it is given, so a shimmer placed around a whole
/// skeleton card paints the card's own surface and border the same grey as
/// the bars inside it, and the silhouette it was carefully given disappears.
/// The result is one featureless slab, which is precisely what a skeleton
/// exists not to be, and is what the dashboard's loading state looked like
/// for a long time before anyone worked out why.
///
/// So the card is built outside this, and only its bars are handed in: the
/// gaps between them are transparent, the shader has nothing to paint there,
/// and the shape reads through.
class OasisShimmer extends StatefulWidget {
  final Widget child;

  /// Defaults follow the theme: the old hard-coded light greys glowed
  /// against the dark background.
  final Color? baseColor;
  final Color? highlightColor;

  const OasisShimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<OasisShimmer> createState() => _OasisShimmerState();
}

class _OasisShimmerState extends State<OasisShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDarkMode(context);
    final base =
        widget.baseColor ??
        (dark ? const Color(0xFF262626) : const Color(0xFFE5E7EB));
    final highlight =
        widget.highlightColor ??
        (dark ? const Color(0xFF333333) : const Color(0xFFF9FAFB));

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = -2.0 + (_controller.value * 4.0);
            return LinearGradient(
              begin: Alignment(dx, -0.2),
              end: Alignment(dx + 1.2, 0.2),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

/// Reusable Shimmer Skeleton Box
class ShimmerBox extends StatelessWidget {
  final double height;
  final double width;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.height,
    this.width = double.infinity,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        // Any opaque colour works, the shader replaces it entirely, but
        // white keeps the sweep even rather than muddying it in dark mode.
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton shaped like a real Oasis list card: leading square thumbnail, a
/// title bar, a shorter subtitle bar and a trailing status pill.
///
/// A featureless grey rectangle tells the reader nothing about what is
/// arriving; matching the silhouette of the card that lands makes the swap
/// feel like the content resolving rather than replacing.
class OasisCardSkeleton extends StatelessWidget {
  /// Show the leading thumbnail block (listings, properties, units).
  final bool hasThumbnail;

  /// Show the leading circular avatar (people-shaped rows: applications).
  final bool hasAvatar;

  /// Show the trailing status pill.
  final bool hasPill;

  /// Show a full-width action bar at the bottom (cards with buttons).
  final bool hasAction;

  const OasisCardSkeleton({
    super.key,
    this.hasThumbnail = false,
    this.hasAvatar = false,
    this.hasPill = true,
    this.hasAction = false,
  });

  @override
  Widget build(BuildContext context) {
    // The card is a real card: its own surface, its own border, outside the
    // shimmer. Only the bars are swept.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: OasisShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasThumbnail) ...[
                  const ShimmerBox(height: 56, width: 56, borderRadius: 14),
                  const SizedBox(width: 14),
                ] else if (hasAvatar) ...[
                  const ShimmerBox(height: 44, width: 44, borderRadius: 22),
                  const SizedBox(width: 14),
                ],
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Deliberately unequal widths: two identical bars read
                      // as a placeholder, uneven ones read as text.
                      ShimmerBox(height: 14, width: 170, borderRadius: 7),
                      SizedBox(height: 10),
                      ShimmerBox(height: 11, width: 110, borderRadius: 6),
                    ],
                  ),
                ),
                if (hasPill) ...[
                  const SizedBox(width: 12),
                  const ShimmerBox(height: 24, width: 66, borderRadius: 12),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const ShimmerBox(height: 11, width: 220, borderRadius: 6),
            if (hasAction) ...[
              const SizedBox(height: 18),
              const ShimmerBox(height: 44, borderRadius: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// A scrollable run of [OasisCardSkeleton]s, sized and padded like the list
/// it stands in for.
class OasisSkeletonList extends StatelessWidget {
  final int count;
  final bool hasThumbnail;
  final bool hasAvatar;
  final bool hasPill;
  final bool hasAction;
  final EdgeInsets padding;

  const OasisSkeletonList({
    super.key,
    this.count = 4,
    this.hasThumbnail = false,
    this.hasAvatar = false,
    this.hasPill = true,
    this.hasAction = false,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 100),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Never scrolls on its own, and is routinely dropped into a Column
      // inside a page-level scroll view: without shrinkWrap that is an
      // unbounded-height viewport, and the skeleton fails to render at all.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => OasisCardSkeleton(
        hasThumbnail: hasThumbnail,
        hasAvatar: hasAvatar,
        hasPill: hasPill,
        hasAction: hasAction,
      ),
    );
  }
}

/// Skeleton for the image-led marketplace listing card: media band on top,
/// title/price lines below.
class OasisListingSkeleton extends StatelessWidget {
  const OasisListingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: OasisShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ShimmerBox(height: 132, borderRadius: 0),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBox(height: 15, width: 190, borderRadius: 7),
                  SizedBox(height: 10),
                  ShimmerBox(height: 11, width: 130, borderRadius: 6),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      ShimmerBox(height: 26, width: 92, borderRadius: 13),
                      SizedBox(width: 10),
                      ShimmerBox(height: 26, width: 70, borderRadius: 13),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
