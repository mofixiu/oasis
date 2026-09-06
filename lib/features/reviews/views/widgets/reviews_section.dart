import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../controllers/review_controller.dart';
import '../../models/review_models.dart';
import 'rating_stars.dart';

/// The reviews block on a detail screen: the average, the breakdown, and the
/// most recent few in full.
///
/// A block rather than its own screen. Reviews are read while deciding, not
/// as a destination: pushing a route for them takes the reader away from the
/// thing they were deciding about, and most listings have few enough that the
/// whole set fits.
///
/// Fetches its own data on mount. It is dropped into screens that already own
/// several loads of their own, and threading a fourth one through each of
/// them would have every caller repeating the same three lines.
class ReviewsSection extends StatefulWidget {
  final ReviewSubject subject;
  final String subjectId;

  /// Shown above the list. Named by the caller because the same block reads
  /// differently under a stay and under an artisan.
  final String title;

  /// How many to show before collapsing the rest behind a count.
  final int previewCount;

  const ReviewsSection({
    super.key,
    required this.subject,
    required this.subjectId,
    this.title = 'Reviews',
    this.previewCount = 3,
  });

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReviewController>().loadReviews(
        widget.subject,
        widget.subjectId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReviewController>();
    final summary = controller.summaryFor(widget.subject, widget.subjectId);
    final all = controller.reviewsFor(widget.subject, widget.subjectId);
    final loaded = controller.hasLoaded(
      '${widget.subject.value}:${widget.subjectId}',
    );

    if (!loaded) {
      // Deliberately not a shimmer. This block sits at the foot of a screen
      // that has already drawn: the photos, the price, the button are all
      // there, and a sweeping animation on the one section still arriving
      // pulls the eye down to the emptiest part of the page. A skeleton
      // earns its keep where a *whole* screen is missing; here it just
      // fidgets. So: the heading, and a still line saying what is coming.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: AppTheme.sectionTitle(context)),
          const SizedBox(height: 10),
          Text(
            'Loading reviews…',
            style: AppTheme.bodyText(
              context,
              color: AppTheme.mutedTextColor(context),
            ),
          ),
        ],
      );
    }

    final visible = _showAll ? all : all.take(widget.previewCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title, style: AppTheme.sectionTitle(context)),
            ),
            RatingBadge(summary: summary, showWhenUnrated: true),
          ],
        ),
        const SizedBox(height: 12),

        if (!summary.hasRating)
          // Said plainly rather than hidden. On a detail screen the absence
          // of reviews is itself information a guest is entitled to weigh.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurfaceColor(context),
              borderRadius: AppTheme.cornerMd,
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Text(
              'Nobody has reviewed ${widget.subject.noun} yet. Reviews can '
              'only be left by people who have actually booked, so they take '
              'a little while to appear.',
              style: AppTheme.bodyText(context),
            ),
          )
        else ...[
          _SummaryHeader(summary: summary),
          const SizedBox(height: 16),
          for (final review in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ReviewCard(review: review),
            ),
          if (all.length > widget.previewCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.actionColor,
                ),
                child: Text(
                  _showAll ? 'Show fewer' : 'Read all ${all.length} reviews',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The big number, the stars, and the per-star bars.
class _SummaryHeader extends StatelessWidget {
  final RatingSummary summary;

  const _SummaryHeader({required this.summary});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.subtleSurfaceColor(context),
      borderRadius: AppTheme.cornerLg,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.label,
              style: AppTheme.screenTitle(
                context,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 2),
            RatingStars(rating: summary.average ?? 0),
            const SizedBox(height: 4),
            Text(
              '${summary.count} ${summary.count == 1 ? 'review' : 'reviews'}',
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(width: 20),
        // Only when the backend broke it down. A bar chart inferred from the
        // average would be a drawing of a guess.
        if (summary.distribution.isNotEmpty)
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  _DistributionBar(
                    star: star,
                    tally: summary.distribution[star] ?? 0,
                    total: summary.count,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _DistributionBar extends StatelessWidget {
  final int star;
  final int tally;
  final int total;

  const _DistributionBar({
    required this.star,
    required this.tally,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : tally / total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: Text(
              '$star',
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: AppTheme.borderColor(context),
                valueColor: const AlwaysStoppedAnimation(AppTheme.vacantColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
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
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.actionColor.withValues(alpha: 0.12),
              child: Text(
                review.initial,
                style: AppTheme.cardTitle(context, color: AppTheme.actionColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    review.displayAuthor,
                    style: AppTheme.cardTitle(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      RatingStars(rating: review.rating.toDouble(), size: 13),
                      if (_when(review.createdAt) case final posted?) ...[
                        const SizedBox(width: 8),
                        Text(
                          posted,
                          style: AppTheme.labelText(
                            context,
                            color: AppTheme.mutedTextColor(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (review.comment.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(review.comment, style: AppTheme.bodyText(context)),
        ],
        // The reviewed party's answer, indented under the review it answers
        // so it never reads as a second, independent review.
        if (review.hasResponse) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurfaceColor(context),
              borderRadius: AppTheme.cornerMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RESPONSE',
                  style: AppTheme.labelText(
                    context,
                  ).copyWith(letterSpacing: 0.9),
                ),
                const SizedBox(height: 4),
                Text(review.response, style: AppTheme.bodyText(context)),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  /// "12 Aug 2026", or null when the timestamp will not parse: a review with
  /// an unreadable date is still worth reading.
  static String? _when(String iso) {
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? null : DateFormat('d MMM yyyy').format(parsed);
  }
}
