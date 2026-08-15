import 'package:flutter/material.dart';

/// Smooth left-to-right sweeping Shimmer effect widget for loading states
class LandaShimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const LandaShimmer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFE5E7EB),
    this.highlightColor = const Color(0xFFF9FAFB),
  });

  @override
  State<LandaShimmer> createState() => _LandaShimmerState();
}

class _LandaShimmerState extends State<LandaShimmer> with SingleTickerProviderStateMixin {
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
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
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
        color: Colors.grey.shade300,
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
