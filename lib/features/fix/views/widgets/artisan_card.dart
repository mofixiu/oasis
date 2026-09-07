import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../reviews/views/widgets/rating_stars.dart';
import '../../models/fix_models.dart';

/// One artisan in a browse list.
///
/// Four signals, in the order a tenant actually weighs them: whether their
/// landlord vouched for this person, what other tenants said about the work,
/// whether they are around today, and how long they have been doing it.
///
/// The rating only appears once somebody has actually left one. An unrated
/// artisan shows no stars rather than zero of them: new on Landa is not the
/// same as bad at the job, and a row of empty stars says the second.
class ArtisanCard extends StatelessWidget {
  final ArtisanProfile artisan;
  final VoidCallback? onTap;

  /// Trailing action, e.g. "Request" on the tenant's browse list or "Choose"
  /// in the landlord's picker.
  final Widget? action;

  /// Draws the card in its chosen state, for the landlord's picker.
  final bool selected;

  const ArtisanCard({
    super.key,
    required this.artisan,
    this.onTap,
    this.action,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final recommended = artisan.isRecommended;
    // A recommendation and a selection are both "this is the one", so they
    // share the accent; nothing else on the card competes with it.
    final highlighted = recommended || selected;

    return LandaPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(
            color: highlighted
                ? AppTheme.actionColor.withValues(alpha: 0.55)
                : AppTheme.borderColor(context),
            width: highlighted ? 1.5 : 1,
          ),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recommended) ...[_RecommendedTag(), const SizedBox(height: 12)],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(artisan: artisan),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              artisan.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.cardTitle(context),
                            ),
                          ),
                          if (artisan.isVerified) ...[
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: AppTheme.successColor,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            artisan.categoryLabel,
                            style: AppTheme.labelText(
                              context,
                              color: AppTheme.actionColor,
                            ),
                          ),
                          // A tenant choosing between strangers to let into
                          // their flat has almost nothing to go on. What
                          // other tenants said is the strongest signal on
                          // this card, so it sits beside the trade.
                          if (artisan.hasRating) ...[
                            const SizedBox(width: 8),
                            RatingStars(
                              rating: artisan.averageRating!,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${artisan.ratingLabel} (${artisan.reviewCount})',
                              style: AppTheme.labelText(
                                context,
                                color: AppTheme.secondaryTextColor(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (artisan.credentials.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          artisan.credentials,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyText(context),
                        ),
                      ],
                    ],
                  ),
                ),
                if (artisan.recentlyOnline) ...[
                  const SizedBox(width: 8),
                  const _OnlineDot(),
                ],
              ],
            ),
            if (artisan.bio.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                artisan.bio.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyText(context),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

/// The landlord's endorsement, said plainly. This is the reason most tenants
/// will pick one name over another, so it leads the card rather than sitting
/// as a badge beside the name.
class _RecommendedTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.successSurface(context),
      borderRadius: AppTheme.cornerSm,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.thumb_up_alt_outlined,
          size: 13,
          color: AppTheme.successColor,
        ),
        const SizedBox(width: 6),
        Text(
          'RECOMMENDED BY YOUR LANDLORD',
          style: AppTheme.labelText(
            context,
            color: AppTheme.successColor,
          ).copyWith(fontSize: 10, letterSpacing: 0.6),
        ),
      ],
    ),
  );
}

/// Initial-in-a-circle, the same treatment the app bar gives an account.
/// There are no artisan photos in the API, and a stock avatar for everyone
/// makes a directory of real people look like placeholder data.
class _Avatar extends StatelessWidget {
  final ArtisanProfile artisan;

  const _Avatar({required this.artisan});

  @override
  Widget build(BuildContext context) {
    final name = artisan.displayName;
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return Container(
      height: 46,
      width: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.actionColor.withValues(alpha: 0.12),
        borderRadius: AppTheme.cornerMd,
      ),
      child: Text(
        initial,
        style: AppTheme.sectionTitle(context, color: AppTheme.actionColor),
      ),
    );
  }
}

/// "Used the app in the last hour": the closest thing to "will pick up the
/// phone today" the backend can tell us.
class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        height: 7,
        width: 7,
        decoration: const BoxDecoration(
          color: AppTheme.successColor,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        'ONLINE',
        style: AppTheme.labelText(
          context,
          color: AppTheme.successColor,
        ).copyWith(fontSize: 9, letterSpacing: 0.6),
      ),
    ],
  );
}
