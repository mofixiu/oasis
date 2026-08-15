import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../profile/views/profile_screen.dart';
import 'widgets/tenant_vault_view.dart';
import 'widgets/landlord_vault_view.dart';

class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final isLandlord = authController.currentRole == UserRole.owner;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        leading: isLandlord
            ? IconButton(
                icon: const Icon(Icons.menu, color: AppTheme.primaryColor),
                onPressed: () {
                  // Toggle sidebar drawer in a real application
                },
              )
            : null,
        title: Image.asset('assets/images/newlogonobackground.png', height: 40),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 16,
                backgroundImage: const AssetImage(
                  'assets/images/profile_avatar.png',
                ),
                backgroundColor: Colors.grey.shade300,
              ),
            ),
          ),
        ],
      ),
      body: isLandlord ? const LandlordVaultView() : const TenantVaultView(),
    );
  }
}
