import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../agreements/models/agreement_group.dart';
import '../../agreements/models/agreement_model.dart';
import '../../agreements/views/tenancy_agreement_modal.dart';
import '../../payments/controllers/payment_controller.dart';
import '../../payments/models/payment_model.dart';
import '../../payments/views/payment_receipt_modal.dart';

/// Everything about one of the tenant's homes.
///
/// The dashboard card deliberately says almost nothing: the address, the
/// rent, the next date. This is where the rest of it went: the full term, the
/// rules, the landlord, the payments made on this unit, and the agreement
/// itself. Splitting them is what let the dashboard stop being a wall.
class MyUnitScreen extends StatelessWidget {
  final TenancyGroup tenancy;

  const MyUnitScreen({super.key, required this.tenancy});

  @override
  Widget build(BuildContext context) {
    final agreement = tenancy.latest;
    final property = agreement.property;
    final schedule = agreement.upcomingRent;

    // Payments made against this unit, including on a previous term: this is
    // the unit's story, not one document's.
    final agreementIds = tenancy.agreements.map((a) => a.id).toSet();
    final payments = context
        .watch<PaymentController>()
        .payments
        .where((p) => agreementIds.contains(p.agreement))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(showBackButton: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(
            property?.name.isNotEmpty == true ? property!.name : 'Your home',
            style: AppTheme.screenTitle(context, color: AppTheme.primaryColor),
          ),
          if (tenancy.unitNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tenancy.label, style: AppTheme.bodyText(context)),
          ],
          const SizedBox(height: 20),

          _Section(
            title: 'The place',
            rows: [
              if (property?.address.isNotEmpty == true)
                ('Address', property!.address),
              if (property?.city.isNotEmpty == true) ('City', property!.city),
              if (property?.state.isNotEmpty == true)
                ('State', property!.state),
              if (tenancy.unitNumber.isNotEmpty) ('Unit', tenancy.unitNumber),
            ],
          ),
          const SizedBox(height: 16),

          _Section(
            title: 'Your rent',
            rows: [
              ('Rent', LandaCurrency.perYear(agreement.rentAmount)),
              if (agreement.plan != RentPlan.unknown)
                ('Paid', agreement.plan.label),
              if (schedule != null) ('Next due', _nextDue(schedule)),
              if (schedule != null && schedule.instalmentsTotal > 1)
                (
                  'Progress',
                  'Payment ${schedule.instalmentsPaid + 1} of '
                      '${schedule.instalmentsTotal}',
                ),
            ],
          ),
          const SizedBox(height: 16),

          _Section(
            title: 'Your tenancy',
            rows: [
              ('Status', agreement.status.label),
              if (agreement.startDate.isNotEmpty)
                ('Starts', _date(agreement.startDate)),
              if (agreement.endDate.isNotEmpty)
                ('Ends', _date(agreement.endDate)),
              if (agreement.landlordEmail.isNotEmpty)
                ('Landlord', agreement.landlordEmail),
            ],
          ),

          if (agreement.rules.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _Panel(
              title: 'House rules',
              child: Text(
                agreement.rules.trim(),
                style: AppTheme.bodyText(context),
              ),
            ),
          ],

          const SizedBox(height: 16),
          _Panel(
            title: payments.isEmpty ? 'Payments' : 'Payments on this unit',
            child: payments.isEmpty
                ? Text(
                    'Nothing paid on this unit yet. Rent you pay shows up '
                    'here with its receipt.',
                    style: AppTheme.bodyText(context),
                  )
                : Column(
                    children: [
                      for (final payment in payments)
                        _PaymentRow(payment: payment),
                    ],
                  ),
          ),

          // The archive of previous terms on the same unit. Only worth a line
          // when there is one: most tenancies are on their first.
          if (tenancy.hasHistory) ...[
            const SizedBox(height: 16),
            _Panel(
              title: 'Earlier terms',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final past in tenancy.history)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${_date(past.startDate)} – ${_date(past.endDate)} · '
                        '${past.status.label}',
                        style: AppTheme.bodyText(context),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          LandaButton(
            label: 'View agreement',
            icon: Icons.description_outlined,
            outlined: true,
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => ViewAgreementModal(agreement: agreement),
            ),
          ),
        ],
      ),
    );
  }

  static String _nextDue(RentSchedule schedule) {
    final amount = LandaCurrency.format(schedule.nextAmountDue);
    if (schedule.isOverdue) return '$amount · overdue';
    final date = schedule.dueDate;
    if (date == null) return '$amount · due now';
    return '$amount on ${DateFormat('d MMM yyyy').format(date)}';
  }

  /// Renders an ISO date readably, and hands back whatever it was given when
  /// that is not a date: a raw value beats an empty row.
  static String _date(String iso) {
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? iso : DateFormat('d MMM yyyy').format(parsed);
  }
}

/// A titled block of label/value rows.
class _Section extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => _Panel(
    title: title,
    child: Column(
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0)
            Divider(height: 20, color: AppTheme.borderColor(context)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.$1, style: AppTheme.bodyText(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  row.$2,
                  textAlign: TextAlign.right,
                  style: AppTheme.cardTitle(context),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: AppTheme.cornerLg,
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _PaymentRow extends StatelessWidget {
  final PaymentModel payment;

  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: () => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PaymentReceiptModal(payment: payment),
    ),
    pressedScale: 0.995,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LandaCurrency.format(payment.totalAmount),
                  style: AppTheme.cardTitle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  payment.status.label,
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
            size: 18,
            color: AppTheme.mutedTextColor(context),
          ),
        ],
      ),
    ),
  );
}
