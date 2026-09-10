import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/oasis_haptics.dart';
import '../../models/review_models.dart';

/// Five stars, read-only, filled to [rating].
///
/// Half stars are rendered rather than rounded away: the difference between a
/// 4.4 and a 4.6 place is exactly the kind of thing a guest is comparing on,
/// and rounding both to "four and a half" throws it away.
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;
  final Color? color;

  const RatingStars({
    super.key,
    required this.rating,
    this.size = 15,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Sand rather than the usual gold: it is the palette's warning/pending
    // colour, and stars sitting in a warm earthy UI in #FFD700 read as if
    // they came from a different app.
    final tone = color ?? AppTheme.vacantColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Padding(
            padding: EdgeInsets.only(right: star == 5 ? 0 : 2),
            child: Icon(_iconFor(star), size: size, color: tone),
          ),
      ],
    );
  }

  IconData _iconFor(int star) {
    if (rating >= star) return Icons.star_rounded;
    if (rating >= star - 0.5) return Icons.star_half_rounded;
    return Icons.star_outline_rounded;
  }
}

/// Five stars the user taps to set a rating.
///
/// Tapping a star sets that many, and a tap on the star already selected
/// clears back to none: otherwise a five-star tap is unrecoverable without
/// closing the sheet, which is the one rating people most often hit by
/// accident reaching for the top of a list.
class RatingStarsInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  const RatingStarsInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var star = 1; star <= 5; star++)
        GestureDetector(
          onTap: () {
            OasisHaptics.select();
            onChanged(value == star ? 0 : star);
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(
              star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: star <= value
                  ? AppTheme.vacantColor
                  : AppTheme.mutedTextColor(context),
            ),
          ),
        ),
    ],
  );
}

/// " 4.8 · 12 reviews": the compact form for a card.
///
/// Renders nothing at all when there is no rating. An unrated listing showing
/// "No reviews yet" on every card would put a negative-sounding line on every
/// new host's listing, which is not what the absence of data means.
class RatingBadge extends StatelessWidget {
  final RatingSummary summary;

  /// Shows "New" instead of nothing when there is no rating. Worth it on a
  /// detail screen, where the space is there and the honest answer helps;
  /// not worth it on a dense list.
  final bool showWhenUnrated;

  const RatingBadge({
    super.key,
    required this.summary,
    this.showWhenUnrated = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!summary.hasRating) {
      if (!showWhenUnrated) return const SizedBox.shrink();
      return Text(
        'Newly listed',
        style: AppTheme.labelText(
          context,
          color: AppTheme.secondaryTextColor(context),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 14, color: AppTheme.vacantColor),
        const SizedBox(width: 3),
        Text(
          summary.label,
          style: AppTheme.labelText(
            context,
            color: AppTheme.primaryTextColor(context),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '(${summary.count})',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
      ],
    );
  }
}
