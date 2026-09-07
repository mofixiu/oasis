import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/custom_bottom_navbar.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_segmented_tabs.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../messaging/views/widgets/message_action_button.dart';
import '../../reviews/views/widgets/rating_stars.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_models.dart';
import 'create_shortlet_sheet.dart';
import 'edit_nightly_price_sheet.dart';
import 'widgets/shortlet_booking_card.dart';
import '../../../core/utils/landa_input_formatters.dart';

/// The host's side of short lets: requests to decide on, and the places on
/// offer.
///
/// Requests lead because they are the only part with someone waiting: a guest
/// cannot pay until the host answers, and an approval starts a 24-hour clock.
class LandlordShortLetsScreen extends StatefulWidget {
  const LandlordShortLetsScreen({super.key});

  @override
  State<LandlordShortLetsScreen> createState() =>
      _LandlordShortLetsScreenState();
}

class _LandlordShortLetsScreenState extends State<LandlordShortLetsScreen>
    with
        SingleTickerProviderStateMixin,
        AutoRefreshMixin<LandlordShortLetsScreen> {
  /// Room for the bottom bar and the button floating above it, so the last
  /// row can always be scrolled out from under both.
  static const double _listBottomInset = CustomBottomNavbar.reservedHeight + 76;

  late final TabController _tabs = TabController(length: 2, vsync: this);

  /// Polls while open. Requests arrive from guests at any hour and the host is
  /// the blocker on all of them: a request sitting unseen is a booking not
  /// made, and it should not need a pull to appear.
  @override
  Duration? get autoRefreshInterval => kLandaPollInterval;

  @override
  Future<void> onAutoRefresh() => _reload();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    final controller = context.read<ShortLetController>();
    return Future.wait([
      controller.loadLandlordBookings(),
      controller.loadLandlordListings(),
    ]);
  }

  Future<void> _approve(ShortLetBooking booking) async {
    final controller = context.read<ShortLetController>();
    final ok = await controller.approveBooking(booking.id);
    if (!mounted) return;

    if (ok) {
      LandaToast.success(
        context,
        'Approved. ${booking.guestLabel} has 24 hours to pay.',
      );
      // Approval changes the totals and the payment deadline on the backend's
      // copy, so the list is re-read rather than left showing the version the
      // decision endpoint happened to echo back.
      await refreshNow();
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not approve that booking. Try again in a moment.',
      );
    }
  }

  Future<void> _reject(ShortLetBooking booking) async {
    final reason = await _askReason(booking);
    if (reason == null || !mounted) return;

    final controller = context.read<ShortLetController>();
    final ok = await controller.rejectBooking(
      booking.id,
      reason: reason.isEmpty ? null : reason,
    );
    if (!mounted) return;

    if (ok) {
      LandaToast.success(context, 'Request declined.');
      await refreshNow();
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not decline that booking. Try again in a moment.',
      );
    }
  }

  /// Collects an optional reason. Returns null when the host backed out, and
  /// an empty string when they declined without saying why.
  Future<String?> _askReason(ShortLetBooking booking) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          'Decline this request?',
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${booking.guestLabel} will be told. A short reason helps them '
              'try different dates.',
              style: AppTheme.bodyText(dialogContext),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 2,
              style: AppTheme.bodyText(dialogContext),
              decoration: InputDecoration(
                hintText: 'Already booked those nights.',
                hintStyle: AppTheme.bodyText(
                  dialogContext,
                  color: AppTheme.mutedTextColor(dialogContext),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(
              'Decline',
              style: AppTheme.cardTitle(
                dialogContext,
                color: AppTheme.disputeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createListing({ShortLetListing? existing}) async {
    final saved = await openCreateShortLetSheet(context, existing: existing);
    if (saved && mounted) await _reload();
  }

  /// The short way to the only number a host changes often.
  ///
  /// The full edit sheet reaches the same field, and a host who wants to
  /// change their house rules as well should use it. This exists because
  /// nine questions between a host and a ₦5,000 price drop is how a price
  /// stops getting adjusted, and a stay that is never repriced is a stay
  /// that sits empty.
  Future<void> _editPrice(ShortLetListing listing) async {
    final saved = await openEditNightlyPriceSheet(context, listing: listing);
    if (saved && mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();
    final pending = controller.pendingBookingCount;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Short lets',
                  style: AppTheme.screenTitle(
                    context,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Let a unit by the night. You approve every stay; your '
                  'payout releases around check-in, unless a guest reports '
                  'a problem first.',
                  style: AppTheme.bodyText(context),
                ),
              ],
            ),
          ),
          LandaSegmentedTabs(
            controller: _tabs,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
            segments: [
              LandaSegment('Requests', badgeCount: pending),
              const LandaSegment('My places'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                RefreshIndicator(
                  onRefresh: _reload,
                  child: _bookingsTab(context, controller),
                ),
                RefreshIndicator(
                  onRefresh: _reload,
                  child: _listingsTab(context, controller),
                ),
              ],
            ),
          ),
        ],
      ),
      // Lifted clear of the floating bottom bar, which is an overlay above
      // this Scaffold rather than part of it: left at its default position
      // the button sits behind the bar and cannot be tapped.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(
          bottom: CustomBottomNavbar.reservedHeight,
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _createListing(),
          backgroundColor: AppTheme.actionColor,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: const Text('List a place'),
        ),
      ),
    );
  }

  Widget _bookingsTab(BuildContext context, ShortLetController controller) {
    final live = controller.liveBookings;
    final closed = controller.closedBookings;

    if (!controller.hasLoaded(ShortLetController.kBookingsKey) ||
        (controller.isLoading && controller.bookings.isEmpty)) {
      return const LandaSkeletonList(count: 3);
    }
    if (controller.hasError && controller.bookings.isEmpty) {
      return LandaErrorState(
        message: controller.errorMessage,
        isConnectionError: controller.errorIsConnection,
        onRetry: _reload,
      );
    }
    if (controller.bookings.isEmpty) {
      return LandaEmptyState(
        icon: Icons.calendar_month_outlined,
        title: 'No booking requests yet',
        message:
            'When a guest asks to stay, their dates land here for you to '
            'approve or decline.',
        actionLabel: 'List a place',
        actionIcon: Icons.add_home_outlined,
        onAction: _createListing,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, _listBottomInset),
      children: [
        for (var index = 0; index < live.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: LandaEntrance(
              index: index,
              child: ShortLetBookingCard(
                booking: live[index],
                isLandlord: true,
                actions: _decisionActions(live[index], controller),
              ),
            ),
          ),
        if (closed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'CLOSED',
            style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
          ),
          const SizedBox(height: 10),
          for (final booking in closed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ShortLetBookingCard(booking: booking, isLandlord: true),
            ),
        ],
      ],
    );
  }

  List<Widget> _decisionActions(
    ShortLetBooking booking,
    ShortLetController controller,
  ) {
    if (booking.status.needsLandlordDecision) {
      // Per-booking, so deciding one request does not disable the rest.
      final busy = controller.isDeciding(booking.id);
      return [
        Row(
          children: [
            Expanded(
              child: LandaButton(
                label: 'Decline',
                icon: Icons.close_rounded,
                outlined: true,
                color: AppTheme.disputeColor,
                onPressed: busy ? null : () => _reject(booking),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LandaButton(
                label: 'Approve',
                icon: Icons.check_rounded,
                isBusy: busy,
                onPressed: busy ? null : () => _approve(booking),
              ),
            ),
          ],
        ),
      ];
    }

    // Past the decision, there can be several things worth doing at once:
    // messaging the guest, withdrawing in an emergency, claiming against a
    // deposit, so this collects whichever apply rather than returning after
    // the first, the way the decision above does.
    final actions = <Widget>[];
    final busy = controller.isSubmitting;

    if (booking.canMessage) {
      actions.add(
        MessageActionButton(
          shortLetBookingId: booking.id,
          label: 'Message the guest',
          expanded: true,
        ),
      );
    }

    if (booking.canBeCancelledByHost) {
      if (actions.isNotEmpty) actions.add(const SizedBox(height: 8));
      actions.add(
        LandaButton(
          label: 'Cancel booking',
          icon: Icons.event_busy_outlined,
          outlined: true,
          color: AppTheme.disputeColor,
          onPressed: busy ? null : () => _cancelAsHost(booking),
        ),
      );
    }

    if (booking.canClaimCautionFee) {
      if (actions.isNotEmpty) actions.add(const SizedBox(height: 8));
      actions.add(
        LandaButton(
          label: 'Claim caution fee',
          icon: Icons.shield_outlined,
          outlined: true,
          onPressed: busy ? null : () => _openCautionClaim(booking),
        ),
      );
    }

    return actions;
  }

  /// The host's own withdrawal from a booking: an emergency, not the
  /// ordinary decline. Requires a reason, unlike the tenant's own cancel.
  Future<void> _cancelAsHost(ShortLetBooking booking) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          'Cancel this booking?',
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${booking.guestLabel} will be told, and gets back everything '
              'they paid. Say why. This is meant for emergencies, not a way '
              'to back out of a booking you approved.',
              style: AppTheme.bodyText(dialogContext),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLines: 2,
              autofocus: true,
              style: AppTheme.bodyText(dialogContext),
              decoration: InputDecoration(
                hintText: 'Emergency maintenance.',
                hintStyle: AppTheme.bodyText(
                  dialogContext,
                  color: AppTheme.mutedTextColor(dialogContext),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonController.text.trim()),
            child: Text(
              'Cancel booking',
              style: AppTheme.cardTitle(
                dialogContext,
                color: AppTheme.disputeColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;

    final controller = context.read<ShortLetController>();
    final ok = await controller.cancelBookingAsHost(booking.id, reason: reason);
    if (!mounted) return;

    if (ok) {
      LandaToast.success(
        context,
        '${booking.guestLabel} has been told and refunded.',
      );
      await refreshNow();
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not cancel that booking. Try again in a moment.',
      );
    }
  }

  /// Claims some or all of a checked-out stay's caution fee.
  ///
  /// Deliberately no evidence upload here: the backend accepts image URLs
  /// for it, and this sheet has no file-storage endpoint to put one at, so
  /// the claim goes in with a written reason only. Worth adding once such an
  /// endpoint exists.
  Future<void> _openCautionClaim(ShortLetBooking booking) async {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          'Claim the caution fee?',
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Up to ${LandaCurrency.format(booking.cautionFee)} is held. '
              'Leave the amount blank to claim all of it. Whatever you do '
              'not claim goes back to the guest right away.',
              style: AppTheme.bodyText(dialogContext),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              inputFormatters: const [LandaThousandsFormatter()],
              style: AppTheme.bodyText(dialogContext),
              decoration: InputDecoration(
                hintText: 'Amount (₦). Optional, defaults to the full fee',
                hintStyle: AppTheme.bodyText(
                  dialogContext,
                  color: AppTheme.mutedTextColor(dialogContext),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 2,
              autofocus: true,
              style: AppTheme.bodyText(dialogContext),
              decoration: InputDecoration(
                hintText: 'Broken lamp in the living room.',
                hintStyle: AppTheme.bodyText(
                  dialogContext,
                  color: AppTheme.mutedTextColor(dialogContext),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send claim'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      LandaToast.error(context, 'Say what the claim is for.');
      return;
    }

    final rawAmount = LandaThousandsFormatter.digitsOf(
      amountController.text,
    );
    final controller = context.read<ShortLetController>();
    final ok = await controller.openCautionClaim(
      bookingId: booking.id,
      claimedAmount: rawAmount.isEmpty ? null : '$rawAmount.00',
      reason: reason,
    );
    if (!mounted) return;

    if (ok) {
      LandaToast.success(
        context,
        'Claim sent. ${booking.guestLabel} has to respond before anything '
        'moves.',
      );
      await refreshNow();
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not send that claim. Try again in a moment.',
      );
    }
  }

  Widget _listingsTab(BuildContext context, ShortLetController controller) {
    final listings = controller.listings;

    if (!controller.hasLoaded(ShortLetController.kListingsKey) ||
        (controller.isLoading && listings.isEmpty)) {
      return const LandaSkeletonList(count: 3);
    }
    if (controller.hasError && listings.isEmpty) {
      return LandaErrorState(
        message: controller.errorMessage,
        isConnectionError: controller.errorIsConnection,
        onRetry: _reload,
      );
    }
    if (listings.isEmpty) {
      return LandaEmptyState(
        icon: Icons.holiday_village_outlined,
        title: 'Nothing listed yet',
        message:
            'Offer a unit by the night and guests can ask to stay. You decide '
            'who comes, and you can stop taking bookings any time.',
        actionLabel: 'List a place',
        actionIcon: Icons.add_rounded,
        onAction: () => _createListing(),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, _listBottomInset),
      children: [
        for (var index = 0; index < listings.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: LandaEntrance(
              index: index,
              child: _ListingRow(
                listing: listings[index],
                onTap: () => _createListing(existing: listings[index]),
                onEditPrice: () => _editPrice(listings[index]),
              ),
            ),
          ),
      ],
    );
  }
}

/// The pencil beside a listing's nightly rate.
///
/// Its own widget so the tap does not fall through to the row's own
/// [LandaPressable], which opens the nine-field editor: two different
/// destinations a millimetre apart, and getting the wrong one is a host
/// scrolling a form they did not ask for.
class _PriceEditButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _PriceEditButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: 'Change the price',
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    icon: const Icon(
      Icons.edit_outlined,
      size: 17,
      color: AppTheme.actionColor,
    ),
  );
}

class _ListingRow extends StatelessWidget {
  final ShortLetListing listing;
  final VoidCallback onTap;

  /// Opens the price-only sheet. Separate from [onTap], which opens the full
  /// listing editor.
  final VoidCallback onEditPrice;

  const _ListingRow({
    required this.listing,
    required this.onTap,
    required this.onEditPrice,
  });

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    pressedScale: 0.99,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  listing.title,
                  style: AppTheme.cardTitle(context),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Paused is worth stating plainly: a host wondering why nobody
              // is booking should be able to see the reason here.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      (listing.isActive
                              ? AppTheme.successColor
                              : AppTheme.mutedTextColor(context))
                          .withValues(alpha: 0.12),
                  borderRadius: AppTheme.cornerSm,
                ),
                child: Text(
                  listing.isActive ? 'Live' : 'Paused',
                  style: AppTheme.labelText(
                    context,
                    color: listing.isActive
                        ? AppTheme.successColor
                        : AppTheme.mutedTextColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${LandaCurrency.format(listing.nightlyPrice)} / night · '
                  'min ${listing.minimumNights} '
                  '${listing.minimumNights == 1 ? 'night' : 'nights'} · '
                  'sleeps ${listing.maximumGuests}',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ),
              // On the price rather than in a menu. Repricing is the most
              // frequent thing a host does to a live listing and the row is
              // where they are already looking at the number.
              _PriceEditButton(onPressed: onEditPrice),
            ],
          ),
          if (listing.hasCautionFee) ...[
            const SizedBox(height: 4),
            Text(
              '${LandaCurrency.format(listing.cautionFee)} refundable caution '
              'fee',
              style: AppTheme.labelText(context, color: AppTheme.vacantColor),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            // Said in both states. A host who set no window needs to know the
            // listing is bookable all year rather than assume it is broken.
            _window(listing) ?? 'Bookable any dates',
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
          // A listing with no write-up is the one thing on this row the host
          // can fix in thirty seconds and that measurably costs them
          // bookings, so it is named rather than left to be noticed. The row
          // already opens the edit sheet, which is where the field is.
          if (!listing.hasDescription) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 16,
                  color: AppTheme.actionColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No description yet. Guests skip past a place they '
                    'cannot picture.',
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.actionColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (listing.hasRating) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                RatingStars(rating: listing.averageRating!, size: 13),
                const SizedBox(width: 6),
                Text(
                  '${listing.ratingLabel} from ${listing.reviewCount} '
                  '${listing.reviewCount == 1 ? 'guest' : 'guests'}',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  static String? _window(ShortLetListing listing) {
    final from = DateTime.tryParse(listing.availableFrom ?? '');
    final to = DateTime.tryParse(listing.availableTo ?? '');
    final format = DateFormat('d MMM yyyy');
    if (from != null && to != null) {
      return 'Bookable ${format.format(from)} – ${format.format(to)}';
    }
    if (from != null) return 'Bookable from ${format.format(from)}';
    if (to != null) return 'Bookable until ${format.format(to)}';
    return null;
  }
}
