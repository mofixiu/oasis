import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../messaging/views/widgets/message_action_button.dart';
import '../../reviews/models/review_models.dart';
import '../../reviews/views/leave_review_sheet.dart';
import '../../vault/controllers/vault_controller.dart';
import '../../vault/views/vault_pin_sheet.dart';
import '../../vault/views/widgets/vault_balance_card.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_models.dart';
import 'widgets/shortlet_booking_card.dart';

/// The guest's side of short lets: what they have asked for, what the host has
/// said, and what still needs paying.
///
/// Payment lives here rather than on the listing because it only becomes
/// possible after approval: by which point the guest is no longer browsing.
class MyShortLetBookingsScreen extends StatefulWidget {
  const MyShortLetBookingsScreen({super.key});

  @override
  State<MyShortLetBookingsScreen> createState() =>
      _MyShortLetBookingsScreenState();
}

class _MyShortLetBookingsScreenState extends State<MyShortLetBookingsScreen>
    with WidgetsBindingObserver, AutoRefreshMixin<MyShortLetBookingsScreen> {
  /// The booking whose provider checkout is open. Held so returning to the app
  /// verifies the right payment and nothing else.
  String? _awaitingCheckoutFor;

  /// Polls while open. This is the screen a guest sits on waiting for the host
  /// to say yes, and the answer arrives on someone else's phone: without
  /// this, an approved booking with a 24-hour payment window only appears when
  /// the guest thinks to drag the list down.
  @override
  Duration? get autoRefreshInterval => kLandaPollInterval;

  @override
  Future<void> onAutoRefresh() => _reload();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the checkout browser is the app's cue to ask the
    // backend what happened. Closing a browser is not proof money moved, so
    // the answer always comes from the verify endpoint.
    if (state == AppLifecycleState.resumed && _awaitingCheckoutFor != null) {
      _verifyAfterCheckout();
    }
  }

  Future<void> _reload() {
    final controller = context.read<ShortLetController>();
    return Future.wait([
      controller.loadMyBookings(),
      // The vault balance decides whether paying from it is even offered.
      context.read<VaultController>().loadVault(),
    ]);
  }

  Future<void> _verifyAfterCheckout() async {
    _awaitingCheckoutFor = null;
    final controller = context.read<ShortLetController>();
    final verified = await controller.verifyPendingPayment();
    if (!mounted) return;

    if (verified == null) {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'We could not confirm that payment yet. Pull down to check again.',
      );
      return;
    }
    if (verified.status.isPaid) {
      LandaToast.success(context, 'Paid. Your stay is confirmed.');
      await _reload();
    } else {
      LandaToast.error(
        context,
        'That payment has not gone through yet. You can try again.',
      );
    }
  }

  /// Offers the two ways to pay, then does the one chosen.
  Future<void> _pay(ShortLetBooking booking) async {
    final vault = context.read<VaultController>();
    final controller = context.read<ShortLetController>();
    final canUseVault = vault.canCover(booking.totalAmount);

    final fromVault = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayWithSheet(
        booking: booking,
        vaultBalance: vault.availableBalance,
        canUseVault: canUseVault,
      ),
    );
    if (fromVault == null || !mounted) return;

    // A new deliberate payment is never merged with a previous attempt.
    controller.beginPaymentIntent(booking.id);

    if (fromVault) {
      await _payFromVault(booking);
    } else {
      await _payWithCard(booking);
    }
  }

  Future<void> _payFromVault(ShortLetBooking booking) async {
    // The PIN is asked for here and lives only as long as this one call.
    final pin = await promptVaultPin(
      context,
      title: 'Confirm ${LandaCurrency.format(booking.totalAmount)}',
      subtitle: 'Enter your vault PIN to pay for this stay.',
      actionLabel: 'Pay ${LandaCurrency.format(booking.totalAmount)}',
    );
    if (!mounted || pin == null) return;

    final controller = context.read<ShortLetController>();
    final paid = await controller.payForBooking(
      booking.id,
      fromVault: true,
      vaultPin: pin,
    );
    if (!mounted) return;

    if (paid == null) {
      if (controller.vaultBalanceFellShort) {
        await _offerShortfallTopUp(booking, controller.vaultShortfall);
        return;
      }
      // A rejected PIN may have just locked the vault, which changes what the
      // guest should do next, so it outranks the raw rejection.
      final vault = context.read<VaultController>();
      await vault.refreshPinStatusAfterFailedAttempt();
      if (!mounted) return;
      LandaToast.error(
        context,
        vault.describeFailedAttempt(controller.errorMessage),
      );
      return;
    }

    LandaToast.success(context, 'Paid. Your stay is confirmed.');
    await _reload();
  }

  Future<void> _payWithCard(ShortLetBooking booking) async {
    final controller = context.read<ShortLetController>();
    final started = await controller.payForBooking(
      booking.id,
      fromVault: false,
    );
    if (!mounted) return;

    if (started == null) {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not start that payment. Try again in a moment.',
      );
      return;
    }

    final url = started.authorizationUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (!started.hasCheckout || uri == null) {
      LandaToast.error(
        context,
        'The payment page could not be opened. Try again in a moment.',
      );
      return;
    }

    // Keep checkout inside the app, as the rent flow does.
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.inAppWebView,
      webViewConfiguration: const WebViewConfiguration(
        enableJavaScript: true,
        enableDomStorage: true,
      ),
    );
    if (!mounted) return;

    if (!opened) {
      LandaToast.error(context, 'Could not open the payment page.');
      return;
    }
    // Verification happens on resume, not here: the page being open says
    // nothing about whether it was paid.
    _awaitingCheckoutFor = booking.id;
  }

  Future<void> _offerShortfallTopUp(
    ShortLetBooking booking,
    String? quotedShortfall,
  ) async {
    final vault = context.read<VaultController>();
    final shortfall =
        quotedShortfall ??
        LandaCurrency.subtract(booking.totalAmount, vault.availableBalance) ??
        booking.totalAmount;

    LandaToast.error(
      context,
      'Your vault is ${LandaCurrency.format(shortfall)} short of this stay. '
      'Nothing has been charged.',
    );

    final funded = await openTopUpSheet(
      context,
      targetAmount: shortfall,
      targetLabel: 'your stay',
    );
    if (funded && mounted) await _reload();
  }

  /// Raises a problem with a stay that has already been paid for.
  ///
  /// Separate from cancelling, and worded so: cancelling withdraws a request
  /// nobody has paid for, while this holds money that has already moved.
  Future<void> _dispute(ShortLetBooking booking) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          'Report a problem',
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your refundable caution fee stays held while this is looked '
              'into. The stay payout is handled separately.',
              style: AppTheme.bodyText(dialogContext),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLines: 3,
              autofocus: true,
              style: AppTheme.bodyText(dialogContext),
              decoration: InputDecoration(
                hintText: 'The place was not accessible when I arrived.',
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
            child: const Text('Never mind'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonController.text.trim()),
            child: Text(
              'Report it',
              style: AppTheme.cardTitle(
                dialogContext,
                color: AppTheme.disputeColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;

    final controller = context.read<ShortLetController>();
    final raised = await controller.disputeBooking(
      booking,
      reason: reason.isEmpty ? null : reason,
    );
    if (!mounted) return;

    if (raised) {
      LandaToast.success(
        context,
        'Reported. The host payout stays paused until this is settled.',
      );
      await _reload();
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not report that just now. Try again in a moment.',
      );
    }
  }

  /// Marks a dispute settled, so the paused host payout can release.
  Future<void> _resolveDispute(ShortLetBooking booking) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          'Mark this resolved?',
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This tells the host their payout can release. Only do this '
              'once the problem is actually sorted.',
              style: AppTheme.bodyText(dialogContext),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteController,
              maxLines: 2,
              style: AppTheme.bodyText(dialogContext),
              decoration: InputDecoration(
                hintText: 'Note for the record (optional)',
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
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Mark resolved'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<ShortLetController>();
    final resolved = await controller.resolveDispute(
      booking,
      note: noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim(),
    );
    if (!mounted) return;

    if (resolved) {
      LandaToast.success(context, 'Marked resolved. Thanks for confirming.');
      await refreshNow();
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not mark that resolved. Try again in a moment.',
      );
    }
  }

  Future<void> _cancel(ShortLetBooking booking) async {
    // Paid, pre-check-in cancellation now has a real refund to quote:
    // fetched here, right before the confirmation, so the numbers in the
    // dialog are current rather than whatever the list happened to load
    // with. Quiet on failure: the dialog still works from its fallback
    // wording, and the cancel call itself carries the backend's final word
    // regardless of whether this lookup succeeded.
    var target = booking;
    if (booking.status == ShortLetBookingStatus.paid) {
      final previewed = await context
          .read<ShortLetController>()
          .previewCancellation(booking.id);
      if (!mounted) return;
      if (previewed != null) target = previewed;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          target.status.isPaid ? 'Cancel this stay?' : 'Cancel this request?',
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Text(
          target.status.isPaid
              ? (target.hasRefundQuote
                    ? 'The host will be told you are no longer coming. Landa '
                          'will return ${LandaCurrency.format(target.totalRefundAmount)} '
                          'under this booking’s cancellation terms.'
                    : 'The host will be told you are no longer coming. Landa '
                          'will confirm the refund under this booking’s '
                          'cancellation terms before completing cancellation.')
              : 'The host will be told you are no longer coming. You have not '
                    'been charged.',
          style: AppTheme.bodyText(dialogContext),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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
    if (confirmed != true || !mounted) return;

    final controller = context.read<ShortLetController>();
    final cancelled = await controller.cancelBooking(booking.id);
    if (!mounted) return;

    if (cancelled) {
      LandaToast.success(context, 'Booking cancelled.');
      await refreshNow();
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not cancel that booking. Try again in a moment.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(showBackButton: true),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _buildBody(context, controller),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ShortLetController controller) {
    final live = controller.liveBookings;
    final closed = controller.closedBookings;

    // Skeleton until the fetch has actually answered, not merely until it is
    // no longer running. Before the first load both are false and empty, and
    // the old check fell through to "No stays yet", which is what a guest
    // with three booked stays saw for a beat every time they opened this.
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
        icon: Icons.luggage_outlined,
        title: 'No stays yet',
        message:
            'Places you ask to stay in show up here, along with what the host '
            'said and anything still to pay.',
        actionLabel: 'Find a place',
        actionIcon: Icons.search_rounded,
        onAction: () => Navigator.pop(context),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Text(
          'My stays',
          style: AppTheme.screenTitle(context, color: AppTheme.primaryColor),
        ),
        const SizedBox(height: 16),

        for (var index = 0; index < live.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: LandaEntrance(
              index: index,
              child: ShortLetBookingCard(
                booking: live[index],
                actions: _actionsFor(live[index], controller),
              ),
            ),
          ),

        if (closed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'PAST AND CANCELLED',
            style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
          ),
          const SizedBox(height: 10),
          for (final booking in closed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ShortLetBookingCard(booking: booking),
            ),
        ],
      ],
    );
  }

  List<Widget> _actionsFor(
    ShortLetBooking booking,
    ShortLetController controller,
  ) {
    final busy = controller.isSubmitting;

    return [
      if (booking.status.needsPayment)
        LandaButton(
          label: 'Pay ${LandaCurrency.format(booking.totalAmount)}',
          icon: Icons.lock_outline_rounded,
          isBusy: busy,
          onPressed: busy ? null : () => _pay(booking),
        ),
      if (booking.canBeCancelledByTenant) ...[
        if (booking.status.needsPayment) const SizedBox(height: 8),
        LandaButton(
          label: 'Cancel booking',
          icon: Icons.close_rounded,
          outlined: true,
          color: AppTheme.disputeColor,
          // The preview lookup uses this same spinner: a booking is either
          // being decided on or being quoted for cancellation, never both.
          isBusy: controller.isPreviewingCancellation(booking.id),
          onPressed: busy ? null : () => _cancel(booking),
        ),
      ],
      // Opens the moment the stay is paid for. This is where the practical
      // half of a short let actually happens: the key, the gate code, the
      // arrival time, and before it existed those were being written into a
      // booking request nobody read again.
      if (booking.canMessage) ...[
        const SizedBox(height: 8),
        MessageActionButton(
          shortLetBookingId: booking.id,
          label: 'Message the host',
          expanded: true,
        ),
      ],

      // Only after checkout, and only once. Asked for here rather than in a
      // notification, because this is the screen the guest is already on when
      // they think about the stay again.
      if (booking.canReview) ...[
        const SizedBox(height: 8),
        LandaButton(
          label: 'Rate this stay',
          icon: Icons.star_outline_rounded,
          outlined: true,
          onPressed: busy ? null : () => _review(booking),
        ),
      ],

      // Only on a stay that is paid for and not already under review. The
      // money is released to the host a day after checkout, so this is the
      // window in which raising a problem still holds it.
      if (booking.canDispute) ...[
        const SizedBox(height: 8),
        LandaButton(
          label: 'Report a problem',
          icon: Icons.gavel_outlined,
          outlined: true,
          color: AppTheme.disputeColor,
          onPressed: busy ? null : () => _dispute(booking),
        ),
      ],

      // Only while a dispute is actually open. Marking it resolved is what
      // lets the host payout release: immediately, if the normal release
      // time has already passed while this was being looked into.
      if (booking.status == ShortLetBookingStatus.disputed) ...[
        const SizedBox(height: 8),
        LandaButton(
          label: 'Mark issue resolved',
          icon: Icons.check_circle_outline_rounded,
          outlined: true,
          onPressed: busy ? null : () => _resolveDispute(booking),
        ),
      ],
    ];
  }

  /// Rates a stay the guest has been on.
  ///
  /// The listing is the subject and the booking is the proof: the backend
  /// checks this guest actually stayed there before it takes the review,
  /// which is what keeps the ratings on the browse list worth reading.
  Future<void> _review(ShortLetBooking booking) async {
    final posted = await openLeaveReviewSheet(
      context,
      subject: ReviewSubject.shortLet,
      subjectId: booking.listingId,
      transactionId: booking.id,
      subjectName: booking.title,
    );
    if (posted && mounted) await refreshNow();
  }
}

/// Card or vault, with the vault offered only when it actually covers the bill.
class _PayWithSheet extends StatelessWidget {
  final ShortLetBooking booking;
  final String vaultBalance;
  final bool canUseVault;

  const _PayWithSheet({
    required this.booking,
    required this.vaultBalance,
    required this.canUseVault,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.of(context).padding.bottom + 20,
    ),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.mutedTextColor(context).withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Pay ${LandaCurrency.format(booking.totalAmount)}',
          style: AppTheme.sectionTitle(context),
        ),
        const SizedBox(height: 4),
        Text(
          'The refundable caution fee is held until checkout.',
          style: AppTheme.bodyText(context),
        ),
        const SizedBox(height: 20),

        _PayOption(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Pay from vault',
          // Naming the balance is what makes the disabled state make sense.
          subtitle: canUseVault
              ? '${LandaCurrency.format(vaultBalance)} available · settles instantly'
              : 'Only ${LandaCurrency.format(vaultBalance)} available',
          enabled: canUseVault,
          onTap: () => Navigator.pop(context, true),
        ),
        const SizedBox(height: 10),
        _PayOption(
          icon: Icons.credit_card_outlined,
          title: 'Pay with card',
          subtitle: 'Opens secure checkout',
          enabled: true,
          onTap: () => Navigator.pop(context, false),
        ),
      ],
    ),
  );
}

class _PayOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _PayOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? AppTheme.primaryTextColor(context)
        : AppTheme.mutedTextColor(context);

    return LandaPressable(
      onTap: enabled ? onTap : null,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.cardTitle(context, color: foreground),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (enabled)
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.mutedTextColor(context),
              ),
          ],
        ),
      ),
    );
  }
}
