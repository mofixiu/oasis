import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Smooth left-to-right sweeping Shimmer effect widget for loading states
class LandaShimmer extends StatefulWidget {
  final Widget child;

  /// Defaults follow the theme — the old hard-coded light greys glowed
  /// against the dark background.
  final Color? baseColor;
  final Color? highlightColor;

  const LandaShimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<LandaShimmer> createState() => _LandaShimmerState();
}

class _LandaShimmerState extends State<LandaShimmer>
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
        // Painted over by the shimmer shader; opaque white keeps the sweep
        // even in dark mode instead of muddying it.
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton for Dashboard Cards (Properties, Agreements, Units)
class ShimmerCardSkeleton extends StatelessWidget {
  const ShimmerCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LandaShimmer(
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShimmerBox(height: 18, width: 140),
                ShimmerBox(height: 24, width: 70, borderRadius: 16),
              ],
            ),
            SizedBox(height: 8),
            ShimmerBox(height: 12, width: 200),
            Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShimmerBox(height: 14, width: 100),
                ShimmerBox(height: 14, width: 80),
              ],
            ),
            SizedBox(height: 12),
            ShimmerBox(height: 48, width: double.infinity, borderRadius: 10),
          ],
        ),
      ),
    );
  }
}

/// Skeleton List Loader
class ShimmerListSkeleton extends StatelessWidget {
  final int count;

  const ShimmerListSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const ShimmerCardSkeleton()),
    );
  }
}

/// Skeleton shaped like a real Landa list card: leading square thumbnail, a
/// title bar, a shorter subtitle bar and a trailing status pill.
///
/// A featureless grey rectangle tells the reader nothing about what is
/// arriving; matching the silhouette of the card that lands makes the swap
/// feel like the content resolving rather than replacing.
class LandaCardSkeleton extends StatelessWidget {
  /// Show the leading thumbnail block (listings, properties, units).
  final bool hasThumbnail;

  /// Show the leading circular avatar (people-shaped rows: applications).
  final bool hasAvatar;

  /// Show the trailing status pill.
  final bool hasPill;

  /// Show a full-width action bar at the bottom (cards with buttons).
  final bool hasAction;

  const LandaCardSkeleton({
    super.key,
    this.hasThumbnail = false,
    this.hasAvatar = false,
    this.hasPill = true,
    this.hasAction = false,
  });

  @override
  Widget build(BuildContext context) {
    return LandaShimmer(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
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

/// A scrollable run of [LandaCardSkeleton]s, sized and padded like the list
/// it stands in for.
class LandaSkeletonList extends StatelessWidget {
  final int count;
  final bool hasThumbnail;
  final bool hasAvatar;
  final bool hasPill;
  final bool hasAction;
  final EdgeInsets padding;

  const LandaSkeletonList({
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
      // inside a page-level scroll view — without shrinkWrap that is an
      // unbounded-height viewport, and the skeleton fails to render at all.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => LandaCardSkeleton(
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
class LandaListingSkeleton extends StatelessWidget {
  const LandaListingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LandaShimmer(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
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
