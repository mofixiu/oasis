import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/landa_currency.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../agreements/models/agreement_group.dart';
import '../../../agreements/models/agreement_model.dart';
import '../my_unit_screen.dart';
import '../../../../core/utils/fade_page_route.dart';

/// One of the tenant's homes, on the dashboard.
///
/// A tenant with two units gets two of these, because the backend's
/// assigned-unit endpoint only ever names the first one and this is built from
/// their agreements instead: one per unit.
///
/// Deliberately large and deliberately sparse: the address, the rent and when
/// it is next due, and nothing else. Everything that used to be crammed
/// alongside it (payment history, the pay button, the agreement text) now
/// lives either on Payments or a tap away on [MyUnitScreen], so the dashboard
/// answers "where do I live and what is coming" at a glance.
class MyUnitCard extends StatelessWidget {
  final TenancyGroup tenancy;

  const MyUnitCard({super.key, required this.tenancy});

  @override
  Widget build(BuildContext context) {
    final agreement = tenancy.latest;
    final schedule = agreement.upcomingRent;
    final property = agreement.property;
    final due = _due(schedule);

    return LandaPressable(
      onTap: () => Navigator.push(
        context,
        FadePageRoute(page: MyUnitScreen(tenancy: tenancy)),
      ),
      pressedScale: 0.99,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(
            color: due == null
                ? AppTheme.borderColor(context)
                : due.tone.withValues(alpha: 0.35),
          ),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    property?.name.isNotEmpty == true
                        ? property!.name
                        : 'Your home',
                    style: AppTheme.sectionTitle(
                      context,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (tenancy.unitNumber.isNotEmpty)
                  _UnitChip(
                    tenancy.label,
                    // Signed but unpaid is not "yours" yet, and the chip is
                    // the first thing read on this card: green there is the
                    // app telling a tenant they have moved in when they have
                    // not paid a naira.
                    isLive: !agreement.awaitingFirstRent,
                  ),
              ],
            ),
            if (_location(agreement) case final location?) ...[
              const SizedBox(height: 4),
              Text(location, style: AppTheme.bodyText(context)),
            ],

            const SizedBox(height: 18),

            // The rent line reads as one sentence: the figure and the cycle
            // together, because "₦300,000" alone has caused people to think
            // it was owed monthly.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RENT',
                        style: AppTheme.labelText(
                          context,
                        ).copyWith(letterSpacing: 0.9),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        LandaCurrency.perYear(agreement.rentAmount),
                        style: AppTheme.sectionTitle(context),
                      ),
                      if (agreement.plan != RentPlan.unknown)
                        Text(
                          'Paid ${agreement.plan.label.toLowerCase()}',
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

            // The tenancy is signed and the first rent has not been paid, so
            // the flat is reserved rather than occupied. Said here, on the
            // card, because this is where a tenant looks to find out where
            // they stand, and "Rent is due today" alone reads as a bill on a
            // home they already have.
            if (agreement.awaitingFirstRent) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: AppTheme.cornerMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_clock_outlined,
                      size: 16,
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your tenancy starts once the first rent is in '
                        'escrow. Pay it from Payments to move in.',
                        style: AppTheme.labelText(
                          context,
                          color: AppTheme.warningColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]
            // Only when there is a date to give. A tenancy with nothing
            // scheduled says nothing rather than inventing reassurance.
            else if (due != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: due.tone.withValues(alpha: 0.1),
                  borderRadius: AppTheme.cornerMd,
                ),
                child: Row(
                  children: [
                    Icon(due.icon, size: 16, color: due.tone),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        due.text,
                        style: AppTheme.labelText(context, color: due.tone),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String? _location(TenancyAgreementModel agreement) {
    final property = agreement.property;
    if (property == null) return null;
    final parts = <String>[
      if (property.address.trim().isNotEmpty) property.address.trim(),
      if (property.city.trim().isNotEmpty) property.city.trim(),
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// When rent lands, and how loudly to say it.
  ///
  /// Three tones on purpose: lateness costs a tenancy, an imminent bill is a
  /// warning, and a date months out is information. Colouring all three alike
  /// trains people to ignore the one that matters.
  static ({String text, Color tone, IconData icon})? _due(
    RentSchedule? schedule,
  ) {
    if (schedule == null) return null;
    final days = schedule.daysUntilDue;

    if (schedule.isOverdue || (days != null && days < 0)) {
      final late = days == null ? null : -days;
      return (
        text: late == null
            ? 'Rent is overdue'
            : 'Rent is $late ${late == 1 ? 'day' : 'days'} overdue',
        tone: AppTheme.disputeColor,
        icon: Icons.event_busy_outlined,
      );
    }
    if (days == 0) {
      return (
        text: 'Rent is due today',
        tone: AppTheme.disputeColor,
        icon: Icons.event_available_outlined,
      );
    }

    final date = schedule.dueDate;
    final amount = LandaCurrency.format(schedule.nextAmountDue);
    if (date == null) {
      return (
        text: '$amount due now',
        tone: AppTheme.actionColor,
        icon: Icons.event_available_outlined,
      );
    }

    final formatted = DateFormat('d MMM yyyy').format(date);
    if (days != null && days <= 30) {
      return (
        text: '$amount due in $days ${days == 1 ? 'day' : 'days'} · $formatted',
        tone: AppTheme.warningColor,
        icon: Icons.event_outlined,
      );
    }
    return (
      text: '$amount due $formatted',
      tone: AppTheme.profileColor,
      icon: Icons.event_outlined,
    );
  }
}

class _UnitChip extends StatelessWidget {
  final String label;

  /// Whether the tenancy is actually running. Sand rather than sage while
  /// the first rent is outstanding: the palette already means "pending" with
  /// that colour everywhere else in the app.
  final bool isLive;

  const _UnitChip(this.label, {this.isLive = true});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: isLive
          ? AppTheme.successSurface(context)
          : AppTheme.vacantSurface(context),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: AppTheme.labelText(
        context,
        color: isLive ? AppTheme.successColor : AppTheme.vacantColor,
      ),
    ),
  );
}
