import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../../agreements/controllers/agreement_controller.dart';
import '../../../properties/controllers/landlord_controller.dart';
import '../../../properties/models/property_model.dart';

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
  final _rulesController = TextEditingController(text: 'No noise after 10 PM. Rent due annually.');
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
      LandaToast.error(context, 'Please enter tenant email or phone number.');
      return;
    }

    if (_selectedProperty == null || _selectedUnit == null) {
      LandaToast.error(context, 'Please select a property and unit.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final startDate = DateTime.now().toIso8601String().split('T').first;
      final endDate = DateTime.now().add(const Duration(days: 365)).toIso8601String().split('T').first;

      final agreementController = context.read<AgreementController>();
      final agreement = await agreementController.createAgreement(
        unitId: _selectedUnit!.id,
        tenantId: contact,
        rentAmount: _rentController.text.trim(),
        startDate: startDate,
        endDate: endDate,
        rules: _rulesController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (agreement != null) {
        Navigator.pop(context);
        LandaToast.success(context, 'Invitation & Tenancy Agreement sent to $contact!');
      } else {
        final errorMsg = agreementController.errorMessage ?? 'Could not create invitation. Please check details.';
        LandaToast.error(context, errorMsg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      LandaToast.error(context, 'Error inviting tenant: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final landlordCtrl = context.watch<LandlordController>();
    final properties = landlordCtrl.properties;
    final bool isSelectionValid = _selectedProperty != null && _selectedUnit != null;

    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.person_add_alt_1_outlined, color: AppTheme.actionColor),
                  SizedBox(width: 8),
                  Text(
                    'Invite Tenant',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Send an invitation link & tenancy bridge agreement to your tenant.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // Property Selector Dropdown
          const Text('SELECT PROPERTY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          DropdownButtonFormField<PropertyModel>(
            initialValue: _selectedProperty,
            hint: const Text('Choose Property'),
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            items: properties.map((p) {
              return DropdownMenuItem(
                value: p,
                child: Text(p.name),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _selectedProperty = val;
                _selectedUnit = null;
              });
            },
          ),
          const SizedBox(height: 16),

          // Unit Selector Dropdown
          if (_selectedProperty != null) ...[
            const Text('SELECT UNIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final units = landlordCtrl.propertyUnits[_selectedProperty!.id] ?? [];
                if (units.isEmpty) {
                  return Text(
                    'No units created for this property yet.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                  );
                }
                return DropdownButtonFormField<UnitModel>(
                  initialValue: _selectedUnit,
                  hint: const Text('Choose Unit'),
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  items: units.map((u) {
                    return DropdownMenuItem(
                      value: u,
                      child: Text('Unit ${u.unitNumber} (₦${u.rentAmount})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedUnit = val;
                      if (val != null && val.rentAmount.isNotEmpty) {
                        _rentController.text = val.rentAmount;
                      }
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          // Tenant Email/Phone
          const Text('TENANT EMAIL OR PHONE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          TextField(
            controller: _emailPhoneController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'tenant@example.com or +2348012345678',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),

          // Annual Rent Amount
          const Text('AGREED RENT AMOUNT (₦)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          TextField(
            controller: _rentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '450000.00',
              prefixIcon: const Icon(Icons.payments_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 24),

          // Submit Button (Greyed out when property or unit is not selected)
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: (_isSubmitting || !isSelectionValid) ? null : _submitInvite,
              icon: _isSubmitting
                  ? const SizedBox()
                  : Icon(
                      Icons.send_rounded,
                      color: isSelectionValid ? Colors.white : Colors.grey.shade600,
                      size: 18,
                    ),
              label: _isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      'Send Tenant Invitation',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isSelectionValid ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelectionValid ? AppTheme.actionColor : Colors.grey.shade300,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: isSelectionValid ? 2 : 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
