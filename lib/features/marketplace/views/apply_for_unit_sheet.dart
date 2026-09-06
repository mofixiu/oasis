import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../properties/models/property_model.dart';
import '../models/marketplace_models.dart';

/// What the tenant confirmed when applying.
class ApplyResult {
  /// Optional note to the landlord. Empty means "send without a message".
  final String message;

  const ApplyResult({required this.message});
}

/// Confirms an application and collects the optional message the backend
/// accepts on `POST /tenant/applications/`.
class ApplyForUnitSheet extends StatefulWidget {
  final UnitModel unit;
  final MarketplaceProperty listing;

  const ApplyForUnitSheet({
    super.key,
    required this.unit,
    required this.listing,
  });

  @override
  State<ApplyForUnitSheet> createState() => _ApplyForUnitSheetState();
}

class _ApplyForUnitSheetState extends State<ApplyForUnitSheet> {
  /// Backend caps the note at 1000 characters.
  static const int _maxMessageLength = 1000;

  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    final property = widget.listing.property;

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
                    'Apply for this unit',
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
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.vacantSurface(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unit ${unit.unitNumber} · ${property.name}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${LandaCurrency.perYear(unit.rentAmount)} · ${unit.bedrooms} bed · ${unit.bathrooms} bath',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.readingTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MESSAGE TO LANDLORD (OPTIONAL)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: AppTheme.mutedTextColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _messageController,
              maxLines: 4,
              maxLength: _maxMessageLength,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                // Names an inspection date on purpose. The note is the only
                // thing a landlord reads before deciding, and the question
                // they answer first is when the tenant wants to see the
                // place: left to a blank box, most applications arrive
                // without it and the conversation starts a day later.
                hintText:
                    'e.g. I am interested in this unit. Could I come for an '
                    'inspection on Saturday the 12th? I can move in from '
                    'the 1st.',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppTheme.mutedTextColor(context),
                ),
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
            const SizedBox(height: 4),
            Text(
              'The landlord will review your application and, if approved, send '
              'you a tenancy agreement to sign.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  ApplyResult(message: _messageController.text.trim()),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.actionColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Send application',
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
