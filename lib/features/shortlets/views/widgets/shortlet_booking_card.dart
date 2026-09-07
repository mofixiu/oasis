import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/landa_currency.dart';
import '../../models/shortlet_models.dart';

/// One booking, from either side of it.
///
/// The same card serves the guest and the host because it is the same booking:
/// the dates, the price and the standing do not change depending on who is
/// looking. Only the wording and the buttons do, which is what [isLandlord]
/// and [actions] are for.
class ShortLetBookingCard extends StatelessWidget {
  final ShortLetBooking booking;
  final bool isLandlord;

  /// Whatever this viewer can do about this booking right now. Passed in
  /// rather than decided here so the card stays a presentation of state and
  /// the screens keep ownership of what happens next.
  final List<Widget> actions;

  const ShortLetBookingCard({
    super.key,
    required this.booking,
    this.isLandlord = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tone = _tone(booking.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(
          color:
              booking.status.needsPayment ||
                  booking.status.needsLandlordDecision
              ? tone.withValues(alpha: 0.35)
              : AppTheme.borderColor(context),
        ),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.title,
                  style: AppTheme.cardTitle(context),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                LandaCurrency.format(booking.totalAmount),
                style: AppTheme.cardTitle(context, color: AppTheme.actionColor),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _StatusPill(
            label: isLandlord
                ? booking.status.landlordLabel
                : booking.status.label,
            tone: tone,
          ),
          const SizedBox(height: 10),

          // A booking the app cannot interpret has no buttons under it:
          // paying, cancelling and disputing are all gated on a status this
          // is not. That silence used to be the entire user experience of the
          // state: a pill reading "Processing" and nothing to do about it.
          //
          // So it explains itself, names the word the server actually used,
          // and points at the one route that still works. Support can act on
          // "it says PAYMENT_FAILED"; nobody can act on "it says Processing".
          if (booking.status == ShortLetBookingStatus.unknown) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.subtleSurfaceColor(context),
                borderRadius: AppTheme.cornerMd,
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    size: 15,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      booking.rawStatusLabel.isEmpty
                          ? 'This booking came back without a status, so the '
                                'app cannot say where it has got to. Pull '
                                'down to refresh. If it stays like this, '
                                'contact support with the dates above.'
                          : 'The server calls this booking '
                                '"${booking.rawStatusLabel}", which this '
                                'version of the app does not recognise. Pull '
                                'down to refresh. If it stays like this, '
                                'quote that word to support.',
                      style: AppTheme.labelText(
                        context,
                        color: AppTheme.secondaryTextColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // The booking-status pill above says where the *stay* has got to.
          // This says where the *money* has got to, and the two are
          // deliberately never the same line: "Paid" used to also mean "and
          // the host already has it", which stopped being true the day
          // payout release moved from the moment of payment to check-in.
          // Host-only: a guest has no payout of their own to watch.
          if (isLandlord && booking.status.isPaid) ...[
            _HostPayoutBanner(booking: booking),
            const SizedBox(height: 10),
          ],

          _Line(icon: Icons.calendar_month_outlined, text: _dateRange(booking)),
          const SizedBox(height: 4),
          _Line(
            icon: Icons.group_outlined,
            text:
                '${booking.guestCount} '
                '${booking.guestCount == 1 ? 'guest' : 'guests'}'
                '${isLandlord ? ' · ${booking.guestLabel}' : ''}',
          ),

          // The total at the top is one number covering two different things.
          // Broken out here so a guest can see what they are actually
          // spending, and a host can see what they are only holding.
          if (booking.hasCautionFee) ...[
            const SizedBox(height: 4),
            _Line(
              icon: Icons.shield_outlined,
              text: booking.isCautionFeeRefunded
                  ? '${LandaCurrency.format(booking.cautionFee)} caution fee '
                        'returned'
                  : 'Includes ${LandaCurrency.format(booking.cautionFee)} '
                        'refundable caution fee '
                        '(${LandaCurrency.format(booking.amountExcludingCautionFee)} '
                        'for the stay)',
              tone: booking.isCautionFeeRefunded
                  ? AppTheme.successColor
                  : AppTheme.vacantColor,
            ),
          ],

          const SizedBox(height: 4),
          _Line(
            icon: Icons.policy_outlined,
            text: '${booking.cancellationPolicy.label} cancellation',
          ),

          // This comes from the backend at its current clock and includes
          // every component of the charge. The app never derives a refund
          // from the policy string or dates itself.
          if (booking.hasRefundQuote) ...[
            const SizedBox(height: 4),
            _Line(
              icon: Icons.currency_exchange_outlined,
              text:
                  'Cancel now: ${LandaCurrency.format(booking.totalRefundAmount)} '
                  'refund',
              tone: AppTheme.successColor,
            ),
          ],

          // A guest's own note back to them is noise; a host reading a request
          // wants it, because it is the only thing the guest said.
          if (isLandlord && booking.message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.subtleSurfaceColor(context),
                borderRadius: AppTheme.cornerMd,
              ),
              child: Text(booking.message, style: AppTheme.bodyText(context)),
            ),
          ],

          // The 24-hour window is the whole reason an approved booking is
          // urgent, so it is stated rather than left for the guest to discover
          // when the booking quietly expires.
          if (_payWindow(booking) case final window?) ...[
            const SizedBox(height: 10),
            _Line(
              icon: Icons.timer_outlined,
              text: window,
              tone: AppTheme.warningColor,
            ),
          ],

          // What the dispute is about, on both sides of it: the guest needs to
          // see what they sent, and the host needs to know what to fix.
          if (booking.status == ShortLetBookingStatus.disputed) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.disputeColor.withValues(alpha: 0.08),
                borderRadius: AppTheme.cornerMd,
                border: Border.all(
                  color: AppTheme.disputeColor.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.gavel_outlined,
                    size: 15,
                    color: AppTheme.disputeColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      booking.disputeReason.isEmpty
                          ? (isLandlord
                                ? 'The guest reported a problem. Your payout '
                                      'stays paused until it is settled.'
                                : 'This stay is being looked into. The host '
                                      'payout stays held until it is '
                                      'settled.')
                          : booking.disputeReason,
                      style: AppTheme.bodyText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Released by the backend only once the stay is paid for, so its
          // presence is the signal that it is worth showing at all.
          if (!isLandlord &&
              booking.status.isPaid &&
              booking.checkInNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.08),
                borderRadius: AppTheme.cornerMd,
                border: Border.all(
                  color: AppTheme.successColor.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.vpn_key_outlined,
                    size: 15,
                    color: AppTheme.successColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      booking.checkInNotes,
                      style: AppTheme.bodyText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (actions.isNotEmpty) ...[const SizedBox(height: 14), ...actions],
        ],
      ),
    );
  }

  /// "1–3 Oct 2026 · 2 nights", falling back to the raw dates when either is
  /// unparseable rather than rendering an empty range.
  static String _dateRange(ShortLetBooking booking) {
    final start = booking.checkInDate;
    final end = booking.checkOutDate;
    final nights = booking.nights;
    final nightsLabel = nights > 0
        ? ' · $nights ${nights == 1 ? 'night' : 'nights'}'
        : '';

    if (start == null || end == null) {
      return '${booking.checkIn} → ${booking.checkOut}$nightsLabel';
    }
    // Drop the repeated month and year on a stay that does not cross either.
    final sameMonth = start.year == end.year && start.month == end.month;
    final from = DateFormat(sameMonth ? 'd' : 'd MMM').format(start);
    final to = DateFormat('d MMM yyyy').format(end);
    return '$from – $to$nightsLabel';
  }

  /// How long is left to pay, or null when that is not the situation.
  static String? _payWindow(ShortLetBooking booking) {
    final left = booking.timeLeftToPay;
    if (left == null) return null;
    if (left == Duration.zero) {
      return 'The payment window has closed.';
    }
    if (left.inHours >= 1) {
      final hours = left.inHours;
      return 'Pay within $hours ${hours == 1 ? 'hour' : 'hours'} to confirm '
          'this stay.';
    }
    final minutes = left.inMinutes < 1 ? 1 : left.inMinutes;
    return 'Pay within $minutes ${minutes == 1 ? 'minute' : 'minutes'} to '
        'confirm this stay.';
  }

  static Color _tone(ShortLetBookingStatus status) {
    switch (status) {
      case ShortLetBookingStatus.paid:
      case ShortLetBookingStatus.checkedIn:
      case ShortLetBookingStatus.checkedOut:
      case ShortLetBookingStatus.completed:
        return AppTheme.successColor;
      case ShortLetBookingStatus.approved:
      case ShortLetBookingStatus.pending:
        return AppTheme.warningColor;
      case ShortLetBookingStatus.disputed:
      case ShortLetBookingStatus.rejected:
      case ShortLetBookingStatus.expired:
        return AppTheme.disputeColor;
      case ShortLetBookingStatus.cancelled:
      case ShortLetBookingStatus.unknown:
        return AppTheme.profileColor;
    }
  }
}

/// Where the host's money stands: a separate line from the booking-status
/// pill above it, on purpose.
///
/// Backend copy is preferred throughout (`resolvedHostPayoutLabel` /
/// `resolvedHostPayoutDescription`): it is written for exactly this banner,
/// and a locally-guessed sentence would drift from it the first time the
/// backend's own wording changes.
class _HostPayoutBanner extends StatelessWidget {
  final ShortLetBooking booking;

  const _HostPayoutBanner({required this.booking});

  @override
  Widget build(BuildContext context) {
    final status = booking.hostPayoutStatus;
    final tone = switch (status) {
      HostPayoutStatus.released => AppTheme.successColor,
      HostPayoutStatus.blocked => AppTheme.disputeColor,
      HostPayoutStatus.refunded => AppTheme.mutedTextColor(context),
      HostPayoutStatus.held ||
      HostPayoutStatus.notFunded ||
      HostPayoutStatus.unknown => AppTheme.vacantColor,
    };
    final icon = switch (status) {
      HostPayoutStatus.released => Icons.check_circle_outline_rounded,
      HostPayoutStatus.blocked => Icons.pause_circle_outlined,
      HostPayoutStatus.refunded => Icons.undo_rounded,
      HostPayoutStatus.held ||
      HostPayoutStatus.notFunded ||
      HostPayoutStatus.unknown => Icons.schedule_outlined,
    };
    final releaseAt = DateTime.tryParse(booking.hostPayoutReleaseAt ?? '');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${LandaCurrency.format(booking.hostPayout)} · ',
                      style: AppTheme.labelText(
                        context,
                        color: tone,
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(
                        booking.resolvedHostPayoutLabel,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.labelText(context, color: tone),
                      ),
                    ),
                  ],
                ),
                if (booking.resolvedHostPayoutDescription.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    booking.resolvedHostPayoutDescription,
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ),
                  ),
                ] else if (status == HostPayoutStatus.held &&
                    releaseAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Releases ${DateFormat('d MMM, h:mm a').format(releaseAt)}, '
                    'unless a problem is reported first.',
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color tone;

  const _StatusPill({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.12),
      borderRadius: AppTheme.cornerSm,
      border: Border.all(color: tone.withValues(alpha: 0.3)),
    ),
    child: Text(label, style: AppTheme.labelText(context, color: tone)),
  );
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? tone;

  const _Line({required this.icon, required this.text, this.tone});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: tone ?? AppTheme.mutedTextColor(context)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: AppTheme.labelText(
            context,
            color: tone ?? AppTheme.secondaryTextColor(context),
          ),
        ),
      ),
    ],
  );
}
