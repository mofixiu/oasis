import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/marketplace_models.dart';

/// Collects the `city`, `state`, `min_rent`, `max_rent`, `bedrooms`, and
/// `bathrooms` filters supported by `GET /tenant/marketplace/`.
///
/// Pops a [MarketplaceFilters] on apply, or null when dismissed.
class MarketplaceFilterSheet extends StatefulWidget {
  final MarketplaceFilters initial;

  const MarketplaceFilterSheet({super.key, required this.initial});

  @override
  State<MarketplaceFilterSheet> createState() => _MarketplaceFilterSheetState();
}

class _MarketplaceFilterSheetState extends State<MarketplaceFilterSheet> {
  late final _cityController = TextEditingController(
    text: widget.initial.city ?? '',
  );
  late final _stateController = TextEditingController(
    text: widget.initial.state ?? '',
  );
  late final _minRentController = TextEditingController(
    text: widget.initial.minRent ?? '',
  );
  late final _maxRentController = TextEditingController(
    text: widget.initial.maxRent ?? '',
  );
  late int? _bedrooms = widget.initial.bedrooms;
  late int? _bathrooms = widget.initial.bathrooms;

  @override
  void dispose() {
    _cityController.dispose();
    _stateController.dispose();
    _minRentController.dispose();
    _maxRentController.dispose();
    super.dispose();
  }

  void _apply() {
    Navigator.pop(
      context,
      MarketplaceFilters(
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        minRent: _minRentController.text.trim(),
        maxRent: _maxRentController.text.trim(),
        bedrooms: _bedrooms,
        bathrooms: _bathrooms,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter listings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FilterField(
                    controller: _cityController,
                    label: 'CITY',
                    hint: 'Lagos',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FilterField(
                    controller: _stateController,
                    label: 'STATE',
                    hint: 'Lagos',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _FilterField(
                    controller: _minRentController,
                    label: 'MIN RENT (₦)',
                    hint: '100000',
                    numeric: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FilterField(
                    controller: _maxRentController,
                    label: 'MAX RENT (₦)',
                    hint: '500000',
                    numeric: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _CountSelector(
              label: 'BEDROOMS',
              value: _bedrooms,
              onChanged: (value) => setState(() => _bedrooms = value),
            ),
            const SizedBox(height: 16),
            _CountSelector(
              label: 'BATHROOMS',
              value: _bathrooms,
              onChanged: (value) => setState(() => _bathrooms = value),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.actionColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Show results',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () =>
                    Navigator.pop(context, const MarketplaceFilters()),
                child: const Text('Reset filters'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool numeric;

  const _FilterField({
    required this.controller,
    required this.label,
    required this.hint,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: AppTheme.mutedTextColor(context),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: AppTheme.inputFillColor(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.borderColor(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppTheme.actionColor,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Any / 1 / 2 / 3 / 4+" selector. Null means no filter.
class _CountSelector extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _CountSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const options = <int?>[null, 1, 2, 3, 4];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: AppTheme.mutedTextColor(context),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((option) {
            final selected = value == option;
            return ChoiceChip(
              label: Text(
                option == null ? 'Any' : (option == 4 ? '4+' : '$option'),
              ),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => onChanged(option),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : AppTheme.secondaryTextColor(context),
              ),
              backgroundColor: AppTheme.surfaceColor(context),
              selectedColor: AppTheme.actionColor,
              side: BorderSide(
                color: selected
                    ? AppTheme.actionColor
                    : AppTheme.borderColor(context),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
