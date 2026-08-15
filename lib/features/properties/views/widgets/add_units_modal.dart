import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../controllers/landlord_controller.dart';
import '../../models/property_model.dart';

class AddUnitsModal extends StatefulWidget {
  final PropertyModel property;

  const AddUnitsModal({super.key, required this.property});

  @override
  State<AddUnitsModal> createState() => _AddUnitsModalState();
}

class _AddUnitsModalState extends State<AddUnitsModal> {
  final List<_UnitDraft> _drafts = [_UnitDraft('A1')];
  bool _isSubmitting = false;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _addRow() =>
      setState(() => _drafts.add(_UnitDraft('A${_drafts.length + 1}')));

  Future<void> _submit() async {
    final invalid = _drafts.any(
      (draft) =>
          draft.unitNumber.text.trim().isEmpty ||
          double.tryParse(draft.rent.text.trim()) == null,
    );
    if (invalid) {
      LandaToast.error(
        context,
        'Give every unit a number and valid rent amount.',
      );
      return;
    }
    final numbers = _drafts
        .map((draft) => draft.unitNumber.text.trim().toLowerCase())
        .toList();
    if (numbers.toSet().length != numbers.length) {
      LandaToast.error(context, 'Each unit number must be unique.');
      return;
    }
    setState(() => _isSubmitting = true);
    final created = await context.read<LandlordController>().createUnitsBatch(
      propertyId: widget.property.id,
      units: _drafts
          .map(
            (draft) => {
              'unit_number': draft.unitNumber.text.trim(),
              'bedrooms': int.tryParse(draft.bedrooms.text.trim()) ?? 1,
              'bathrooms': int.tryParse(draft.bathrooms.text.trim()) ?? 1,
              'rent_amount': draft.rent.text.trim(),
            },
          )
          .toList(),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (created == null) {
      LandaToast.error(
        context,
        context.read<LandlordController>().errorMessage ??
            'Could not add units.',
      );
      return;
    }
    Navigator.pop(context);
    LandaToast.success(
      context,
      '${created.length} unit${created.length == 1 ? '' : 's'} added to ${widget.property.name}.',
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      top: 24,
      left: 20,
      right: 20,
      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add units in batch',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  Text(
                    widget.property.name,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Add several apartments at once. All rows are saved together.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _drafts.length,
            itemBuilder: (_, index) => _UnitDraftRow(
              draft: _drafts[index],
              index: index,
              canRemove: _drafts.length > 1,
              onRemove: () => setState(() {
                final draft = _drafts.removeAt(index);
                draft.dispose();
              }),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add),
            label: const Text('Add another unit'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Save ${_drafts.length} unit${_drafts.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}

class _UnitDraft {
  final TextEditingController unitNumber;
  final bedrooms = TextEditingController(text: '1');
  final bathrooms = TextEditingController(text: '1');
  final rent = TextEditingController();
  _UnitDraft(String number) : unitNumber = TextEditingController(text: number);
  void dispose() {
    unitNumber.dispose();
    bedrooms.dispose();
    bathrooms.dispose();
    rent.dispose();
  }
}

class _UnitDraftRow extends StatelessWidget {
  final _UnitDraft draft;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  const _UnitDraftRow({
    required this.draft,
    required this.index,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfff8f9fb),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Text(
              'UNIT ${index + 1}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const Spacer(),
            if (canRemove)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red,
                ),
                iconSize: 20,
              ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: draft.unitNumber,
                decoration: const InputDecoration(
                  labelText: 'Number',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: draft.bedrooms,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Beds',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: draft.bathrooms,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Baths',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: draft.rent,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Annual rent (₦)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
  );
}
