import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/landa_currency.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../models/property_model.dart';
import 'missing_photos_prompt.dart';

/// One property in the landlord's portfolio: where it is, how many units it
/// has, and which of them are let.
///
/// Lifted out of the landlord dashboard when the portfolio moved to a screen
/// of its own. The dashboard now shows a single summary box; this is what the
/// screen behind it is made of.
class PropertyPortfolioCard extends StatelessWidget {
  final PropertyModel property;
  final List<UnitModel> units;

  /// Opens the property's own page.
  final VoidCallback onTap;

  /// Opens the batch add-units sheet.
  final VoidCallback onAddUnits;

  const PropertyPortfolioCard({
    super.key,
    required this.property,
    required this.units,
    required this.onTap,
    required this.onAddUnits,
  });

  @override
  Widget build(BuildContext context) {
    final occupied = units.where((u) => u.isOccupied).length;
    final anyOccupied = occupied > 0;

    return LandaPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(color: AppTheme.borderColor(context)),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.name,
                        style: AppTheme.sectionTitle(
                          context,
                          color: AppTheme.primaryColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${property.address}, ${property.city}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryTextColor(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_home_outlined,
                    color: AppTheme.actionColor,
                  ),
                  onPressed: onAddUnits,
                  tooltip: 'Add units in batch',
                ),
              ],
            ),
            // A listing with no photos is hidden from the marketplace, which
            // the landlord cannot see from their side, so say it here, on the
            // property it applies to, with the fix attached.
            if (property.needsPhotos) MissingPhotosPrompt(property: property),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Units: ${units.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                Text(
                  anyOccupied ? 'Occupied' : 'Vacant',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: anyOccupied
                        ? AppTheme.successColor
                        : AppTheme.vacantColor,
                  ),
                ),
              ],
            ),
            if (units.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: units.map((u) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: u.isOccupied
                          ? AppTheme.successSurface(context)
                          : AppTheme.vacantSurface(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Unit ${u.unitNumber} (${LandaCurrency.format(u.rentAmount)})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: u.isOccupied
                            ? AppTheme.successColor
                            : AppTheme.primaryColor,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
