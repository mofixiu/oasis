import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/widgets/landa_media_hero.dart';
import '../../../core/widgets/landa_network_image.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../reviews/models/review_models.dart';
import '../../reviews/views/widgets/reviews_section.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_models.dart';
import 'my_shortlet_bookings_screen.dart';
import 'request_booking_sheet.dart';
import '../../../core/utils/fade_page_route.dart';

/// One short let, and the button that asks the host for dates.
///
/// Requesting is not booking: nothing is held and nothing is charged until the
/// host approves. The screen says so plainly rather than presenting a Book
/// button that would set the wrong expectation.
class ShortLetListingScreen extends StatelessWidget {
  final ShortLetListing listing;

  /// The dates the tenant searched with, when they arrived from a dated
  /// search. Seeds the booking sheet so they do not pick the same stay twice,
  /// and is what the unavailable notice below refers to.
  final DateTimeRange? requestedDates;

  const ShortLetListingScreen({
    super.key,
    required this.listing,
    this.requestedDates,
  });

  Future<void> _request(BuildContext context) async {
    final booking = await openRequestBookingSheet(
      context,
      listing: listing,
      initialDates: requestedDates,
    );
    if (booking == null || !context.mounted) return;

    LandaToast.success(
      context,
      'Request sent. You will hear back from the host, and only pay if they '
      'say yes.',
    );
    Navigator.push(
      context,
      FadePageRoute(page: const MyShortLetBookingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = context.select<ShortLetController, bool>(
      (c) => c.isSubmitting,
    );
    // Every picture of the place, the walkthrough last. The header pages
    // through all of them, before this, the cover was the only photo a guest
    // could see without booking.
    final photos = listing.photoUrls.isNotEmpty
        ? listing.photoUrls
        : [if (listing.coverPhotoUrl != null) listing.coverPhotoUrl!];

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      // The photo runs under the status bar. A detail screen for somewhere
      // you might sleep should open with the room, not with a toolbar.
      extendBodyBehindAppBar: true,
      // White clock and battery, whatever the photo underneath is doing. The
      // status bar sits on the header's top scrim, which is dark by
      // construction, but iOS picks its own colour from the app's theme, so
      // a light-mode user would get black glyphs on a dark scrim.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.zero,
              children: [
                LandaMediaHero(
                  photoUrls: photos,
                  videoUrl: listing.hasVideo ? listing.videoUrl : null,
                  title: listing.title,
                  emptyIcon: Icons.holiday_village_outlined,
                  heroTag: landaMediaHeroTag('shortlet', listing.id),
                  // Name, place and rating over the photograph. The three
                  // things a guest checks first, in the order they check them,
                  // without having to scroll past the picture to find them.
                  overlay: _HeroOverlay(listing: listing),
                  // Clears the sheet below, which is lifted over the bottom of
                  // the photo by a corner radius. Without this the location
                  // line is half-covered by the page.
                  overlayBottomInset: 46,
                ),
                // Lifted over the bottom of the photo, so the page reads as one
                // sheet resting on the image rather than two stacked blocks.
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.pageBackground(context),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppTheme.radiusLg),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _details(context, isSubmitting),
                    ),
                  ),
                ),
              ],
            ),

            // Floats on the photo rather than sitting in a bar above it.
            Positioned(
              top: 0,
              left: 12,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: LandaMediaCircleButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Everything below the photo header.
  ///
  /// Split out of `build` so the header, the sheet and the floating back
  /// button stay readable as three things rather than one 200-line tree.
  List<Widget> _details(BuildContext context, bool isSubmitting) {
    return [
      // Said again here rather than only on the search card: this is the
      // screen with the request button on it, and a guest who taps
      // through deserves to know before they pick their dates.
      if (listing.isUnavailableForPeriod) ...[
        _UnavailableNotice(
          reason: listing.unavailableLabel,
          dates: requestedDates,
        ),
        const SizedBox(height: 18),
      ],

      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerLg,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LandaCurrency.format(listing.nightlyPrice),
                    style: AppTheme.sectionTitle(
                      context,
                      color: AppTheme.actionColor,
                    ),
                  ),
                  Text('per night', style: AppTheme.labelText(context)),
                ],
              ),
            ),
            _Stat(
              icon: Icons.nights_stay_outlined,
              value: '${listing.minimumNights}',
              label: listing.minimumNights == 1 ? 'night min' : 'nights min',
            ),
            const SizedBox(width: 16),
            _Stat(
              icon: Icons.group_outlined,
              value: '${listing.maximumGuests}',
              label: listing.maximumGuests == 1 ? 'guest max' : 'guests max',
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),

      // The host's own words, above everything the app has to say about the
      // place. A guest deciding between two flats at the same price is
      // deciding on this paragraph; burying it under the policy notices
      // would put the app's boilerplate ahead of the only part written for
      // them.
      if (listing.hasDescription) ...[
        Text(listing.description, style: AppTheme.bodyText(context)),
        const SizedBox(height: 18),
      ],

      // Stated before the guest picks dates, not at checkout. A deposit
      // is the single largest surprise in a nightly booking: it can be
      // more than the stay, and a guest who finds out about it after
      // the host has approved has already been made to wait for nothing.
      if (listing.hasCautionFee) ...[
        _CautionFeeNotice(amount: listing.cautionFee),
        const SizedBox(height: 18),
      ],

      _CancellationPolicyNotice(listing: listing),
      const SizedBox(height: 18),

      if (listing.bedrooms > 0 || listing.bathrooms > 0) ...[
        _Detail(
          icon: Icons.king_bed_outlined,
          title: 'The space',
          body:
              '${listing.bedrooms} '
              '${listing.bedrooms == 1 ? 'bedroom' : 'bedrooms'} · '
              '${listing.bathrooms} '
              '${listing.bathrooms == 1 ? 'bathroom' : 'bathrooms'}',
        ),
        const SizedBox(height: 14),
      ],

      if (_availability(listing) case final window?) ...[
        _Detail(
          icon: Icons.event_available_outlined,
          title: 'Available',
          body: window,
        ),
        const SizedBox(height: 14),
      ],

      if (listing.houseRules.isNotEmpty) ...[
        _Detail(
          icon: Icons.rule_outlined,
          title: 'House rules',
          body: listing.houseRules,
        ),
        const SizedBox(height: 14),
      ],

      // Arrival details are released by the backend only after payment, so
      // saying so beats leaving a guest wondering where the address is.
      _Detail(
        icon: Icons.vpn_key_outlined,
        title: 'Getting in',
        body: 'The host shares check-in details once your stay is paid for.',
      ),
      const SizedBox(height: 24),

      LandaButton(
        label: 'Ask for these dates',
        icon: Icons.calendar_month_outlined,
        isBusy: isSubmitting,
        onPressed: isSubmitting ? null : () => _request(context),
      ),
      const SizedBox(height: 10),
      Text(
        'Nothing is charged yet. You pay only after the host approves, and '
        'the refundable caution fee is held until checkout.',
        textAlign: TextAlign.center,
        style: AppTheme.labelText(
          context,
          color: AppTheme.secondaryTextColor(context),
        ),
      ),
      const SizedBox(height: 32),

      // Below the request button rather than above it. Reviews are what a
      // guest reads when they are unsure; someone already convinced
      // should not have to scroll past twelve of them to book.
      ReviewsSection(
        subject: ReviewSubject.shortLet,
        subjectId: listing.id,
        title: 'What guests said',
      ),
    ];
  }

  /// "1 Sep – 31 Dec 2026", or null when the host set no window.
  static String? _availability(ShortLetListing listing) {
    final from = listing.availableFrom;
    final to = listing.availableTo;
    if (from == null && to == null) return null;

    final start = from == null ? null : DateTime.tryParse(from);
    final end = to == null ? null : DateTime.tryParse(to);
    final format = DateFormat('d MMM yyyy');

    if (start != null && end != null) {
      return '${format.format(start)} – ${format.format(end)}';
    }
    if (start != null) return 'From ${format.format(start)}';
    if (end != null) return 'Until ${format.format(end)}';
    return null;
  }
}

/// The name, place and rating, laid over the bottom of the photo header.
///
/// White on the scrim rather than terracotta on the page below it. This is
/// the one place in the app where type sits on a photograph, and the reason
/// is that a guest should be able to see the room and read what it is called
/// in a single glance, without the title having pushed the picture up the
/// screen to make room for itself.
class _HeroOverlay extends StatelessWidget {
  final ShortLetListing listing;

  const _HeroOverlay({required this.listing});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (listing.hasRating) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                '${listing.ratingLabel} · ${listing.reviewCount} '
                '${listing.reviewCount == 1 ? 'review' : 'reviews'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTheme.textXs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      Text(
        listing.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.screenTitle(context, color: Colors.white).copyWith(
          // A drop shadow rather than a heavier scrim: it holds the letters
          // against a busy photo without dimming the whole picture.
          shadows: const [
            Shadow(
              color: Color(0x99000000),
              blurRadius: 14,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
      if (listing.location.isNotEmpty) ...[
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.place_outlined, size: 14, color: Colors.white70),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                listing.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: AppTheme.textSm,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(color: Color(0x99000000), blurRadius: 10)],
                ),
              ),
            ),
          ],
        ),
      ],
    ],
  );
}

class _CancellationPolicyNotice extends StatelessWidget {
  final ShortLetListing listing;

  const _CancellationPolicyNotice({required this.listing});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.subtleSurfaceColor(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.policy_outlined, size: 18, color: AppTheme.actionColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${listing.cancellationPolicy.label} cancellation',
                style: AppTheme.cardTitle(context),
              ),
              const SizedBox(height: 3),
              Text(
                listing.resolvedCancellationPolicySummary,
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your exact refund is confirmed by Landa when you cancel.',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.mutedTextColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Says the searched dates will not work here, and why.
///
/// Not a blocker: the guest can still ask for different dates, so this
/// explains rather than disables. The request button below stays live.
class _UnavailableNotice extends StatelessWidget {
  final String reason;
  final DateTimeRange? dates;

  const _UnavailableNotice({required this.reason, required this.dates});

  @override
  Widget build(BuildContext context) {
    final range = dates;
    final format = DateFormat('d MMM');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 18,
            color: AppTheme.secondaryTextColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  range == null
                      ? 'Not free for your dates'
                      : 'Not free ${format.format(range.start)} – '
                            '${format.format(range.end)}',
                  style: AppTheme.cardTitle(context),
                ),
                const SizedBox(height: 4),
                Text(reason, style: AppTheme.bodyText(context)),
                const SizedBox(height: 6),
                Text(
                  'You can still ask the host for different dates.',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Stat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, size: 18, color: AppTheme.secondaryTextColor(context)),
      const SizedBox(height: 4),
      Text(value, style: AppTheme.cardTitle(context)),
      Text(label, style: AppTheme.labelText(context)),
    ],
  );
}

class _Detail extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Detail({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppTheme.mutedTextColor(context)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.cardTitle(context)),
            const SizedBox(height: 3),
            Text(body, style: AppTheme.bodyText(context)),
          ],
        ),
      ),
    ],
  );
}

/// Says there is a refundable deposit, how much, and when it comes back.
///
/// Framed as "you get this back" rather than "you must pay this", because
/// that is the true shape of it, but the amount leads, since that is the
/// number the guest has to actually have.
class _CautionFeeNotice extends StatelessWidget {
  final String amount;

  const _CautionFeeNotice({required this.amount});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.vacantSurface(context),
      borderRadius: AppTheme.cornerLg,
      border: Border.all(color: AppTheme.vacantColor.withValues(alpha: 0.45)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.shield_outlined,
          size: 20,
          color: AppTheme.vacantColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${LandaCurrency.format(amount)} refundable deposit',
                style: AppTheme.cardTitle(context),
              ),
              const SizedBox(height: 4),
              Text(
                'This host asks for a caution fee. It is added to what you pay '
                'and returned after checkout, unless they report damage.',
                style: AppTheme.bodyText(context),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
