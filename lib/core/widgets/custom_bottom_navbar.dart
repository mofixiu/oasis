import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/app_theme.dart';

/// Custom bottom navigation bar for Landa OS MVP.
class CustomBottomNavbar extends StatelessWidget {
  final int currentIndex;
  final bool isLandlord;
  final Function(int) onTap;

  const CustomBottomNavbar({
    super.key,
    required this.currentIndex,
    this.isLandlord = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = AppTheme.isDarkMode(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      decoration: BoxDecoration(
        color: (isDarkMode ? AppTheme.darkCardColor : Colors.white).withOpacity(
          isDarkMode ? 0.94 : 0.85,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDarkMode
              ? AppTheme.profileColor.withOpacity(0.28)
              : Colors.white.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
            height: 72,
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: BottomNavigationBar(
                currentIndex: currentIndex,
                onTap: onTap,
                backgroundColor: Colors.transparent,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: AppTheme.actionColor,
                unselectedItemColor: isDarkMode
                    ? AppTheme.whiteColor.withOpacity(0.65)
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
                items: const [
                  BottomNavigationBarItem(
                    icon: Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Icon(Icons.grid_view_outlined),
                    ),
                    label: 'DASHBOARD',
                  ),
                  BottomNavigationBarItem(
                    icon: Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Icon(Icons.payments_outlined),
                    ),
                    label: 'PAYMENTS',
                  ),

                  /*
                  // ==========================================================
                  // NON-MVP NAVIGATION TABS (Commented Out for MVP Phase)
                  // ==========================================================
                  BottomNavigationBarItem(
                    icon: Icon(Icons.explore_outlined),
                    label: 'DISCOVER',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.build_outlined),
                    label: 'FIX',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    label: 'VAULT',
                  ),
                  */
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
