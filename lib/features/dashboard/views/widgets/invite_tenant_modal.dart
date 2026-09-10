import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/oasis_currency.dart';
import '../../../../core/widgets/oasis_sheet.dart';
import '../../../../core/widgets/oasis_toast.dart';
import '../../../agreements/controllers/agreement_controller.dart';
import '../../../agreements/models/agreement_model.dart';
import '../../../agreements/views/widgets/rent_plan_picker.dart';
import '../../../properties/controllers/landlord_controller.dart';
import '../../../properties/models/property_model.dart';
import '../../../../core/utils/oasis_input_formatters.dart';

class InviteTenantModal extends StatefulWidget {
  const InviteTenantModal({super.key});

  @override
  State<InviteTenantModal> createState() => _InviteTenantModalState();
}

class _InviteTenantModalState extends State<InviteTenantModal> {
  PropertyModel? _selectedProperty;
  UnitModel? _selectedUnit;
  final _emailPhoneController = TextEditingController();
  final _rentController = TextEditingController(text: '450000.00');
  final _rulesController = TextEditingController(
    text: 'No noise after 10 PM. Rent due annually.',
  );

  /// Matches the backend's own default, so leaving the picker alone sends the
  /// tenancy everyone expects.
  RentPlan _rentPlan = RentPlan.fallback;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailPhoneController.dispose();
    _rentController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  void _submitInvite() async {
    final contact = _emailPhoneController.text.trim();
    if (contact.isEmpty) {
      OasisToast.error(context, 'Please enter tenant email or phone number.');
      return;
    }

    if (_selectedProperty == null || _selectedUnit == null) {
      OasisToast.error(context, 'Please select a property and unit.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final startDate = DateTime.now().toIso8601String().split('T').first;
      final endDate = DateTime.now()
          .add(const Duration(days: 365))
          .toIso8601String()
          .split('T')
          .first;

      final agreementController = context.read<AgreementController>();
      final agreement = await agreementController.createAgreement(
        unitId: _selectedUnit!.id,
        tenantId: contact,
        rentAmount: OasisThousandsFormatter.digitsOf(_rentController.text),
        startDate: startDate,
        endDate: endDate,
        rules: _rulesController.text.trim(),
        rentPlan: _rentPlan,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (agreement != null) {
        Navigator.pop(context);
        OasisToast.success(
          context,
          'Invitation & Tenancy Agreement sent to $contact!',
        );
      } else {
        final errorMsg =
            agreementController.errorMessage ??
            'Could not create invitation. Please check details.';
        OasisToast.error(context, errorMsg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      OasisToast.error(context, 'Error inviting tenant: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final landlordCtrl = context.watch<LandlordController>();
    final properties = landlordCtrl.properties;
    final bool isSelectionValid =
        _selectedProperty != null && _selectedUnit != null;
    final units = _selectedProperty == null
        ? const <UnitModel>[]
        : landlordCtrl.propertyUnits[_selectedProperty!.id] ?? const [];

    return OasisSheet(
      icon: Icons.person_add_alt_1_rounded,
      title: 'Invite tenant',
      subtitle: 'Send an invitation link and tenancy bridge agreement.',
      footer: OasisSheetButton(
        label: 'Send tenant invitation',
        icon: Icons.send_rounded,
        isLoading: _isSubmitting,
        onPressed: isSelectionValid ? _submitInvite : null,
      ),
      children: [
        const OasisFieldLabel('Select property'),
        DropdownButtonFormField<PropertyModel>(
          initialValue: _selectedProperty,
          isExpanded: true,
          borderRadius: AppTheme.cornerMd,
          icon: Icon(
            Icons.expand_more_rounded,
            color: AppTheme.mutedTextColor(context),
          ),
          hint: Text(
            'Choose property',
            style: AppTheme.bodyText(
              context,
              color: AppTheme.mutedTextColor(context),
            ),
          ),
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            prefixIcon: Icons.apartment_rounded,
          ),
          items: properties.map((p) {
            return DropdownMenuItem(
              value: p,
              child: Text(p.name, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (val) {
            setState(() {
              _selectedProperty = val;
              _selectedUnit = null;
            });
          },
        ),
        const SizedBox(height: 18),

        if (_selectedProperty != null) ...[
          const OasisFieldLabel('Select unit'),
          if (units.isEmpty)
            _NoticeBanner(
              icon: Icons.info_outline_rounded,
              message: 'No units created for this property yet.',
            )
          else
            DropdownButtonFormField<UnitModel>(
              initialValue: _selectedUnit,
              isExpanded: true,
              borderRadius: AppTheme.cornerMd,
              icon: Icon(
                Icons.expand_more_rounded,
                color: AppTheme.mutedTextColor(context),
              ),
              hint: Text(
                'Choose unit',
                style: AppTheme.bodyText(
                  context,
                  color: AppTheme.mutedTextColor(context),
                ),
              ),
              style: AppTheme.cardTitle(context),
              decoration: oasisInputDecoration(
                context,
                prefixIcon: Icons.meeting_room_outlined,
              ),
              items: units.map((u) {
                return DropdownMenuItem(
                  value: u,
                  child: Text(
                    'Unit ${u.unitNumber} · ${OasisCurrency.format(u.rentAmount)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedUnit = val;
                  if (val != null && val.rentAmount.isNotEmpty) {
                    _rentController.text = OasisThousandsFormatter.groupAmount(
                      val.rentAmount,
                    );
                  }
                });
              },
            ),
          const SizedBox(height: 18),
        ],

        const OasisFieldLabel('Tenant email or phone'),
        TextField(
          controller: _emailPhoneController,
          keyboardType: TextInputType.emailAddress,
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'tenant@example.com or +234 801 234 5678',
            prefixIcon: Icons.alternate_email_rounded,
          ),
        ),
        const SizedBox(height: 18),

        const OasisFieldLabel('Agreed rent amount'),
        TextField(
          controller: _rentController,
          keyboardType: TextInputType.number,
          inputFormatters: const [OasisThousandsFormatter()],
          style: AppTheme.cardTitle(context),
          onChanged: (_) => setState(() {}),
          decoration: oasisInputDecoration(
            context,
            hint: '450,000',
            prefixIcon: Icons.payments_outlined,
            suffix: Padding(
              padding: const EdgeInsets.only(right: 16, left: 8),
              child: Text('₦ / year', style: AppTheme.labelText(context)),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Placed under the amount because it reads as a qualifier on it: the
        // figure above is what the tenant owes for the year, and this is how
        // they will be asked for it.
        const OasisFieldLabel('How often rent is due'),
        RentPlanPicker(
          selected: _rentPlan,
          annualRent: OasisThousandsFormatter.digitsOf(_rentController.text),
          onChanged: (plan) => setState(() => _rentPlan = plan),
        ),
        const SizedBox(height: 20),

        _InviteSummary(
          property: _selectedProperty,
          unit: _selectedUnit,
          rent: OasisThousandsFormatter.digitsOf(_rentController.text),
          plan: _rentPlan,
        ),
      ],
    );
  }
}

/// Restates what the landlord is about to send, so the invitation is never
/// fired off from four disconnected fields.
class _InviteSummary extends StatelessWidget {
  final PropertyModel? property;
  final UnitModel? unit;
  final String rent;
  final RentPlan plan;

  const _InviteSummary({
    required this.property,
    required this.unit,
    required this.rent,
    required this.plan,
  });

  @override
  Widget build(BuildContext context) {
    final ready = property != null && unit != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ready
            ? AppTheme.actionColor.withValues(alpha: 0.06)
            : AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(
          color: ready
              ? AppTheme.actionColor.withValues(alpha: 0.2)
              : AppTheme.borderColor(context),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.description_outlined : Icons.pending_outlined,
            size: 19,
            color: ready
                ? AppTheme.actionColor
                : AppTheme.mutedTextColor(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ready
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${property!.name} · Unit ${unit!.unitNumber}',
                        style: AppTheme.cardTitle(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${OasisCurrency.format(rent)} per year, '
                        '${plan.label.toLowerCase()} · 12-month bridge '
                        'agreement starting today.',
                        style: AppTheme.bodyText(context),
                      ),
                    ],
                  )
                : Text(
                    'Pick a property and unit to generate the tenancy agreement.',
                    style: AppTheme.bodyText(context),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final IconData icon;
  final String message;

  const _NoticeBanner({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppTheme.vacantSurface(
        context,
      ).withValues(alpha: AppTheme.isDarkMode(context) ? 0.14 : 1),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.sandColor.withValues(alpha: 0.5)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.sandColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: AppTheme.bodyText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        ),
      ],
    ),
  );
}
