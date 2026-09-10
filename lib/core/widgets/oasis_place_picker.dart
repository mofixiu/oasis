import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/oasis_haptics.dart';
import '../utils/nigeria_locations.dart';
import 'oasis_pressable.dart';
import 'oasis_sheet.dart';

/// Picks a Nigerian state, or a town inside one, from a searchable sheet.
///
/// Both were free-text boxes. Testers asked for the list, and the reason is
/// not only typing: the marketplace matches a tenant's filter against the
/// landlord's string, so "Lagos state" and "lagos" are two different places
/// as far as search is concerned, and a listing typed one way is invisible to
/// a tenant who typed the other. A shared list is what makes the two agree.
///
/// The sheet never *refuses* an answer. Nigeria has 774 LGAs and this list
/// carries the towns people put on addresses, so [allowCustom] leaves a way
/// to enter one that is missing rather than making an omission a wall.
Future<String?> openPlacePicker(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<String> options,
  String? selected,
  IconData icon = Icons.location_city_rounded,
  String searchHint = 'Search',

  /// Offers "Use what I typed" for a query with no match in [options].
  bool allowCustom = true,

  /// Shown instead of the list when there is nothing to pick from — a city
  /// list with no state chosen yet.
  String? emptyMessage,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) {
    // Measured inside the builder, so the sheet grows when the keyboard
    // pushes the search field up rather than being fixed at open time.
    final height = MediaQuery.sizeOf(sheetContext).height;
    final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: keyboard > 0 ? height * 0.92 : height * 0.72,
      ),
      child: _PlacePickerSheet(
        title: title,
        subtitle: subtitle,
        options: options,
        selected: selected,
        icon: icon,
        searchHint: searchHint,
        allowCustom: allowCustom,
        emptyMessage: emptyMessage,
      ),
    );
  },
);

/// Picks a state, canonicalised to the spelling the rest of the app uses.
Future<String?> openStatePicker(BuildContext context, {String? selected}) =>
    openPlacePicker(
      context,
      title: 'Which state?',
      subtitle: 'Pick the state the property is in.',
      options: NigeriaLocations.states,
      selected: NigeriaLocations.canonicalState(selected) ?? selected,
      icon: Icons.map_outlined,
      searchHint: 'Search states',
      // A state that is not one of the 37 does not exist, so there is nothing
      // to let somebody through with.
      allowCustom: false,
    );

/// Picks a town inside [state]. Falls back to free text when the state is not
/// one we hold a list for, or when the town is simply not in it.
Future<String?> openCityPicker(
  BuildContext context, {
  required String? state,
  String? selected,
}) {
  final cities = NigeriaLocations.citiesIn(state);
  final stateName = NigeriaLocations.canonicalState(state);
  return openPlacePicker(
    context,
    title: 'Which city or area?',
    subtitle: stateName == null
        ? 'Type the town, area or LGA the property is in.'
        : 'Pick the area in $stateName, or type one that is not listed.',
    options: cities,
    selected: selected,
    icon: Icons.location_city_rounded,
    searchHint: 'Search or type an area',
    emptyMessage: state == null || state.trim().isEmpty
        ? 'Choose the state first and the areas in it will be listed here.'
        : null,
  );
}

class _PlacePickerSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> options;
  final String? selected;
  final IconData icon;
  final String searchHint;
  final bool allowCustom;
  final String? emptyMessage;

  const _PlacePickerSheet({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.icon,
    required this.searchHint,
    required this.allowCustom,
    required this.emptyMessage,
  });

  @override
  State<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<_PlacePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Matches on a substring rather than a prefix: somebody looking for
  /// "Victoria Island" types "island", and somebody looking for Port
  /// Harcourt's suburbs types "harcourt".
  List<String> get _matches {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return widget.options;
    return widget.options
        .where((option) => option.toLowerCase().contains(needle))
        .toList();
  }

  /// Whether what was typed is worth offering as an answer of its own.
  ///
  /// Only when it matches nothing: an exact hit is already the first row, and
  /// offering "Use Ikeja" underneath a tappable "Ikeja" is two ways to do the
  /// same thing.
  bool get _canUseTyped {
    if (!widget.allowCustom) return false;
    final typed = _query.trim();
    if (typed.length < 2) return false;
    return !widget.options.any(
      (option) => option.toLowerCase() == typed.toLowerCase(),
    );
  }

  void _choose(String value) {
    OasisHaptics.select();
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return OasisSheet(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      children: [
        TextField(
          controller: _searchController,
          autofocus: false,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => setState(() => _query = value),
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: widget.searchHint,
            prefixIcon: Icons.search_rounded,
          ),
        ),
        const SizedBox(height: 14),

        if (_canUseTyped) ...[
          _PlaceRow(
            label: 'Use "${_query.trim()}"',
            isSelected: false,
            leading: Icons.edit_location_alt_outlined,
            onTap: () => _choose(_query.trim()),
          ),
          const SizedBox(height: 8),
        ],

        if (matches.isEmpty && !_canUseTyped)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              widget.emptyMessage ??
                  'Nothing matches "${_query.trim()}". Check the spelling, or '
                      'type the area in full.',
              style: AppTheme.bodyText(context),
              textAlign: TextAlign.center,
            ),
          ),

        for (final option in matches) ...[
          _PlaceRow(
            label: option,
            isSelected:
                option.toLowerCase() == widget.selected?.toLowerCase().trim(),
            onTap: () => _choose(option),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// One tappable row. Selected state is a tick and a tinted border rather than
/// a filled block: the list can be forty rows long and forty tinted blocks is
/// a wall.
class _PlaceRow extends StatelessWidget {
  final String label;
  final bool isSelected;
  final IconData? leading;
  final VoidCallback onTap;

  const _PlaceRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.actionColor.withValues(alpha: 0.08)
            : AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(
          color: isSelected
              ? AppTheme.actionColor.withValues(alpha: 0.4)
              : AppTheme.borderColor(context),
        ),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            Icon(leading, size: 18, color: AppTheme.actionColor),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: AppTheme.cardTitle(
                context,
                color: isSelected ? AppTheme.actionColor : null,
              ),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_circle_rounded,
              size: 19,
              color: AppTheme.actionColor,
            ),
        ],
      ),
    ),
  );
}

/// A field-shaped button that opens a picker instead of a keyboard.
///
/// Looks like the text fields beside it on purpose: a form where one box
/// takes typing and the next opens a sheet, with nothing to tell them apart,
/// is a form people tap twice and give up on. The chevron is the tell.
class OasisPickerField extends StatelessWidget {
  final String? value;
  final String hint;
  final IconData? prefixIcon;
  final VoidCallback? onTap;

  const OasisPickerField({
    super.key,
    required this.value,
    required this.hint,
    this.prefixIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;
    return OasisPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: EdgeInsets.fromLTRB(prefixIcon == null ? 16 : 14, 16, 12, 16),
        decoration: BoxDecoration(
          color: AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            if (prefixIcon != null) ...[
              Icon(
                prefixIcon,
                size: 19,
                color: AppTheme.mutedTextColor(context),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                hasValue ? value!.trim() : hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hasValue
                    ? AppTheme.cardTitle(context)
                    : AppTheme.bodyText(
                        context,
                        color: AppTheme.mutedTextColor(context),
                      ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: AppTheme.mutedTextColor(context),
            ),
          ],
        ),
      ),
    );
  }
}
