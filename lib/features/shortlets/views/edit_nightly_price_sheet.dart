import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_models.dart';
import '../../../core/utils/oasis_input_formatters.dart';

/// Changes what a stay costs a night, and nothing else.
///
/// Returns true when something was saved.
///
/// A stay's price is already editable through [openCreateShortLetSheet], but
/// that sheet asks nine questions, because it is the sheet for *creating* a
/// listing. A host dropping their price by ₦5,000 to fill a quiet Tuesday is
/// not revisiting their cancellation policy, their house rules or their
/// booking window, and making them scroll past all three to reach one number
/// is how a price stops being adjusted at all.
///
/// So: two doors on the same room. This one, for the number that actually
/// moves, and the full sheet for everything else.
///
/// Everything not asked for here is carried through from [listing] unchanged.
/// The edit is a `PATCH` of the whole listing rather than of one field, so a
/// key left out of the body is a house rule deleted and a calendar wiped:
/// see `ShortLetService.saveListing`.
Future<bool> openEditNightlyPriceSheet(
  BuildContext context, {
  required ShortLetListing listing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditNightlyPriceSheet(listing: listing),
  );
  return saved ?? false;
}

class _EditNightlyPriceSheet extends StatefulWidget {
  final ShortLetListing listing;

  const _EditNightlyPriceSheet({required this.listing});

  @override
  State<_EditNightlyPriceSheet> createState() => _EditNightlyPriceSheetState();
}

class _EditNightlyPriceSheetState extends State<_EditNightlyPriceSheet> {
  final _priceController = TextEditingController();

  /// The refundable deposit. Editable alongside the nightly rate because the
  /// two are one decision to a guest comparing places: a ₦40,000 night with a
  /// ₦100,000 deposit is not cheaper than a ₦55,000 night without one, and a
  /// host cutting their rate to compete usually needs to look at both.
  final _cautionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _priceController.text = OasisThousandsFormatter.groupAmount(
      widget.listing.nightlyPrice,
    );
    if (widget.listing.hasCautionFee) {
      _cautionController.text = OasisThousandsFormatter.groupAmount(
        widget.listing.cautionFee,
      );
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _cautionController.dispose();
    super.dispose();
  }

  String get _rawPrice =>
      _priceController.text.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _hasPrice => _rawPrice.replaceAll(RegExp(r'^0+'), '').isNotEmpty;

  String get _rawCaution =>
      _cautionController.text.replaceAll(RegExp(r'[^0-9]'), '');

  /// A field left blank, and one filled with zeroes, both mean "no deposit".
  bool get _hasCaution => _rawCaution.replaceAll(RegExp(r'^0+'), '').isNotEmpty;

  String get _nightlyPrice => '$_rawPrice.00';
  String get _cautionFee => _hasCaution ? '$_rawCaution.00' : '0.00';

  /// True when neither number has moved. Saving then would spend a request to
  /// report a change that did not happen.
  bool get _isUnchanged =>
      OasisCurrency.minorUnits(_nightlyPrice) ==
          OasisCurrency.minorUnits(widget.listing.nightlyPrice) &&
      OasisCurrency.minorUnits(_cautionFee) ==
          OasisCurrency.minorUnits(widget.listing.cautionFee);

  Future<void> _save() async {
    if (!_hasPrice) {
      OasisToast.error(context, 'Set a nightly price.');
      return;
    }

    final listing = widget.listing;
    final controller = context.read<ShortLetController>();
    final saved = await controller.saveListing(
      unitId: listing.unitId,
      // Always an edit: this sheet only ever opens on a listing that exists.
      listingId: listing.id,
      nightlyPrice: _nightlyPrice,
      cautionFee: _cautionFee,
      // Everything below is the listing as it already stands. Sent rather
      // than omitted because the save endpoint replaces the listing: a key
      // left out is a house rule deleted, a calendar wiped, a policy reset.
      minimumNights: listing.minimumNights,
      maximumGuests: listing.maximumGuests,
      description: listing.description,
      cancellationPolicy: listing.cancellationPolicy,
      availableFrom: listing.availableFrom,
      availableTo: listing.availableTo,
      blockedDates: listing.blockedDates,
      houseRules: listing.houseRules,
      checkInNotes: listing.checkInNotes,
      isActive: listing.isActive,
    );
    if (!mounted) return;

    if (saved == null) {
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not change that price. Try again in a moment.',
      );
      return;
    }

    Navigator.pop(context, true);
    OasisToast.success(
      context,
      'Now ${OasisCurrency.format(_nightlyPrice)} a night.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();
    final listing = widget.listing;

    return OasisSheet(
      icon: Icons.sell_outlined,
      title: 'Change the price',
      subtitle:
          '${listing.title} is listed at '
          '${OasisCurrency.format(listing.nightlyPrice)} a night. Guests '
          'browsing stays see the new price straight away.',
      footer: OasisSheetButton(
        label: 'Save new price',
        icon: Icons.check_rounded,
        isLoading: controller.isSubmitting,
        onPressed: !_hasPrice || _isUnchanged || controller.isSubmitting
            ? null
            : _save,
      ),
      children: [
        const OasisFieldLabel('Price per night'),
        TextField(
          controller: _priceController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: const [OasisThousandsFormatter()],
          onChanged: (_) => setState(() {}),
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: '50000',
            prefixIcon: Icons.payments_outlined,
            suffix: Padding(
              padding: const EdgeInsets.only(right: 16, left: 8),
              child: Text('₦ / night', style: AppTheme.labelText(context)),
            ),
          ),
        ),
        const SizedBox(height: 18),

        OasisFieldLabel(
          'Caution fee',
          trailing: Text(
            _hasCaution ? 'Refundable' : 'None',
            style: AppTheme.labelText(
              context,
              color: _hasCaution
                  ? AppTheme.vacantColor
                  : AppTheme.mutedTextColor(context),
            ),
          ),
        ),
        TextField(
          controller: _cautionController,
          keyboardType: TextInputType.number,
          inputFormatters: const [OasisThousandsFormatter()],
          onChanged: (_) => setState(() {}),
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'Leave blank for none',
            prefixIcon: Icons.shield_outlined,
          ),
        ),
        const SizedBox(height: 16),

        // What a guest will actually be asked for, in one number. A nightly
        // rate plus a deposit is the figure that decides a booking, and a
        // host adjusting one of them should see the other move with it.
        if (_hasPrice)
          _QuoteLine(
            nightlyPrice: _nightlyPrice,
            cautionFee: _cautionFee,
            minimumNights: listing.minimumNights,
          ),

        const SizedBox(height: 12),
        Text(
          'Stays already booked or paid for keep the price they were agreed '
          'at. This only changes what new guests are quoted.',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
      ],
    );
  }
}

/// "3 nights = ₦150,000, plus a ₦50,000 refundable deposit."
class _QuoteLine extends StatelessWidget {
  final String nightlyPrice;
  final String cautionFee;
  final int minimumNights;

  const _QuoteLine({
    required this.nightlyPrice,
    required this.cautionFee,
    required this.minimumNights,
  });

  @override
  Widget build(BuildContext context) {
    final stay = OasisCurrency.scale(nightlyPrice, minimumNights);
    final hasDeposit = (OasisCurrency.minorUnits(cautionFee) ?? 0) > 0;
    final nights = minimumNights == 1 ? 'night' : 'nights';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 18,
            color: AppTheme.secondaryTextColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A $minimumNights-$nights stay comes to '
              '${OasisCurrency.format(stay)}'
              '${hasDeposit ? ', plus ${OasisCurrency.format(cautionFee)} '
                        'refundable' : ''}.',
              style: AppTheme.bodyText(context),
            ),
          ),
        ],
      ),
    );
  }
}
