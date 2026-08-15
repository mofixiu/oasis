import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../features/profile/views/profile_screen.dart';

/// Standardized Landa OS App Bar
/// Left-aligned, larger LandaOS logo and right-aligned profile avatar button
class LandaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showProfileIcon;

  const LandaAppBar({super.key, this.showProfileIcon = true});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.pageBackground(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      centerTitle: false,
      title: Image.asset(
        'assets/images/newlogonobackground.png',
        height: 48,
        fit: BoxFit.contain,
      ),
      actions: showProfileIcon
          ? [
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
                child: const Padding(
                  padding: EdgeInsets.only(right: 20.0),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.profileColor,
                    child: Icon(Icons.person, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ]
          : null,
    );
  }
}
