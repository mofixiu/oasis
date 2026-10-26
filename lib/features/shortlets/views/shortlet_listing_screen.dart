import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/widgets/oasis_media_hero.dart';
import '../../../core/widgets/oasis_network_image.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_toast.dart';
import 'v2/v2_stay_widgets.dart';
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
  final bool isV2;

  /// The dates the tenant searched with, when they arrived from a dated
  /// search. Seeds the booking sheet so they do not pick the same stay twice,
  /// and is what the unavailable notice below refers to.
  final DateTimeRange? requestedDates;

  const ShortLetListingScreen({
    super.key,
    required this.listing,
    this.isV2 = false,
    this.requestedDates,
  });

  Future<void> _request(BuildContext context) async {
    final booking = await openRequestBookingSheet(
      context,
      listing: listing,
      initialDates: requestedDates,
    );
    if (booking == null || !context.mounted) return;

    OasisToast.success(
      context,
      'Request sent. You will hear back from the host, and only pay if they '
      'say yes.',
    );
    Navigator.push(
      context,
      FadePageRoute(page: MyShortLetBookingsScreen(isV2: isV2)),
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
    if (isV2) return _buildV2(context, isSubmitting, photos);

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
                OasisMediaHero(
                  photoUrls: photos,
                  videoUrl: listing.hasVideo ? listing.videoUrl : null,
                  title: listing.title,
                  emptyIcon: Icons.holiday_village_outlined,
                  heroTag: oasisMediaHeroTag('shortlet', listing.id),
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
                  child: OasisMediaCircleButton(
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

  /// The v2 listing: photos, then the name and rating on the page, the
  /// space at a glance, the host's description, and a price bar that stays
  /// on screen with the request button.
  Widget _buildV2(
    BuildContext context,
    bool isSubmitting,
    List<String> photos,
  ) {
    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      extendBodyBehindAppBar: true,
      body: _V2PhotoScrollChrome(
        builder: (context, controller, pastPhoto) => Stack(
          children: [
            ListView(
              controller: controller,
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                OasisMediaHero(
                  photoUrls: photos,
                  videoUrl: listing.hasVideo ? listing.videoUrl : null,
                  title: listing.title,
                  emptyIcon: Icons.holiday_village_outlined,
                  heroTag: oasisMediaHeroTag('shortlet', listing.id),
                  overlayBottomInset: 46,
                  counterAtBottom: true,
                  counterBottomInset: 40,
                ),
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
                      children: _v2Details(context),
                    ),
                  ),
                ),
              ],
            ),
            // Once the photo has scrolled away, a bar slides in behind the
            // back and save buttons so they never sit on the text.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: pastPhoto ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    height: MediaQuery.paddingOf(context).top + 60,
                    decoration: BoxDecoration(
                      color: AppTheme.pageBackground(context),
                      border: Border(
                        bottom: BorderSide(
                          color: AppTheme.borderColor(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 12,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OasisMediaCircleButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 16,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: V2SaveButton(listing: listing, size: 42),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _V2RequestBar(
                listing: listing,
                isSubmitting: isSubmitting,
                onRequest: () => _request(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _v2Details(BuildContext context) => [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            listing.title,
            style: AppTheme.screenTitle(
              context,
            ).copyWith(fontSize: 24, letterSpacing: -0.8),
          ),
        ),
        if (listing.hasRating) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: V2RatingLine(listing: listing, compact: true),
          ),
        ],
      ],
    ),
    if (listing.location.isNotEmpty) ...[
      const SizedBox(height: 4),
      Text(
        listing.location,
        style: AppTheme.bodyText(context).copyWith(fontSize: 14),
      ),
    ],
    const SizedBox(height: 20),
    Row(
      children: [
        if (listing.bedrooms > 0)
          Expanded(
            child: _V2Amenity(
              icon: Icons.king_bed_outlined,
              label: v2Plural(listing.bedrooms, 'Bedroom', 'Bedrooms'),
            ),
          ),
        if (listing.bathrooms > 0)
          Expanded(
            child: _V2Amenity(
              icon: Icons.bathtub_outlined,
              label: v2Plural(listing.bathrooms, 'Bath', 'Baths'),
            ),
          ),
        Expanded(
          child: _V2Amenity(
            icon: Icons.people_outline_rounded,
            label: v2Plural(listing.maximumGuests, 'Guest', 'Guests'),
          ),
        ),
        Expanded(
          child: _V2Amenity(
            icon: Icons.nights_stay_outlined,
            label:
                '${listing.minimumNights}+ '
                '${listing.minimumNights == 1 ? 'night' : 'nights'}',
          ),
        ),
      ],
    ),
    const SizedBox(height: 20),
    Divider(height: 1, color: AppTheme.borderColor(context)),
    const SizedBox(height: 20),
    if (listing.isUnavailableForPeriod) ...[
      _UnavailableNotice(
        reason: listing.unavailableLabel,
        dates: requestedDates,
      ),
      const SizedBox(height: 18),
    ],
    if (listing.hasDescription) ...[
      Text('About this shortlet', style: AppTheme.sectionTitle(context)),
      const SizedBox(height: 8),
      _V2ReadMore(text: listing.description),
      const SizedBox(height: 20),
    ],
    if (listing.hasCautionFee) ...[
      _CautionFeeNotice(amount: listing.cautionFee),
      const SizedBox(height: 14),
    ],
    _CancellationPolicyNotice(listing: listing),
    const SizedBox(height: 20),
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
    _Detail(
      icon: Icons.vpn_key_outlined,
      title: 'Getting in',
      body: 'The host shares check-in details once your booking is paid for.',
    ),
    const SizedBox(height: 28),
    ReviewsSection(
      subject: ReviewSubject.shortLet,
      subjectId: listing.id,
      title: 'What guests said',
    ),
  ];

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
                    OasisCurrency.format(listing.nightlyPrice),
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

      OasisButton(
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

/// Tracks whether the photo header has scrolled away, and sets the status
/// bar to match: light over the photo, dark over the page.
class _V2PhotoScrollChrome extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    ScrollController controller,
    bool pastPhoto,
  )
  builder;

  const _V2PhotoScrollChrome({required this.builder});

  @override
  State<_V2PhotoScrollChrome> createState() => _V2PhotoScrollChromeState();
}

class _V2PhotoScrollChromeState extends State<_V2PhotoScrollChrome> {
  /// Roughly where the photo header ends under the status bar and buttons.
  static const double _threshold = 250;

  final _controller = ScrollController();
  bool _pastPhoto = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final past = _controller.offset > _threshold;
      if (past != _pastPhoto) setState(() => _pastPhoto = past);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = !_pastPhoto || AppTheme.isDarkMode(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: light ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: widget.builder(context, _controller, _pastPhoto),
    );
  }
}

/// An icon in a soft circle with a short label, for the space at a glance.
class _V2Amenity extends StatelessWidget {
  final IconData icon;
  final String label;

  const _V2Amenity({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Icon(icon, size: 22, color: AppTheme.primaryTextColor(context)),
      ),
      const SizedBox(height: 8),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.bodyText(context).copyWith(
          color: AppTheme.primaryTextColor(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

/// The host's description, four lines first with a way to read the rest.
class _V2ReadMore extends StatefulWidget {
  final String text;

  const _V2ReadMore({required this.text});

  @override
  State<_V2ReadMore> createState() => _V2ReadMoreState();
}

class _V2ReadMoreState extends State<_V2ReadMore> {
  static const _collapsedLines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.bodyText(
      context,
      color: AppTheme.readingTextColor(context).withValues(alpha: 0.82),
    ).copyWith(fontSize: 14, height: 1.55);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : _collapsedLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows || _expanded)
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: AppTheme.primaryTextColor(context),
                ),
                iconAlignment: IconAlignment.end,
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                ),
                label: Text(
                  _expanded ? 'Show less' : 'Read more',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Price and the request button, pinned to the bottom of the listing.
///
/// "Request to book", not "Book now": nothing is held or charged until the
/// host approves.
class _V2RequestBar extends StatelessWidget {
  final ShortLetListing listing;
  final bool isSubmitting;
  final VoidCallback onRequest;

  const _V2RequestBar({
    required this.listing,
    required this.isSubmitting,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      border: Border(top: BorderSide(color: AppTheme.borderColor(context))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              V2NightlyPrice(amount: listing.nightlyPrice, fontSize: 18),
              const SizedBox(height: 2),
              Text(
                'Pay only if the host approves',
                style: AppTheme.bodyText(context).copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OasisButton(
          label: 'Request to book',
          expand: false,
          isBusy: isSubmitting,
          onPressed: isSubmitting ? null : onRequest,
        ),
      ],
    ),
  );
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
                'Your exact refund is confirmed by Oasis when you cancel.',
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
                '${OasisCurrency.format(amount)} refundable deposit',
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
