import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../features/notifications/views/notifications_screen.dart';
import '../../features/profile/views/profile_screen.dart';
import 'landa_pressable.dart';

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
      // The wordmark is navy, which all but disappears on the dark
      // background — dark mode gets the white-on-transparent variant.
      title: Image.asset(
        AppTheme.isDarkMode(context)
            ? 'assets/images/logo_wordmark_light.png'
            : 'assets/images/newlogonobackground.png',
        height: 48,
        fit: BoxFit.contain,
      ),
      actions: showProfileIcon
          ? [
              const _NotificationBell(),
              const SizedBox(width: 4),
              const _ProfileAvatar(),
            ]
          : null,
    );
  }
}

/// Tappable account avatar. Shows the signed-in user's initial rather than a
/// generic person glyph — the same treatment the profile screen already uses,
/// and it makes the bar feel like it belongs to someone.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) {
    final email = context.select<AuthController, String>(
      (controller) => controller.currentUser?.email ?? '',
    );
    final initial = email.isEmpty ? null : email[0].toUpperCase();

    return LandaPressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.only(right: 20.0, left: 4, top: 8, bottom: 8),
        child: Container(
          height: 36,
          width: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.profileColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.pageBackground(context),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.profileColor.withValues(alpha: 0.35),
                blurRadius: 12,
                spreadRadius: -3,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: initial == null
              ? const Icon(Icons.person, size: 18, color: Colors.white)
              : Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTheme.textMd,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
        ),
      ),
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
