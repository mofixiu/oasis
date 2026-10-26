import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_models.dart';
import '../../../core/app_variant.dart';

/// Asks the host for dates. Returns the booking on success, null otherwise.
Future<ShortLetBooking?> openRequestBookingSheet(
  BuildContext context, {
  required ShortLetListing listing,
  DateTimeRange? initialDates,
}) => showModalBottomSheet<ShortLetBooking>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      _RequestBookingSheet(listing: listing, initialDates: initialDates),
);

class _RequestBookingSheet extends StatefulWidget {
  final ShortLetListing listing;

  /// The dates the tenant searched with, when they came from a dated search.
  /// Seeded rather than left blank so they are not asked to pick the same
  /// stay a second time: including when those dates turned out to be taken,
  /// where the sheet's own check explains it in place.
  final DateTimeRange? initialDates;

  const _RequestBookingSheet({required this.listing, this.initialDates});

  @override
  State<_RequestBookingSheet> createState() => _RequestBookingSheetState();
}

class _RequestBookingSheetState extends State<_RequestBookingSheet> {
  final _messageController = TextEditingController();

  late DateTimeRange? _stay = widget.initialDates;
  late int _guests = 1;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  int get _nights =>
      _stay == null ? 0 : _stay!.end.difference(_stay!.start).inDays;

  /// Everything wrong with the current selection, or null when it is sendable.
  ///
  /// The backend re-checks all of this and its answer is final; this only
  /// stops the app sending a request that is certain to be refused, so a guest
  /// is not left waiting on a rejection the app could see coming.
  String? get _problem {
    final stay = _stay;
    if (stay == null) return 'Pick your check-in and check-out dates.';
    if (_nights < widget.listing.minimumNights) {
      final min = widget.listing.minimumNights;
      return 'This host takes bookings of at least $min '
          '${min == 1 ? 'night' : 'nights'}.';
    }
    if (_guests > widget.listing.maximumGuests) {
      return 'This place sleeps up to ${widget.listing.maximumGuests}.';
    }
    if (!widget.listing.coversStay(stay.start, stay.end)) {
      return 'Some of those nights are not available. Try different dates.';
    }
    // The search already asked the backend about exactly these dates, and it
    // sees blocked dates and rival bookings the listing payload does not.
    // Only trust that answer while the dates are still the searched ones.
    if (widget.listing.isUnavailableForPeriod &&
        stay.start == widget.initialDates?.start &&
        stay.end == widget.initialDates?.end) {
      return widget.listing.unavailableLabel;
    }
    return null;
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Bound the picker by the host's own window where they set one, so
    // unavailable months are not even reachable.
    final windowStart = _parse(widget.listing.availableFrom);
    final windowEnd = _parse(widget.listing.availableTo);
    final first = windowStart != null && windowStart.isAfter(today)
        ? windowStart
        : today;
    final last = windowEnd ?? today.add(const Duration(days: 365));

    if (last.isBefore(first)) {
      OasisToast.error(context, 'This place is not taking bookings right now.');
      return;
    }

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      currentDate: today,
      initialDateRange: _stay,
      helpText: isOasisV2 ? 'Select your dates' : 'Select your stay',
      saveText: 'Done',
    );
    if (picked != null) setState(() => _stay = picked);
  }

  Future<void> _submit() async {
    final problem = _problem;
    if (problem != null) {
      OasisToast.error(context, problem);
      return;
    }

    final controller = context.read<ShortLetController>();
    final booking = await controller.requestBooking(
      listingId: widget.listing.id,
      checkIn: shortLetIsoDate(_stay!.start),
      checkOut: shortLetIsoDate(_stay!.end),
      guestCount: _guests,
      message: _messageController.text,
    );
    if (!mounted) return;

    if (booking == null) {
      // The backend owns availability, clashes and limits, so its sentence is
      // shown as written rather than second-guessed here.
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not send that request. Try again in a moment.',
      );
      return;
    }
    Navigator.pop(context, booking);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();
    final stay = _stay;
    final total = widget.listing.totalFor(_nights);

    return OasisSheet(
      icon: Icons.calendar_month_outlined,
      title: 'Ask for these dates',
      subtitle:
          'The host has to approve before anything is charged. '
          '${widget.listing.title}.',
      footer: OasisSheetButton(
        label: 'Send request',
        icon: Icons.send_rounded,
        isLoading: controller.isSubmitting,
        onPressed: controller.isSubmitting || _problem != null ? null : _submit,
      ),
      children: [
        OasisFieldLabel(isOasisV2 ? 'Your dates' : 'Your stay'),
        _DateField(stay: stay, nights: _nights, onTap: _pickDates),
        const SizedBox(height: 20),

        OasisFieldLabel('Guests (up to ${widget.listing.maximumGuests})'),
        _GuestStepper(
          value: _guests,
          max: widget.listing.maximumGuests,
          onChanged: (value) => setState(() => _guests = value),
        ),
        const SizedBox(height: 20),

        Container(
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
                Icons.policy_outlined,
                size: 16,
                color: AppTheme.actionColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.listing.cancellationPolicy.label} cancellation: '
                  '${widget.listing.resolvedCancellationPolicySummary} '
                  'Oasis confirms the exact refund before a paid cancellation.',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        const OasisFieldLabel('Note to the host (optional)'),
        TextField(
          controller: _messageController,
          maxLines: 3,
          maxLength: 1000,
          style: AppTheme.bodyText(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'Arriving late on Friday, leaving Sunday morning.',
          ),
        ),

        // Only quoted once there is a real stay to quote. The host's platform
        // fee is added by the backend at payment time, so this is the nightly
        // maths and says so.
        if (total != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurfaceColor(context),
              borderRadius: AppTheme.cornerMd,
            ),
            child: Column(
              children: [
                _QuoteRow(
                  label:
                      '${OasisCurrency.format(widget.listing.nightlyPrice)} '
                      '× $_nights ${_nights == 1 ? 'night' : 'nights'}',
                  amount: OasisCurrency.format(total),
                ),
                // The deposit is its own line rather than folded into the
                // total. A guest comparing two places needs to see which part
                // of the number is spent and which part is coming back.
                if (widget.listing.hasCautionFee) ...[
                  const SizedBox(height: 8),
                  _QuoteRow(
                    label: 'Refundable caution fee',
                    amount: OasisCurrency.format(widget.listing.cautionFee),
                    tone: AppTheme.vacantColor,
                  ),
                  const SizedBox(height: 8),
                  Divider(color: AppTheme.borderColor(context), height: 1),
                  const SizedBox(height: 8),
                  _QuoteRow(
                    label: 'To pay when approved',
                    amount: OasisCurrency.format(
                      widget.listing.totalWithDepositFor(_nights) ?? total,
                    ),
                    emphasise: true,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: AppTheme.mutedTextColor(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.listing.hasCautionFee
                            ? 'The caution fee comes back after checkout '
                                  'unless the host reports damage. The exact '
                                  'total, including fees, is confirmed when '
                                  'the host approves.'
                            : 'The exact total, including fees, is confirmed '
                                  'when the host approves.',
                        style: AppTheme.labelText(
                          context,
                          color: AppTheme.secondaryTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // Says what is wrong while it is still fixable, rather than waiting
        // for the send button to be pressed.
        if (_problem case final problem?) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: AppTheme.warningColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  problem,
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.warningColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static DateTime? _parse(String? iso) =>
      iso == null || iso.isEmpty ? null : DateTime.tryParse(iso);
}

class _DateField extends StatelessWidget {
  final DateTimeRange? stay;
  final int nights;
  final VoidCallback onTap;

  const _DateField({
    required this.stay,
    required this.nights,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('d MMM yyyy');

    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.cornerMd,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.date_range_outlined,
              size: 19,
              color: AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: stay == null
                  ? Text(
                      'Choose your dates',
                      style: AppTheme.bodyText(
                        context,
                        color: AppTheme.mutedTextColor(context),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${format.format(stay!.start)} → '
                          '${format.format(stay!.end)}',
                          style: AppTheme.cardTitle(context),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$nights ${nights == 1 ? 'night' : 'nights'}',
                          style: AppTheme.labelText(context),
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
}

class _GuestStepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _GuestStepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.subtleSurfaceColor(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Row(
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          onTap: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Text(
            '$value ${value == 1 ? 'guest' : 'guests'}',
            textAlign: TextAlign.center,
            style: AppTheme.cardTitle(context),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    ),
  );
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: 20),
    color: AppTheme.actionColor,
    disabledColor: AppTheme.mutedTextColor(context),
  );
}

/// One label-and-amount line in the price breakdown.
class _QuoteRow extends StatelessWidget {
  final String label;
  final String amount;
  final Color? tone;
  final bool emphasise;

  const _QuoteRow({
    required this.label,
    required this.amount,
    this.tone,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: emphasise
              ? AppTheme.cardTitle(context)
              : AppTheme.bodyText(context, color: tone),
        ),
      ),
      Text(
        amount,
        style: emphasise
            ? AppTheme.cardTitle(context, color: AppTheme.actionColor)
            : AppTheme.cardTitle(context, color: tone),
      ),
    ],
  );
}
