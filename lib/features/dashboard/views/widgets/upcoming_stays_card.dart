import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/landa_currency.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../shortlets/models/shortlet_models.dart';

/// A paid short-let booking, on the tenant's dashboard.
///
/// Exists because a successful payment used to leave no mark anywhere a
/// tenant would naturally look. Rent, repairs and agreements all surface on
/// this page; a stay they had paid for did not, so the money looked like it
/// had gone nowhere. Confirming a payment somewhere the payer will see it is
/// part of taking the payment.
///
/// Deliberately compact and deliberately not the whole booking: it says the
/// stay is confirmed, when it is, and what it cost. Everything else (the
/// key, the dispute button, the receipt) is one tap away on Stays, where it
/// already lives.
class UpcomingStayCard extends StatelessWidget {
  final ShortLetBooking booking;
  final VoidCallback onTap;

  const UpcomingStayCard({
    super.key,
    required this.booking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnderReview = booking.status == ShortLetBookingStatus.disputed;
    final tone = isUnderReview ? AppTheme.disputeColor : AppTheme.successColor;

    return LandaPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(color: tone.withValues(alpha: 0.3)),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: AppTheme.cornerMd,
              ),
              child: Icon(
                isUnderReview
                    ? Icons.gavel_outlined
                    : Icons.holiday_village_outlined,
                color: tone,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.title,
                    style: AppTheme.cardTitle(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _countdown(booking),
                    style: AppTheme.labelText(context, color: tone),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Says paid, in the amount that was taken. The single
                    // most reassuring thing on this card is the number the
                    // tenant remembers seeing at checkout.
                    '${LandaCurrency.format(booking.totalAmount)} paid'
                    '${booking.hasCautionFee && !booking.isCautionFeeRefunded ? ' · deposit held' : ''}',
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ),
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

  /// "Check in tomorrow · 12–14 Sep", or the plain dates when the check-in is
  /// far enough off that counting days is noise.
  ///
  /// A relative phrase near the date and an absolute one away from it: "in 47
  /// days" is not something anyone plans around, and "today" is the only
  /// thing worth reading on the morning of.
  static String _countdown(ShortLetBooking booking) {
    final dates = _dateRange(booking);
    final start = booking.checkInDate;
    if (start == null) return dates;

    final now = DateTime.now();
    final days = DateTime(
      start.year,
      start.month,
      start.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;

    if (days < 0) return 'Staying now · $dates';
    if (days == 0) return 'Check in today · $dates';
    if (days == 1) return 'Check in tomorrow · $dates';
    if (days <= 14) return 'Check in in $days days · $dates';
    return 'Confirmed · $dates';
  }

  static String _dateRange(ShortLetBooking booking) {
    final start = booking.checkInDate;
    final end = booking.checkOutDate;
    if (start == null || end == null) {
      return '${booking.checkIn} → ${booking.checkOut}';
    }
    final sameMonth = start.year == end.year && start.month == end.month;
    return '${DateFormat(sameMonth ? 'd' : 'd MMM').format(start)}–'
        '${DateFormat('d MMM').format(end)}';
  }
}
