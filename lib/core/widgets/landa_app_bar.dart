import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../../features/messaging/controllers/messaging_controller.dart';
import '../../features/messaging/views/conversations_screen.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../features/notifications/views/notifications_screen.dart';
import '../../features/profile/views/profile_screen.dart';
import 'landa_animated_value.dart';
import 'landa_pressable.dart';
import '../utils/fade_page_route.dart';

/// Standardized Landa OS App Bar.
///
/// The account avatar leads on the left: it is the one control that is about
/// *you* rather than about the app, and it reads as an identity anchor there
/// in a way it never did tucked in behind three other icons. The wordmark it
/// replaced was decoration: every screen under it already says where you are.
///
/// The right-hand group is ordered by how often it is needed: notifications
/// first, then messages. Discover is not here: it owns a bottom-nav slot of
/// its own on a tenant's app.
class LandaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showProfileIcon;

  /// Pushed routes need a way back; tab roots do not.
  final bool showBackButton;

  /// Whether the Messages button belongs on this screen.
  ///
  /// Off for an artisan. A conversation in Landa hangs off an application or
  /// a tenancy, and an artisan has neither: the inbox would open on an empty
  /// list that can never fill. The bell stays, because verification lands
  /// there.
  final bool showMessages;

  const LandaAppBar({
    super.key,
    this.showProfileIcon = true,
    this.showBackButton = false,
    this.showMessages = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    // A pushed route still needs its back arrow, and the avatar still belongs
    // on the left, so the two share the leading slot rather than the avatar
    // being exiled to the far right on those screens.
    final showAvatar = showProfileIcon;

    return AppBar(
      backgroundColor: AppTheme.pageBackground(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
      titleSpacing: 0,
      centerTitle: false,
      leadingWidth: _leadingWidth,
      leading: (showBackButton || showAvatar)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showBackButton) const _BackButton(),
                if (showAvatar)
                  Padding(
                    padding: EdgeInsets.only(left: showBackButton ? 0 : 20),
                    child: const _ProfileAvatar(),
                  ),
              ],
            )
          : null,
      actions: showProfileIcon
          ? [
              const _NotificationBell(),
              if (showMessages) const _MessagesButton(),
              const SizedBox(width: 8),
            ]
          : null,
    );
  }

  /// Enough room for whatever the leading row actually holds. An over-wide
  /// leading slot pushes the (empty) title area around and makes the bar look
  /// unbalanced, so it is sized rather than left to the default 56.
  double get _leadingWidth {
    var width = 0.0;
    if (showBackButton) width += 48;
    if (showProfileIcon) width += showBackButton ? 44 : 64;
    return width == 0 ? 0 : width;
  }
}

/// Explicit back arrow. [AppBar.automaticallyImplyLeading] is off because the
/// leading slot is a row, so the arrow has to be built here.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Back',
    onPressed: () => Navigator.maybePop(context),
    icon: Icon(
      Icons.arrow_back_rounded,
      color: AppTheme.primaryTextColor(context),
    ),
  );
}

/// Tappable account avatar. Shows the signed-in user's initial rather than a
/// generic person glyph: the same treatment the profile screen already uses,
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
      onTap: () =>
          Navigator.push(context, FadePageRoute(page: const ProfileScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
        FadePageRoute(page: const NotificationsScreen()),
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 26,
            color: AppTheme.primaryTextColor(context),
          ),
          // Scales in and out rather than appearing and vanishing. A badge
          // that pops into existence between frames is the difference
          // between "you have a notification" and a rendering glitch, and
          // the count inside it now counts, instead of being swapped.
          Positioned(
            right: -3,
            top: -3,
            child: AnimatedScale(
              scale: unread > 0 ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
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
                child: LandaAnimatedValue(
                  value: unread > 9 ? '9+' : '$unread',
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
          ),
        ],
      ),
    );
  }
}

/// Opens the message inbox, badged with unread threads.
///
/// Sits beside the bell rather than in the bottom nav: messaging is a reply to
/// something that already happened (an application, a tenancy) not a
/// destination people set out for, and the bottom bar is down to three slots
/// for the MVP.
class _MessagesButton extends StatelessWidget {
  const _MessagesButton();

  @override
  Widget build(BuildContext context) {
    // The controller's own count rather than one derived from the inbox
    // list. `inboxUnreadCount` is a fold over `conversations`, which is empty
    // until the inbox screen has been opened, so the dot only ever appeared
    // *after* visiting the screen it was meant to advertise. Both dashboards
    // now refresh this number on load, and the socket keeps it moving.
    final unread = context.select<MessagingController, int>(
      (controller) => controller.unreadCount,
    );

    return IconButton(
      tooltip: 'Messages',
      onPressed: () => Navigator.push(
        context,
        FadePageRoute(page: const ConversationsScreen()),
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 24,
            color: AppTheme.primaryTextColor(context),
          ),
          if (unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: AppTheme.actionColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.pageBackground(context),
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
