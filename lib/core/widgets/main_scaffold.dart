import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/user_model.dart';
import '../../features/auth/views/identity_verification_screen.dart';
import '../../features/dashboard/views/dashboard_screen.dart';
import '../../features/dashboard/views/landlord_dashboard_screen.dart';
import '../../features/fix/views/artisan_home_screen.dart';
import '../../features/marketplace/views/landlord_applications_screen.dart';
import '../../features/marketplace/views/marketplace_screen.dart';
import '../../features/payments/views/payments_screen.dart';
import '../../features/shortlets/views/landlord_shortlets_screen.dart';
import '../../features/shortlets/views/shortlet_browse_screen.dart';

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

    final role = authController.currentRole;

    // MVP Active Navigation Screens. Order must stay in step with the items
    // in CustomBottomNavbar. The second slot is the one each renting role
    // uses differently: a landlord decides on applications there, a tenant
    // browses the listings they can apply through.
    //
    // Short lets get a tab of their own for both renting roles. They are a
    // second business running on the same units: nightly rather than yearly,
    // with their own inbox and their own money, so burying them under
    // Discover or behind a dashboard button made them read as a footnote to
    // renting.
    //
    // An artisan gets neither, and now gets no tab bar at all. They hold no
    // unit, sign no agreement and pay no rent; since API guide 18 removed the
    // Fix job workflow they take no jobs through Landa and are paid no money
    // through it either. What is left for them is one screen: the listing
    // landlords and tenants find them by, so a bottom bar would be a row of
    // one. Fix itself is not a tab for the other two roles: a tenant reaches
    // it from a card on their dashboard, and a landlord from the unit they
    // want cover on.
    final List<Widget> screens = switch (role) {
      UserRole.owner => const [
        LandlordDashboardScreen(),
        LandlordApplicationsScreen(),
        LandlordShortLetsScreen(),
        PaymentsScreen(),
      ],
      UserRole.tenant => const [
        DashboardScreen(),
        MarketplaceScreen(),
        ShortLetBrowseScreen(),
        PaymentsScreen(),
      ],
      UserRole.artisan => const [ArtisanHomeScreen()],
    };

    // Safety check for index out of bounds
    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: Stack(
        children: [
          // An IndexedStack, not `screens[_currentIndex]`.
          //
          // Switching tabs used to destroy the outgoing screen and build the
          // incoming one from nothing: scroll position lost, every controller
          // refetched, skeletons on a tab that was fully loaded ten seconds
          // ago. Dashboard → Stays → Dashboard should put you back exactly
          // where you were, because that is what the phone does everywhere
          // else.
          //
          // The cost is that every tab stays alive once visited. That is the
          // point: the controllers are process-wide singletons anyway, so
          // the state was already in memory; the widgets were the only thing
          // being thrown away.
          IndexedStack(index: _currentIndex, children: screens),

          // Hidden for a role with one destination. A bar with a single item
          // is chrome that does nothing but take a thumb's worth of screen.
          if (screens.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CustomBottomNavbar(
                currentIndex: _currentIndex,
                role: role,
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
