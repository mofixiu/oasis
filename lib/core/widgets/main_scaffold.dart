import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/user_model.dart';
import '../../features/auth/views/identity_verification_screen.dart';
import '../../features/dashboard/views/dashboard_screen.dart';
import '../../features/dashboard/views/landlord_dashboard_screen.dart';
import '../../features/marketplace/views/landlord_applications_screen.dart';
import '../../features/marketplace/views/marketplace_screen.dart';
import '../../features/payments/views/payments_screen.dart';

// NON-MVP FEATURES (Commented out for 30-day MVP phase):
// import '../../features/maintenance/views/fixes_screen.dart';
// import '../../features/vault/views/vault_screen.dart';

import 'custom_bottom_navbar.dart';

/// Wrapper scaffold that maintains the bottom navigation state and switches
/// between the MVP feature screens.
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();

    // Product APIs are backend-gated until identity verification reaches
    // VERIFIED. Keep the client navigation in the same state as that gate.
    if (authController.isAuthenticated &&
        authController.currentUser?.verificationStatus !=
            VerificationStatus.verified) {
      return const IdentityVerificationScreen();
    }

    final isLandlord = authController.currentRole == UserRole.owner;

    // MVP Active Navigation Screens. Order must stay in step with the items
    // in CustomBottomNavbar.
    final List<Widget> screens = [
      isLandlord ? const LandlordDashboardScreen() : const DashboardScreen(),
      isLandlord
          ? const LandlordApplicationsScreen()
          : const MarketplaceScreen(),
      const PaymentsScreen(),

      // NON-MVP SCREENS (Commented out):
      // const FixesScreen(),
      // const VaultScreen(),
    ];

    // Safety check for index out of bounds
    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: Stack(
        children: [
          screens[_currentIndex],

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomBottomNavbar(
              currentIndex: _currentIndex,
              isLandlord: isLandlord,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
