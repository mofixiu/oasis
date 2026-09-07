import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/landa_currency.dart';
import '../../../../core/widgets/landa_sheet.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../controllers/landlord_controller.dart';
import '../../models/property_model.dart';
import '../../../../core/utils/landa_input_formatters.dart';

/// Changes what a unit costs.
///
/// Returns true when a new rent was saved.
///
/// This is the one field on a unit a landlord genuinely revisits. Everything
/// else (the unit number, the room count, the photos) describes what the
/// flat *is*, and is right or wrong from the day it is typed. The price is a
/// position in a market: a flat sitting empty for two months is usually a
/// flat priced for a market that has moved, and until this existed the only
/// remedy inside Landa was to delete the unit and add it again, which throws
/// away its photos, its walkthrough and its applications.
Future<bool> openEditUnitRentSheet(
  BuildContext context, {
  required UnitModel unit,
  required String propertyId,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditUnitRentSheet(unit: unit, propertyId: propertyId),
  );
  return saved ?? false;
}

class _EditUnitRentSheet extends StatefulWidget {
  final UnitModel unit;
  final String propertyId;

  const _EditUnitRentSheet({required this.unit, required this.propertyId});

  @override
  State<_EditUnitRentSheet> createState() => _EditUnitRentSheetState();
}

class _EditUnitRentSheetState extends State<_EditUnitRentSheet> {
  final _rentController = TextEditingController();

  /// What the typed figure is quoted for. Only ever a year or a month here:
  /// a unit let by the night is priced on its short-let listing, which is a
  /// different screen and a different number.
  RentInterval _interval = RentInterval.perYear;

  @override
  void initState() {
    super.initState();
    // Seeded with the rent as it stands, in whole naira. A landlord changing
    // a price is nearly always nudging one, and starting from an empty field
    // makes them retype a figure they can see on the screen behind.
    _rentController.text = widget.unit.rentAmount.split('.').first;
  }

  @override
  void dispose() {
    _rentController.dispose();
    super.dispose();
  }

  /// The typed figure, digits only.
  String get _raw => _rentController.text.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _hasRent => _raw.replaceAll(RegExp(r'^0+'), '').isNotEmpty;

  /// What will actually be stored: a year's rent, whatever was typed.
  String? get _annualRent =>
      _hasRent ? LandaCurrency.scale(_raw, _interval.periodsPerYear) : null;

  /// Whether the figure on screen is the one already saved. Nothing is sent
  /// for a save that changes nothing: it would spend a request to produce a
  /// success message about no change at all.
  bool get _isUnchanged =>
      LandaCurrency.minorUnits(_annualRent) ==
      LandaCurrency.minorUnits(widget.unit.rentAmount);

  Future<void> _save() async {
    final annual = _annualRent;
    if (annual == null) {
      LandaToast.error(context, 'Enter the new rent.');
      return;
    }

    final controller = context.read<LandlordController>();
    final saved = await controller.updateUnitRent(
      propertyId: widget.propertyId,
      unitId: widget.unit.id,
      rentAmount: annual,
    );
    if (!mounted) return;

    if (!saved) {
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not change that rent. Try again in a moment.',
      );
      return;
    }

    // The navigator is resolved before the pop, so the toast is not looking
    // for an overlay through a context that is on its way out.
    Navigator.pop(context, true);
    LandaToast.success(
      context,
      'Unit ${widget.unit.unitNumber} is now ${LandaCurrency.perYear(annual)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = context.watch<LandlordController>().isSavingUnit;
    final annual = _annualRent;

    return LandaSheet(
      icon: Icons.sell_outlined,
      title: 'Change the rent',
      subtitle:
          'Unit ${widget.unit.unitNumber} is listed at '
          '${LandaCurrency.perYear(widget.unit.rentAmount)}. What you set here '
          'is what tenants browsing the marketplace see.',
      footer: LandaSheetButton(
        label: 'Save new rent',
        icon: Icons.check_rounded,
        isLoading: isSaving,
        onPressed: !_hasRent || _isUnchanged || isSaving ? null : _save,
      ),
      children: [
        const LandaFieldLabel('New rent'),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: _rentController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: const [LandaThousandsFormatter()],
                onChanged: (_) => setState(() {}),
                style: AppTheme.cardTitle(context),
                decoration: landaInputDecoration(
                  context,
                  hint: 'Rent (₦)',
                  prefixIcon: Icons.payments_outlined,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Beside the amount, not under it, for the same reason the units
            // sheet puts it there: a rent read without its interval is wrong
            // by a factor of twelve.
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<RentInterval>(
                initialValue: _interval,
                isExpanded: true,
                borderRadius: AppTheme.cornerMd,
                style: AppTheme.cardTitle(context),
                decoration: landaInputDecoration(context),
                items: [
                  for (final option in const [
                    RentInterval.perYear,
                    RentInterval.perMonth,
                  ])
                    DropdownMenuItem(
                      value: option,
                      child: Text(
                        option.suffix,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: isSaving
                    ? null
                    : (interval) {
                        if (interval != null) {
                          setState(() => _interval = interval);
                        }
                      },
              ),
            ),
          ],
        ),

        // Landa stores one rent per unit, a year's, so a landlord who typed
        // a monthly figure is shown the multiplication rather than finding it
        // on the listing afterwards.
        if (annual != null && _interval != RentInterval.perYear) ...[
          const SizedBox(height: 8),
          Text(
            'Saved as ${LandaCurrency.perYear(annual)}.',
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        ],

        const SizedBox(height: 16),

        // The one thing a landlord must not misunderstand about this screen.
        // A signed tenancy is a contract at a price both sides agreed; the
        // unit's rent is what the *next* tenant is quoted. Letting somebody
        // believe they had just raised a sitting tenant's rent, or quietly
        // doing it: would be the worst possible outcome of a price field.
        _Notice(
          icon: widget.unit.isOccupied
              ? Icons.gpp_good_outlined
              : Icons.storefront_outlined,
          accent: widget.unit.isOccupied
              ? AppTheme.successColor
              : AppTheme.actionColor,
          message: widget.unit.isOccupied
              ? 'Someone is living here. Their signed agreement keeps the rent '
                    'they agreed to. This only changes what the unit is '
                    'advertised at once it is free again.'
              : 'This takes effect on the listing straight away. Applications '
                    'already sent keep the rent they were made at.',
        ),
      ],
    );
  }
}

/// A tinted line of consequence under the field. Small on purpose: it is a
/// clarification, not a warning, and styling it as an alarm would make an
/// ordinary price change feel dangerous.
class _Notice extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String message;

  const _Notice({
    required this.icon,
    required this.accent,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.07),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: accent.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        ),
      ],
    ),
  );
}
