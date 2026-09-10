import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/oasis_currency.dart';
import '../../../../core/utils/oasis_haptics.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../models/agreement_model.dart';

/// How often rent falls due, chosen when the landlord writes the agreement.
///
/// Chips rather than a dropdown: there are five options, the choice changes
/// what the tenant will actually be billed, and a collapsed dropdown hides
/// that behind a tap. The annual rent is the same figure either way: the plan
/// only decides how it is split, so the picker says so underneath instead of
/// leaving the landlord to wonder whether the amount above should change.
class RentPlanPicker extends StatelessWidget {
  final RentPlan selected;
  final ValueChanged<RentPlan> onChanged;

  /// The annual rent as typed, so the picker can show what one instalment
  /// comes to. Optional, and ignored when it is not a readable number: the
  /// backend works out the real figure and this is only a preview.
  final String? annualRent;

  const RentPlanPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.annualRent,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final plan in RentPlan.selectable)
            _PlanChip(
              plan: plan,
              isSelected: plan == selected,
              onTap: () {
                OasisHaptics.select();
                onChanged(plan);
              },
            ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.event_repeat_outlined,
            size: 15,
            color: AppTheme.mutedTextColor(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _explain(selected, annualRent),
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  /// What the chosen plan means, with an instalment figure when the rent is
  /// far enough along to give one.
  ///
  /// The estimate is flagged as one: it divides the bare annual rent, while
  /// the tenant's real bill carries the platform fee on top. Presenting it as
  /// exact would have the landlord quoting a number the tenant never sees.
  static String _explain(RentPlan plan, String? annualRent) {
    final instalments = _instalmentsPerYear(plan);
    if (instalments == null || instalments == 1) return plan.description;

    final annual = OasisCurrency.minorUnits(annualRent);
    if (annual == null || annual <= 0) return plan.description;

    final each = OasisCurrency.fromMinorUnits(annual ~/ instalments);
    return '${plan.description}. Around ${OasisCurrency.format(each)} each, '
        'before fees.';
  }

  /// Only for the preview above. The instalment count a tenant actually owes
  /// comes from the backend's `instalments_total`.
  static int? _instalmentsPerYear(RentPlan plan) => switch (plan) {
    RentPlan.annual => 1,
    RentPlan.sixMonthly => 2,
    RentPlan.quarterly => 4,
    RentPlan.monthly => 12,
    RentPlan.weekly => 52,
    RentPlan.unknown => null,
  };
}

class _PlanChip extends StatelessWidget {
  final RentPlan plan;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlanChip({
    required this.plan,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.actionColor
            : AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(
          color: isSelected
              ? AppTheme.actionColor
              : AppTheme.borderColor(context),
        ),
      ),
      child: Text(
        plan.label,
        style: AppTheme.cardTitle(
          context,
          color: isSelected ? Colors.white : AppTheme.primaryTextColor(context),
        ),
      ),
    ),
  );
}
