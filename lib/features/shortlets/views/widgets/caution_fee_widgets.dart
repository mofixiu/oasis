import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/oasis_currency.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../models/shortlet_models.dart';

/// "18h 20m left", "45m left", or "Closing now".
String cautionWindowLabel(Duration left) {
  if (left <= Duration.zero) return 'Closing now';
  final hours = left.inHours;
  final minutes = left.inMinutes.remainder(60);
  if (hours == 0) return '${minutes < 1 ? 1 : minutes}m left';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m left';
}

/// The caution-fee claim window is 24 hours from checkout.
const Duration cautionClaimWindow = Duration(hours: 24);

Color _pendingInk(BuildContext context) =>
    AppTheme.isDarkMode(context) ? AppTheme.sandColor : const Color(0xFF85602F);

Color _alertInk(BuildContext context) => AppTheme.isDarkMode(context)
    ? const Color(0xFFE59A8F)
    : AppTheme.brickRedColor;

/// The host's checkout inspection: the place has been left, the caution fee
/// is still held, and the host has a fixed window to say all is well or
/// report damage. Counts down live.
class CheckoutInspectionPanel extends StatefulWidget {
  final ShortLetBooking booking;
  final bool busy;
  final VoidCallback onAllGood;
  final VoidCallback onReportDamage;

  const CheckoutInspectionPanel({
    super.key,
    required this.booking,
    required this.busy,
    required this.onAllGood,
    required this.onReportDamage,
  });

  @override
  State<CheckoutInspectionPanel> createState() =>
      _CheckoutInspectionPanelState();
}

class _CheckoutInspectionPanelState extends State<CheckoutInspectionPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Minute precision is all the label shows; a faster tick would only
    // rebuild for nothing.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final deadline = booking.cautionClaimDeadline;
    final left = booking.cautionClaimWindowLeft;
    final urgent = left != null && left < const Duration(hours: 3);
    final elapsed = left == null
        ? null
        : 1 - (left.inSeconds / cautionClaimWindow.inSeconds).clamp(0.0, 1.0);
    final ink = urgent ? _alertInk(context) : _pendingInk(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.vacantSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.fact_check_outlined, size: 19, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checkout inspection',
                      style: AppTheme.cardTitle(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.guestLabel} has checked out. Check the place, '
                      'then refund the '
                      '${OasisCurrency.format(booking.cautionFee)} caution '
                      'fee or report damage.',
                      style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 15, color: ink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  left == null
                      ? 'Within 24 hours of checkout'
                      : cautionWindowLabel(left),
                  style: TextStyle(
                    color: ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (deadline != null)
                Text(
                  'Closes ${DateFormat('EEE h:mm a').format(deadline)}',
                  style: AppTheme.bodyText(context).copyWith(fontSize: 11),
                ),
            ],
          ),
          if (elapsed != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: elapsed,
                minHeight: 6,
                backgroundColor: AppTheme.surfaceColor(context),
                color: ink,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'If you do nothing, the caution fee goes back to the guest when '
            'the time is up.',
            style: AppTheme.bodyText(
              context,
              color: AppTheme.mutedTextColor(context),
            ).copyWith(fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PanelButton(
                  label: 'All good, refund',
                  icon: Icons.check_rounded,
                  filled: true,
                  color: AppTheme.successColor,
                  onTap: widget.busy ? null : widget.onAllGood,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PanelButton(
                  label: 'Report damage',
                  icon: Icons.report_outlined,
                  filled: false,
                  color: _alertInk(context),
                  onTap: widget.busy ? null : widget.onReportDamage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final Color color;
  final VoidCallback? onTap;

  const _PanelButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.55 : 1,
    child: OasisPressable(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: filled ? color : AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(12),
          border: filled
              ? null
              : Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: filled ? Colors.white : color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: filled ? Colors.white : color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// What happened to a claim the host made, on the host's booking card.
class HostCautionClaimStatus extends StatelessWidget {
  final ShortLetBooking booking;
  final CautionClaim claim;

  const HostCautionClaimStatus({
    super.key,
    required this.booking,
    required this.claim,
  });

  @override
  Widget build(BuildContext context) {
    final amount = OasisCurrency.format(claim.claimedAmount);
    final (status, ink) = switch (claim.status) {
      CautionClaimStatus.open => (
        'Waiting for ${booking.guestLabel} to respond.',
        _pendingInk(context),
      ),
      CautionClaimStatus.accepted => (
        'Accepted. $amount is on its way to your vault.',
        AppTheme.successColor,
      ),
      CautionClaimStatus.countered => (
        claim.counterAmount.isEmpty
            ? 'The guest made a counter-offer. Oasis is reviewing it.'
            : 'The guest offered '
                  '${OasisCurrency.format(claim.counterAmount)}. Oasis is '
                  'reviewing it.',
        _pendingInk(context),
      ),
      CautionClaimStatus.rejected => (
        'The guest disagreed. Oasis is reviewing the claim.',
        _pendingInk(context),
      ),
      CautionClaimStatus.resolved => (
        'Settled by Oasis.',
        AppTheme.successColor,
      ),
      CautionClaimStatus.unknown => (
        'Claim sent.',
        AppTheme.secondaryTextColor(context),
      ),
    };

    return _NoticeBox(
      icon: Icons.shield_outlined,
      ink: ink,
      title: 'You claimed $amount of the caution fee',
      lines: [if (claim.reason.isNotEmpty) '“${claim.reason}”', status],
    );
  }
}

/// Where the guest's caution fee stands. A short line in most states; a
/// banner with a Respond button when the host has made a claim.
class GuestCautionFeeStatus extends StatelessWidget {
  final ShortLetBooking booking;
  final VoidCallback? onRespond;

  const GuestCautionFeeStatus({
    super.key,
    required this.booking,
    this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    final fee = OasisCurrency.format(booking.cautionFee);
    final deadline = booking.cautionClaimDeadline;
    final claim = booking.cautionClaim;

    switch (booking.cautionFeeStage) {
      case CautionFeeStage.none:
        return const SizedBox.shrink();
      case CautionFeeStage.held:
        return _StatusLine(
          icon: Icons.shield_outlined,
          ink: AppTheme.secondaryTextColor(context),
          text:
              '$fee caution fee held. It comes back 24 hours after '
              'checkout.',
        );
      case CautionFeeStage.inspection:
        return _StatusLine(
          icon: Icons.fact_check_outlined,
          ink: _pendingInk(context),
          text: deadline == null
              ? 'Your host is checking the place. $fee comes back within 24 '
                    'hours of checkout.'
              : 'Your host is checking the place. $fee comes back by '
                    '${DateFormat('EEE h:mm a').format(deadline)}.',
        );
      case CautionFeeStage.returned:
        return _StatusLine(
          icon: Icons.check_circle_outline_rounded,
          ink: AppTheme.successColor,
          text: '$fee caution fee is back in your vault.',
        );
      case CautionFeeStage.underReview:
        return _StatusLine(
          icon: Icons.gavel_outlined,
          ink: _pendingInk(context),
          text:
              'Oasis is reviewing your caution fee. It stays held until '
              'this is settled.',
        );
      case CautionFeeStage.settled:
        return _StatusLine(
          icon: Icons.check_circle_outline_rounded,
          ink: AppTheme.secondaryTextColor(context),
          text: claim == null
              ? 'Your caution fee has been settled.'
              : 'Caution fee settled: '
                    '${OasisCurrency.format(claim.claimedAmount)} went to the '
                    'host.',
        );
      case CautionFeeStage.claimed:
        final claimed = OasisCurrency.format(claim!.claimedAmount);
        final returned = OasisCurrency.subtract(
          booking.cautionFee,
          claim.claimedAmount,
        );
        final hasReturned = (OasisCurrency.minorUnits(returned) ?? 0) > 0;
        return _NoticeBox(
          icon: Icons.report_outlined,
          ink: _alertInk(context),
          title: 'Your host claimed $claimed of your caution fee',
          lines: [
            if (claim.reason.isNotEmpty) '“${claim.reason}”',
            if (hasReturned)
              'The other ${OasisCurrency.format(returned)} is already back '
                  'in your vault.',
            'Accept it, disagree, or offer a smaller amount.',
          ],
          action: onRespond == null
              ? null
              : _PanelButton(
                  label: 'Respond',
                  icon: Icons.reply_rounded,
                  filled: true,
                  color: AppTheme.terracottaColor,
                  onTap: onRespond,
                ),
        );
    }
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final Color ink;
  final String text;

  const _StatusLine({
    required this.icon,
    required this.ink,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 16, color: ink),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: AppTheme.bodyText(context, color: ink).copyWith(fontSize: 12),
        ),
      ),
    ],
  );
}

class _NoticeBox extends StatelessWidget {
  final IconData icon;
  final Color ink;
  final String title;
  final List<String> lines;
  final Widget? action;

  const _NoticeBox({
    required this.icon,
    required this.ink,
    required this.title,
    required this.lines,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ink.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ink.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.cardTitle(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  for (final line in lines) ...[
                    const SizedBox(height: 3),
                    Text(
                      line,
                      style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}
