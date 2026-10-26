import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/oasis_currency.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_toast.dart';
import '../../../../core/widgets/v2_ui.dart';
import '../../controllers/shortlet_controller.dart';
import '../../models/shortlet_models.dart';
import '../widgets/caution_fee_widgets.dart';
import 'v2_stay_widgets.dart';

/// Everything about one stay: where, when, what it cost, and what can still
/// be done about it.
class V2BookingDetailsScreen extends StatefulWidget {
  final ShortLetBooking booking;
  final bool isHost;

  /// The actions open to the viewer, worked out by the screen that owns
  /// them. Called with the latest copy of the booking on every build, so a
  /// cancelled stay stops offering to be cancelled.
  final List<V2BookingAction> Function(ShortLetBooking booking)? actionsFor;

  /// Opens the answer sheet for a host's claim on the caution fee.
  final Future<void> Function(ShortLetBooking booking)? onRespondToClaim;

  const V2BookingDetailsScreen({
    super.key,
    required this.booking,
    this.isHost = false,
    this.actionsFor,
    this.onRespondToClaim,
  });

  @override
  State<V2BookingDetailsScreen> createState() => _V2BookingDetailsScreenState();
}

class _V2BookingDetailsScreenState extends State<V2BookingDetailsScreen> {
  static const double _photoHeight = 270;

  final _scrollController = ScrollController();
  int _photoIndex = 0;

  /// Whether the photo has scrolled out from under the status bar, which
  /// then needs dark icons on the page.
  bool _pastPhoto = false;

  @override
  void initState() {
    super.initState();
    // The photos come from the listing. Opened straight from a notification
    // or a chat, the listings may not have loaded yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<ShortLetController>();
      if (controller.browseListings.isEmpty) controller.loadBrowseListings();
    });
    _scrollController.addListener(() {
      final past = _scrollController.offset > _photoHeight - 30;
      if (past != _pastPhoto) setState(() => _pastPhoto = past);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Check-in and check-out times are not in the booking payload yet; these
  /// are the house defaults the previous details screen also showed.
  static const _checkInTime = '2:00 PM';
  static const _checkOutTime = '11:00 AM';

  Future<void> _openDirections(String address) async {
    final uri = Uri.https('maps.apple.com', '/', {'q': address});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      OasisToast.error(context, 'Could not open maps on this phone.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();
    final booking = controller.bookings.firstWhere(
      (candidate) => candidate.id == widget.booking.id,
      orElse: () => widget.booking,
    );
    final listing = v2ListingFor(controller, booking);
    final isHost = widget.isHost;
    final actions = widget.actionsFor?.call(booking) ?? const [];

    final address = booking.address.isNotEmpty
        ? booking.address
        : listing?.address ?? '';
    final location = listing?.location.isNotEmpty == true
        ? listing!.location
        : address;
    final place = booking.propertyName.isNotEmpty
        ? booking.propertyName
        : listing?.title ?? 'Shortlet';
    final statusLabel = isHost
        ? booking.status.landlordLabel
        : booking.status.label;
    final photos = <String>{
      if (listing?.coverPhotoUrl?.trim().isNotEmpty == true)
        listing!.coverPhotoUrl!.trim(),
      ...?listing?.photoUrls
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty),
    }.toList();

    final tiles = <_QuickAction>[
      if (address.isNotEmpty)
        _QuickAction(
          icon: Icons.near_me_outlined,
          label: 'Directions',
          onTap: () => _openDirections(address),
        ),
      if (booking.canMessage)
        _QuickAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: isHost ? 'Message guest' : 'Message host',
          onTap: () => v2OpenBookingConversation(context, booking.id),
        ),
    ];
    final payWindow = v2PayWindow(booking);
    final topInset = MediaQuery.paddingOf(context).top;

    return V2StatusBar(
      overPhoto: !_pastPhoto,
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: ListView(
          controller: _scrollController,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 12,
          ),
          children: [
            SizedBox(
              height: topInset + _photoHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photos.length > 1)
                    PageView.builder(
                      itemCount: photos.length,
                      onPageChanged: (index) =>
                          setState(() => _photoIndex = index),
                      itemBuilder: (context, index) =>
                          V2StayPhoto(url: photos[index]),
                    )
                  else
                    V2StayPhoto(
                      url: photos.isEmpty ? null : photos.first,
                      listingKnown: listing != null,
                    ),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.black.withValues(alpha: 0.38),
                            Colors.black.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: topInset + 8,
                    left: 16,
                    child: V2CircleButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPhoto: true,
                      size: 40,
                      onTap: () => Navigator.maybePop(context),
                    ),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      right: 16,
                      bottom: 36,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_photoIndex + 1}/${photos.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                decoration: BoxDecoration(
                  color: AppTheme.pageBackground(context),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            place,
                            style: AppTheme.screenTitle(
                              context,
                            ).copyWith(fontSize: 24, letterSpacing: -0.8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: V2StatusPill(
                            label: statusLabel,
                            tone: v2ToneFor(booking.status),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (location.isNotEmpty) ...[
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyText(context),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        Text(
                          'Booking #${_shortId(booking.id)}',
                          style: AppTheme.bodyText(
                            context,
                            color: AppTheme.mutedTextColor(context),
                          ).copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                    if (tiles.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          for (var i = 0; i < tiles.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(child: _QuickActionTile(action: tiles[i])),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor(context),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppTheme.borderColor(context),
                        ),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: _DateBlock(
                                label: 'Check-in',
                                date: booking.checkInDate,
                                raw: booking.checkIn,
                                time: _checkInTime,
                              ),
                            ),
                            VerticalDivider(
                              width: 24,
                              color: AppTheme.borderColor(context),
                            ),
                            Expanded(
                              child: _DateBlock(
                                label: 'Check-out',
                                date: booking.checkOutDate,
                                raw: booking.checkOut,
                                time: _checkOutTime,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _Fact(
                            icon: Icons.people_outline_rounded,
                            label: 'Guests',
                            value: v2Plural(
                              booking.guestCount,
                              'guest',
                              'guests',
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: _Fact(
                            icon: Icons.nightlight_outlined,
                            label: 'Nights',
                            value: booking.nights > 0
                                ? v2Plural(booking.nights, 'night', 'nights')
                                : '—',
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: _Fact(
                            icon: Icons.credit_card_outlined,
                            label: isHost
                                ? 'Payout'
                                : booking.status.isPaid
                                ? 'Total paid'
                                : 'Total',
                            value: OasisCurrency.format(
                              isHost ? booking.hostPayout : booking.totalAmount,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isHost &&
                        booking.cautionFeeStage != CautionFeeStage.none) ...[
                      const SizedBox(height: 16),
                      GuestCautionFeeStatus(
                        booking: booking,
                        onRespond: widget.onRespondToClaim == null
                            ? null
                            : () => widget.onRespondToClaim!(booking),
                      ),
                    ],
                    if (payWindow != null) ...[
                      const SizedBox(height: 14),
                      V2IconText(
                        icon: Icons.timer_outlined,
                        text: payWindow,
                        color: AppTheme.isDarkMode(context)
                            ? AppTheme.sandColor
                            : const Color(0xFF85602F),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Divider(height: 1, color: AppTheme.borderColor(context)),
                    if (listing != null || address.isNotEmpty)
                      _InfoRow(
                        icon: Icons.home_work_outlined,
                        title: 'Property details',
                        subtitle: 'Address, rooms, house rules',
                        onTap: () => _showSheet(context, 'Property details', [
                          if (address.isNotEmpty)
                            _DetailRow(label: 'Address', value: address),
                          if (listing != null && listing.bedrooms > 0)
                            _DetailRow(
                              label: 'Bedrooms',
                              value: '${listing.bedrooms}',
                            ),
                          if (listing != null && listing.bathrooms > 0)
                            _DetailRow(
                              label: 'Bathrooms',
                              value: '${listing.bathrooms}',
                            ),
                          if (listing != null && listing.houseRules.isNotEmpty)
                            _DetailRow(
                              label: 'House rules',
                              value: listing.houseRules,
                            ),
                        ]),
                      ),
                    if (booking.status.isPaid &&
                        booking.checkInNotes.isNotEmpty)
                      _InfoRow(
                        icon: Icons.key_outlined,
                        title: 'Check-in instructions',
                        subtitle: 'How to get into the property',
                        onTap: () =>
                            _showSheet(context, 'Check-in instructions', [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  booking.checkInNotes,
                                  style: AppTheme.bodyText(
                                    context,
                                    color: AppTheme.readingTextColor(context),
                                  ).copyWith(fontSize: 14),
                                ),
                              ),
                            ]),
                      ),
                    _InfoRow(
                      icon: Icons.event_busy_outlined,
                      title: 'Cancellation policy',
                      subtitle: booking.cancellationPolicy.label,
                      onTap: () => _showSheet(context, 'Cancellation policy', [
                        _DetailRow(
                          label: booking.cancellationPolicy.label,
                          value:
                              listing?.resolvedCancellationPolicySummary ??
                              booking.cancellationPolicy.defaultSummary,
                        ),
                        if (booking.hasRefundQuote)
                          _DetailRow(
                            label: 'If you cancel now',
                            value:
                                '${OasisCurrency.format(booking.totalRefundAmount)} '
                                'back',
                          ),
                      ]),
                    ),
                    _InfoRow(
                      icon: isHost
                          ? Icons.account_balance_outlined
                          : Icons.receipt_long_outlined,
                      title: isHost ? 'Payout details' : 'Payment details',
                      subtitle: 'See the breakdown',
                      showDivider: false,
                      onTap: () => _showSheet(
                        context,
                        isHost ? 'Payout details' : 'Payment details',
                        [
                          if (!isHost && booking.amount.isNotEmpty)
                            _DetailRow(
                              label: 'Accommodation',
                              value: OasisCurrency.format(booking.amount),
                            ),
                          if (booking.hasCautionFee)
                            _DetailRow(
                              label: booking.isCautionFeeRefunded
                                  ? 'Caution fee returned'
                                  : 'Refundable caution fee',
                              value: OasisCurrency.format(booking.cautionFee),
                            ),
                          _DetailRow(
                            label: isHost
                                ? 'Payout'
                                : booking.status.needsPayment
                                ? 'Total due'
                                : booking.status.isPaid
                                ? 'Total paid'
                                : 'Booking total',
                            value: OasisCurrency.format(
                              isHost ? booking.hostPayout : booking.totalAmount,
                            ),
                            emphasize: true,
                          ),
                          _DetailRow(
                            label: isHost ? 'Payout status' : 'Payment status',
                            value: isHost
                                ? booking.resolvedHostPayoutLabel
                                : booking.status.isPaid
                                ? 'Payment confirmed'
                                : statusLabel,
                          ),
                          if (booking.paymentReference?.isNotEmpty ?? false)
                            _DetailRow(
                              label: 'Reference',
                              value: booking.paymentReference!,
                            ),
                        ],
                      ),
                    ),
                    if (actions.isNotEmpty) const SizedBox(height: 16),
                    for (final action in actions) ...[
                      if (action.isPrimary)
                        OasisButton(
                          label: action.label,
                          icon: action.icon,
                          isBusy: action.isBusy,
                          onPressed: action.onTapIfEnabled,
                        )
                      else if (action.isDestructive)
                        V2DestructiveButton(
                          label: action.label,
                          isBusy: action.isBusy,
                          onTap: action.onTapIfEnabled,
                        )
                      else
                        V2SoftButton(
                          label: action.label,
                          icon: action.icon,
                          onTap: action.onTapIfEnabled,
                        ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The first block of an ID is enough to quote to support; a full UUID is
  /// not something anyone reads.
  static String _shortId(String id) {
    final head = id
        .split('-')
        .firstWhere((part) => part.length >= 4, orElse: () => id);
    final short = head.length > 8 ? head.substring(0, 8) : head;
    return short.toUpperCase();
  }

  void _showSheet(BuildContext context, String title, List<Widget> rows) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor(sheetContext),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusLg),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            MediaQuery.paddingOf(sheetContext).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.mutedTextColor(
                      sheetContext,
                    ).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: AppTheme.sectionTitle(sheetContext)),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;

  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: action.onTap,
    child: Container(
      height: 76,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            action.icon,
            size: 22,
            color: AppTheme.primaryTextColor(context),
          ),
          const SizedBox(height: 8),
          Text(
            action.label,
            style: AppTheme.bodyText(context).copyWith(
              color: AppTheme.primaryTextColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _DateBlock extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String raw;
  final String time;

  const _DateBlock({
    required this.label,
    required this.date,
    required this.raw,
    required this.time,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTheme.bodyText(context).copyWith(fontSize: 12)),
      const SizedBox(height: 4),
      Text(
        date == null
            ? (raw.isEmpty ? '—' : raw)
            : DateFormat('EEE, d MMM yyyy').format(date!),
        style: AppTheme.cardTitle(
          context,
        ).copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 2),
      Text(
        time,
        style: AppTheme.bodyText(
          context,
          color: AppTheme.primaryTextColor(context),
        ).copyWith(fontSize: 13),
      ),
    ],
  );
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Fact({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: AppTheme.secondaryTextColor(context)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTheme.bodyText(context).copyWith(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.cardTitle(
                context,
              ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.borderColor(context)),
              ),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.primaryTextColor(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.cardTitle(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.mutedTextColor(context),
          ),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTheme.borderColor(context))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTheme.bodyText(context).copyWith(fontSize: 13),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: emphasize
                ? AppTheme.cardTitle(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700)
                : AppTheme.bodyText(
                    context,
                    color: AppTheme.primaryTextColor(context),
                  ).copyWith(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
