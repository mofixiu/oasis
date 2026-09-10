import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../features/auth/models/user_model.dart';
import '../../features/marketplace/controllers/marketplace_controller.dart';
import '../../features/shortlets/controllers/shortlet_controller.dart';
import '../theme/app_theme.dart';
import '../utils/oasis_haptics.dart';

/// Custom bottom navigation bar for Oasis MVP.
class CustomBottomNavbar extends StatelessWidget {
  final int currentIndex;

  /// Whose app this is. Each role gets a different set of destinations, and
  /// the order here must stay in step with the screen list in `MainScaffold`.
  final UserRole role;

  final Function(int) onTap;

  const CustomBottomNavbar({
    super.key,
    required this.currentIndex,
    this.role = UserRole.tenant,
    required this.onTap,
  });

  bool get _isLandlord => role == UserRole.owner;

  /// Vertical space the bar occupies at the bottom of the screen: its own
  /// height plus the gap it floats above the edge.
  ///
  /// The bar is an overlay in [MainScaffold]'s Stack rather than a Scaffold's
  /// own `bottomNavigationBar`, so nothing beneath it is inset automatically.
  /// Any screen with content or a button near the bottom has to leave this
  /// much room itself, and should read it from here rather than re-deriving a
  /// number that would drift when the bar changes.
  static const double reservedHeight = _barHeight + _bottomGap;

  static const double _barHeight = 72;
  static const double _bottomGap = 12;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = AppTheme.isDarkMode(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, _bottomGap),
      decoration: BoxDecoration(
        color: (isDarkMode ? AppTheme.darkCardColor : Colors.white).withValues(
          alpha: isDarkMode ? 0.94 : 0.85,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode
              ? AppTheme.profileColor.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: SizedBox(
            height: _barHeight,
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: BottomNavigationBar(
                currentIndex: currentIndex,
                onTap: (index) {
                  // Tab changes are selection-class feedback, not commits.
                  if (index != currentIndex) OasisHaptics.select();
                  onTap(index);
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: AppTheme.actionColor,
                unselectedItemColor: isDarkMode
                    ? AppTheme.whiteColor.withValues(alpha: 0.65)
                    : Colors.grey.shade600,
                showSelectedLabels: true,
                showUnselectedLabels: true,
                selectedLabelStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                items: _items(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The destinations for the signed-in role.
  ///
  /// An artisan gets neither Stays nor Payments: they hold no unit and pay no
  /// rent, and both sets of endpoints are closed to them. What they have is
  /// the work and the money it earned.
  ///
  /// The second slot is the one each renting role uses differently, and both
  /// uses are the same shape: the inbound side of finding a tenancy. A
  /// landlord gets Applications, the decisions waiting on them; a tenant gets
  /// Discover, the listings they can apply through. Discover spent a release
  /// as a compass in the app bar, where finding a home (the reason a tenant
  /// installs this at all) ranked below three icons and got the smallest tap
  /// target on the screen.
  ///
  /// Fix is not a tab for either of the other two roles. A tenant needs it a
  /// few times a year: a permanent slot would give it more standing than
  /// rent, so they reach it from a card on their dashboard, and a landlord
  /// from the unit they want cover on.
  List<BottomNavigationBarItem> _items() {
    // No artisan branch: since API guide 18 removed the Fix job workflow an
    // artisan has a single screen, and `MainScaffold` does not render a bar
    // for them at all.

    return [
      const BottomNavigationBarItem(
        icon: Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Icon(Icons.grid_view_outlined),
        ),
        label: 'DASHBOARD',
      ),

      if (_isLandlord)
        const BottomNavigationBarItem(
          icon: Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: _PendingApplicationsIcon(),
          ),
          label: 'APPLICATIONS',
        )
      else
        // Undotted on purpose. The landlord's inbox dot marks a decision
        // waiting on them; nothing on Discover waits on a tenant. The one
        // thing that does, an approved application's agreement, already has
        // the banner on their dashboard, and a second alert for it here would
        // send them to the wrong screen for it.
        const BottomNavigationBarItem(
          icon: Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Icon(Icons.explore_outlined),
          ),
          label: 'DISCOVER',
        ),

      BottomNavigationBarItem(
        icon: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _ShortLetsIcon(isLandlord: _isLandlord),
        ),
        label: 'STAYS',
      ),

      const BottomNavigationBarItem(
        icon: Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Icon(Icons.payments_outlined),
        ),
        label: 'PAYMENTS',
      ),
    ];
  }
}

/// Short lets icon, dotted while something is actually waiting on this user.
///
/// The two roles wait on different things: a landlord owes guests a decision,
/// while a guest owes money on a stay that expires 24 hours after approval.
/// Both are time-limited, which is what earns the dot.
class _ShortLetsIcon extends StatelessWidget {
  final bool isLandlord;

  const _ShortLetsIcon({required this.isLandlord});

  @override
  Widget build(BuildContext context) {
    final waiting = context.select<ShortLetController, bool>(
      (controller) => isLandlord
          ? controller.pendingBookingCount > 0
          : controller.bookingsAwaitingPayment.isNotEmpty,
    );

    return _DottedIcon(icon: Icons.holiday_village_outlined, showDot: waiting);
  }
}

/// Applications inbox icon carrying a red dot while any application is still
/// awaiting the landlord's decision.
class _PendingApplicationsIcon extends StatelessWidget {
  const _PendingApplicationsIcon();

  @override
  Widget build(BuildContext context) {
    final hasPending = context.select<MarketplaceController, bool>(
      (controller) => controller.pendingLandlordApplicationCount > 0,
    );

    return _DottedIcon(icon: Icons.inbox_outlined, showDot: hasPending);
  }
}

/// A tab icon with an optional attention dot.
class _DottedIcon extends StatelessWidget {
  final IconData icon;
  final bool showDot;

  const _DottedIcon({required this.icon, required this.showDot});

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(icon),
      if (showDot)
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppTheme.alertDotColor,
              shape: BoxShape.circle,
              // Ring it against the bar so the dot stays legible on both the
              // light and dark navbar fills.
              border: Border.all(
                color: AppTheme.isDarkMode(context)
                    ? AppTheme.darkCardColor
                    : Colors.white,
                width: 1.5,
              ),
            ),
          ),
        ),
    ],
  );
}
