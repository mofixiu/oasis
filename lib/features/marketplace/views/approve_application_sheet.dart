import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/marketplace_models.dart';

/// Terms the landlord sets when approving an application.
class ApprovalTerms {
  final String startDate;
  final String endDate;
  final String? rules;

  const ApprovalTerms({
    required this.startDate,
    required this.endDate,
    this.rules,
  });
}

/// Collects `start_date`, `end_date`, and `rules` for
/// `POST /landlord/applications/{id}/approve/`, which creates the pending
/// tenancy agreement.
class ApproveApplicationSheet extends StatefulWidget {
  final RentalApplication application;

  const ApproveApplicationSheet({super.key, required this.application});

  @override
  State<ApproveApplicationSheet> createState() =>
      _ApproveApplicationSheetState();
}

class _ApproveApplicationSheetState extends State<ApproveApplicationSheet> {
  // Default to a standard 12-month tenancy starting today.
  late DateTime _startDate = DateTime.now();
  late DateTime _endDate = DateTime(
    DateTime.now().year + 1,
    DateTime.now().month,
    DateTime.now().day,
  ).subtract(const Duration(days: 1));

  final _rulesController = TextEditingController(
    text: 'No illegal activity. Keep shared areas clean.',
  );
  String? _error;

  @override
  void dispose() {
    _rulesController.dispose();
    super.dispose();
  }

  static String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // Keep the range valid rather than letting the backend reject it.
        if (!_endDate.isAfter(_startDate)) {
          _endDate = DateTime(
            picked.year + 1,
            picked.month,
            picked.day,
          ).subtract(const Duration(days: 1));
        }
      } else {
        _endDate = picked;
      }
      _error = null;
    });
  }

  void _submit() {
    if (!_endDate.isAfter(_startDate)) {
      setState(() => _error = 'End date must be after the start date.');
      return;
    }
    Navigator.pop(
      context,
      ApprovalTerms(
        startDate: _format(_startDate),
        endDate: _format(_endDate),
        rules: _rulesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final application = widget.application;

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
                Expanded(
                  child: Text(
                    'Approve application',
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
            const SizedBox(height: 4),
            Text(
              'Approving creates a pending tenancy agreement for '
              '${application.tenantEmail ?? 'this tenant'} on Unit '
              '${application.unitNumber}, marks the unit occupied, and declines '
              'other pending applications for it.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'START DATE',
                    value: _format(_startDate),
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'END DATE',
                    value: _format(_endDate),
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'TENANCY RULES',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: AppTheme.mutedTextColor(context),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _rulesController,
              maxLines: 3,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.inputFillColor(context),
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
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(fontSize: 12, color: AppTheme.disputeColor),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.actionColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Approve & send agreement',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
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
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.inputFillColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 15,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
