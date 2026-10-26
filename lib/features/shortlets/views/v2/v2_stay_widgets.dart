import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/fade_page_route.dart';
import '../../../../core/utils/oasis_currency.dart';
import '../../../../core/utils/oasis_haptics.dart';
import '../../../../core/widgets/oasis_network_image.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_toast.dart';
import '../../../../core/widgets/v2_ui.dart';
import '../../../messaging/controllers/messaging_controller.dart';
import '../../../messaging/views/conversation_screen.dart';
import '../../controllers/saved_shortlets_controller.dart';
import '../../controllers/shortlet_controller.dart';
import '../../models/shortlet_models.dart';

/// The Home hero's backdrop when no listing has a photo yet. Decoration
/// only: a listing without photos shows [V2StayPhoto]'s "No photos yet"
/// tile, never this, because a guest would take it for the place itself.
const String v2FallbackStayPhoto = 'assets/images/quality_hero.png';

/// Something the guest can do about a booking: shown in the trip card's menu
/// and as buttons on the booking details screen.
class V2BookingAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDestructive;
  final bool isBusy;
  final bool isEnabled;

  const V2BookingAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
    this.isBusy = false,
    this.isEnabled = true,
  });

  VoidCallback? get onTapIfEnabled => isEnabled && !isBusy ? onTap : null;
}

/// How long is left to pay for an approved stay, or null when nothing is due.
String? v2PayWindow(ShortLetBooking booking) {
  final left = booking.timeLeftToPay;
  if (left == null) return null;
  if (left == Duration.zero) return 'The payment window has closed.';
  if (left.inHours >= 1) {
    return 'Pay within ${v2Plural(left.inHours, 'hour', 'hours')} to confirm '
        'this booking.';
  }
  final minutes = left.inMinutes < 1 ? 1 : left.inMinutes;
  return 'Pay within ${v2Plural(minutes, 'minute', 'minutes')} to confirm '
      'this booking.';
}

V2Tone v2ToneFor(ShortLetBookingStatus status) => switch (status) {
  ShortLetBookingStatus.paid ||
  ShortLetBookingStatus.checkedIn ||
  ShortLetBookingStatus.checkedOut ||
  ShortLetBookingStatus.completed => V2Tone.positive,
  ShortLetBookingStatus.pending ||
  ShortLetBookingStatus.approved => V2Tone.pending,
  ShortLetBookingStatus.disputed ||
  ShortLetBookingStatus.rejected ||
  ShortLetBookingStatus.expired => V2Tone.negative,
  ShortLetBookingStatus.cancelled ||
  ShortLetBookingStatus.unknown => V2Tone.neutral,
};

/// Whether a booking belongs under Past: checkout has happened, or nothing
/// more will happen to it. An open dispute, or a caution fee claim waiting
/// on the guest, is not past: something still needs doing.
bool v2IsPastTrip(ShortLetBooking booking) {
  if (booking.status.isClosed) return true;
  if (booking.status == ShortLetBookingStatus.disputed) return false;
  // A claim on the caution fee waiting for the guest's answer keeps the trip
  // where they look first.
  if (booking.cautionFeeStage == CautionFeeStage.claimed) return false;
  return booking.status == ShortLetBookingStatus.completed ||
      booking.status == ShortLetBookingStatus.checkedOut ||
      (booking.status.isPaid && booking.hasCheckedOut);
}

/// The listing a booking was made on, when the app has already loaded it.
/// Bookings carry no photos of their own, so this is where the photo comes
/// from.
ShortLetListing? v2ListingFor(
  ShortLetController controller,
  ShortLetBooking booking,
) {
  for (final candidate in [
    ...controller.browseListings,
    ...controller.listings,
  ]) {
    if (candidate.id == booking.listingId) return candidate;
  }
  return null;
}

/// "12 – 15 Dec 2026", or "28 Dec – 2 Jan 2027" across a month.
String v2DateRange(ShortLetBooking booking) {
  final start = booking.checkInDate;
  final end = booking.checkOutDate;
  if (start == null || end == null) {
    return '${booking.checkIn} – ${booking.checkOut}';
  }
  final sameMonth = start.year == end.year && start.month == end.month;
  final sameYear = start.year == end.year;
  final from = DateFormat(
    sameMonth
        ? 'd'
        : sameYear
        ? 'd MMM'
        : 'd MMM yyyy',
  ).format(start);
  return '$from – ${DateFormat('d MMM yyyy').format(end)}';
}

String v2Plural(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';

/// Opens (or creates) the message thread for a paid stay.
Future<void> v2OpenBookingConversation(
  BuildContext context,
  String bookingId,
) async {
  final controller = context.read<MessagingController>();
  final conversation = await controller.startConversation(
    shortLetBookingId: bookingId,
  );
  if (!context.mounted) return;
  if (conversation == null) {
    OasisToast.error(
      context,
      controller.errorMessage ??
          'Could not open that conversation. Try again in a moment.',
    );
    return;
  }
  Navigator.push(
    context,
    FadePageRoute(page: ConversationScreen(conversation: conversation)),
  );
}

/// Heart on a photo that saves or unsaves a shortlet.
class V2SaveButton extends StatelessWidget {
  final ShortLetListing listing;
  final double size;

  const V2SaveButton({super.key, required this.listing, this.size = 36});

  Future<void> _toggle(BuildContext context) async {
    OasisHaptics.select();
    final saved = await context.read<SavedShortLetsController>().toggle(
      listing,
    );
    if (!saved && context.mounted) {
      OasisToast.error(
        context,
        'Could not update your saved shortlets. Try again in a moment.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = context.select<SavedShortLetsController, bool>(
      (controller) => controller.isSaved(listing.id),
    );
    return Semantics(
      button: true,
      label: saved ? 'Remove from saved' : 'Save shortlet',
      excludeSemantics: true,
      child: OasisPressable(
        onTap: () => _toggle(context),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(saved),
              size: size * 0.52,
              color: saved ? AppTheme.terracottaColor : AppTheme.blackColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// A network photo that falls back to the bundled interior shot instead of an
/// empty block.
class V2StayPhoto extends StatelessWidget {
  final String? url;
  final double? height;
  final double? width;
  final double scrimOpacity;

  /// A bundled image to show instead of the "No photos yet" tile. Only for
  /// decoration, like the Home hero, never for a listing's own photo.
  final String? fallbackAsset;

  /// False when the listing itself has not been found (not loaded yet, or
  /// paused since the booking), so a missing [url] says nothing about its
  /// photos: the tile is shown without "No photos yet".
  final bool listingKnown;

  const V2StayPhoto({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.scrimOpacity = 0,
    this.fallbackAsset,
    this.listingKnown = true,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      if (fallbackAsset case final asset?) {
        return Image.asset(
          asset,
          height: height,
          width: width ?? double.infinity,
          fit: BoxFit.cover,
        );
      }
      // New places go live before their photos are added (backend, 2026-10-23),
      // so this is a state guests do see.
      return _NoPhotoYet(height: height, width: width, label: listingKnown);
    }
    return OasisNetworkImage(
      url: trimmed,
      height: height,
      width: width ?? double.infinity,
      placeholderIcon: Icons.holiday_village_outlined,
      scrimOpacity: scrimOpacity,
    );
  }
}

/// A stay on the home shelf: rounded photo, then name and rating, place, and
/// nightly price.
class V2StayCard extends StatelessWidget {
  final ShortLetListing listing;
  final VoidCallback onTap;
  final double width;

  const V2StayCard({
    super.key,
    required this.listing,
    required this.onTap,
    this.width = 268,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: OasisPressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                children: [
                  V2StayPhoto(url: listing.coverPhotoUrl, height: 206),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: V2SaveButton(listing: listing, size: 34),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          listing.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.cardTitle(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (listing.hasRating) ...[
                        const SizedBox(width: 6),
                        V2RatingLine(listing: listing, compact: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    listing.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  V2NightlyPrice(amount: listing.nightlyPrice),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "₦280,000 / night": the amount carries the weight, the unit does not.
class V2NightlyPrice extends StatelessWidget {
  final String amount;
  final double fontSize;

  const V2NightlyPrice({super.key, required this.amount, this.fontSize = 16});

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: OasisCurrency.format(amount),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppTheme.primaryTextColor(context),
          ),
        ),
        TextSpan(
          text: ' / night',
          style: TextStyle(
            fontSize: fontSize - 4,
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// "★ 4.8 (120 reviews)", or the minimum stay for a place nobody has rated
/// yet, so a new listing never shows a zero.
class V2RatingLine extends StatelessWidget {
  final ShortLetListing listing;

  /// "★ 4.8 (32)" rather than "★ 4.8 (32 reviews)".
  final bool compact;

  const V2RatingLine({super.key, required this.listing, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.bodyText(context).copyWith(fontSize: 12);
    if (!listing.hasRating) {
      return Text(
        'New · min ${v2Plural(listing.minimumNights, 'night', 'nights')}',
        style: style,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.star_rounded,
          size: 15,
          color: AppTheme.terracottaColor,
        ),
        const SizedBox(width: 3),
        Text(
          listing.ratingLabel!,
          style: style.copyWith(
            color: AppTheme.primaryTextColor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          compact
              ? '(${listing.reviewCount})'
              : '(${v2Plural(listing.reviewCount, 'review', 'reviews')})',
          style: style,
        ),
      ],
    );
  }
}

/// Icon and short text, for the facts row on trip cards.
class V2IconText extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const V2IconText({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: color ?? AppTheme.secondaryTextColor(context),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodyText(
            context,
            color: color ?? AppTheme.primaryTextColor(context),
          ).copyWith(fontSize: 13),
        ),
      ),
    ],
  );
}

/// Soft pink button for cancelling, as in the booking details mockup.
class V2DestructiveButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isBusy;

  const V2DestructiveButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = AppTheme.isDarkMode(context)
        ? const Color(0xFFE59A8F)
        : AppTheme.brickRedColor;
    return OasisPressable(
      onTap: isBusy ? null : onTap,
      pressedScale: 0.98,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.disputeSurface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: foreground.withValues(alpha: 0.25)),
        ),
        child: isBusy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: AppTheme.textMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

/// Neutral filled button, for secondary actions under the primary one.
class V2SoftButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  const V2SoftButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    pressedScale: 0.98,
    child: Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppTheme.primaryTextColor(context)),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: AppTheme.cardTitle(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

/// Stands in for a listing's photo when it has none yet: plain, so nobody
/// mistakes it for the place.
class _NoPhotoYet extends StatelessWidget {
  final double? height;
  final double? width;

  /// Whether to say "No photos yet", rather than show the icon alone.
  final bool label;

  const _NoPhotoYet({this.height, this.width, this.label = true});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: width ?? double.infinity,
    color: AppTheme.subtleSurfaceColor(context),
    alignment: Alignment.center,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final icon = Icon(
          Icons.photo_camera_outlined,
          size: 26,
          color: AppTheme.mutedTextColor(context),
        );
        // The label only where it fits: a thumbnail gets the icon alone.
        if (!label ||
            constraints.maxHeight < 90 ||
            constraints.maxWidth < 110) {
          return icon;
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 6),
            Text(
              'No photos yet',
              style: AppTheme.labelText(
                context,
                color: AppTheme.mutedTextColor(context),
              ),
            ),
          ],
        );
      },
    ),
  );
}
