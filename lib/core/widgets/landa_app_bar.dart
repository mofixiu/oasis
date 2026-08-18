import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../features/notifications/views/notifications_screen.dart';
import '../../features/profile/views/profile_screen.dart';

/// Standardized Landa OS App Bar
/// Left-aligned LandaOS logo, right-aligned notification bell and profile avatar
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
              const _NotificationBell(),
              const SizedBox(width: 4),
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

/// Bell that opens the notifications screen, badged with the unread count.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationController, int>(
      (controller) => controller.unreadCount,
    );

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 26,
            color: AppTheme.primaryTextColor(context),
          ),
          if (unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 17),
                decoration: BoxDecoration(
                  color: AppTheme.actionColor,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: AppTheme.pageBackground(context),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
