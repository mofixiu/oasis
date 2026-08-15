import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/controllers/auth_controller.dart';
import 'add_property_modal.dart';
import 'invite_tenant_modal.dart';

class LandlordHeader extends StatelessWidget {
  const LandlordHeader({super.key});

  void _showAddProperty(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.8;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints.tightFor(height: sheetHeight),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AddPropertyModal(),
    );
  }

  void _showInviteTenant(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const InviteTenantModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().currentUser;
    final displayName = user?.email.split('@').first ?? 'landlord';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Portfolio\nOverview',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryColor,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome back, $displayName. Here is your current standing.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => _showAddProperty(context),
            icon: const Icon(Icons.add, size: 20, color: Colors.white),
            label: const Text(
              'Add New Property',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.actionColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => _showInviteTenant(context),
            icon: const Icon(
              Icons.person_add_alt_1,
              size: 20,
              color: Colors.white,
            ),
            label: const Text(
              'Invite Tenant',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.actionColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
