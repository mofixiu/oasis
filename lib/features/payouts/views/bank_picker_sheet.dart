import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/payout_models.dart';

/// Searchable bank picker. Nigerian bank lists run to several hundred
/// entries, so a plain scroll would be unusable: this filters as you type.
///
/// Pops the selected bank name.
class BankPickerSheet extends StatefulWidget {
  final List<BankOption> banks;
  final String? selected;

  const BankPickerSheet({super.key, required this.banks, this.selected});

  @override
  State<BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<BankPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BankOption> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.banks;
    return widget.banks
        .where((bank) => bank.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose your bank',
                      style: AppTheme.sectionTitle(
                        context,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search banks',
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppTheme.mutedTextColor(context),
                  ),
                  filled: true,
                  fillColor: AppTheme.inputFillColor(context),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.borderColor(context),
                    ),
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
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No bank matches "${_query.trim()}".',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 24,
                        color: AppTheme.borderColor(context),
                      ),
                      itemBuilder: (context, index) {
                        final bank = results[index];
                        final isSelected = bank.name == widget.selected;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                          ),
                          title: Text(
                            bank.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppTheme.actionColor
                                  : AppTheme.primaryTextColor(context),
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: AppTheme.actionColor,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, bank.name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
