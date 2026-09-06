import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../auth/controllers/auth_controller.dart';
import 'add_property_modal.dart';
import 'invite_tenant_modal.dart';

class LandlordHeader extends StatelessWidget {
  const LandlordHeader({super.key});

  void _showAddProperty(BuildContext context) => openAddPropertyFlow(context);

  void _showInviteTenant(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
        Text(
          'Portfolio\nOverview',
          style: AppTheme.screenTitle(
            context,
            color: AppTheme.primaryColor,
          ).copyWith(height: 1.15),
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome back, $displayName. Here is your current standing.',
          style: AppTheme.bodyText(context),
        ),
        const SizedBox(height: 24),
        LandaButton(
          label: 'Add New Property',
          icon: Icons.add_rounded,
          onPressed: () => _showAddProperty(context),
        ),
        const SizedBox(height: 12),
        // Secondary action, so it is outlined rather than a second filled
        // button competing with the first for attention.
        LandaButton(
          label: 'Invite Tenant',
          icon: Icons.person_add_alt_1_rounded,
          outlined: true,
          onPressed: () => _showInviteTenant(context),
        ),
      ],
    );
  }
}
