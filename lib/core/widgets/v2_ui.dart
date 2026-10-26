import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../features/notifications/views/notifications_screen.dart';
import '../../features/profile/views/v2_profile_screen.dart';
import '../theme/app_theme.dart';
import '../utils/fade_page_route.dart';
import 'oasis_network_image.dart';
import 'oasis_pressable.dart';

/// Building blocks shared by the v2 short-stay screens, so every tab opens
/// with the same large heading, chip row and pill shapes.

/// Status bar icons for a v2 screen without an app bar: dark on the light
/// page, light in dark mode or when the screen opens on a photo.
class V2StatusBar extends StatelessWidget {
  final Widget child;
  final bool overPhoto;

  const V2StatusBar({super.key, required this.child, this.overPhoto = false});

  @override
  Widget build(BuildContext context) {
    final light = overPhoto || AppTheme.isDarkMode(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (light ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: child,
    );
  }
}

/// Large heading at the top of a v2 tab: title, one line of context, and an
/// optional control on the right.
class V2PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const V2PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  static TextStyle titleStyle(BuildContext context) => TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.9,
    height: 1.15,
    color: AppTheme.primaryTextColor(context),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: subtitle == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle(context)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: AppTheme.bodyText(context).copyWith(fontSize: 14),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    ),
  );
}

/// Round, softly filled icon button used beside page titles and over photos.
class V2CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool showDot;

  /// White fill with a shadow, for sitting on top of a photo.
  final bool onPhoto;
  final double size;

  const V2CircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.showDot = false,
    this.onPhoto = false,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final button = OasisPressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: onPhoto
              ? AppTheme.surfaceColor(context).withValues(alpha: 0.94)
              : AppTheme.surfaceColor(context),
          shape: BoxShape.circle,
          border: onPhoto
              ? null
              : Border.all(color: AppTheme.borderColor(context)),
          boxShadow: onPhoto ? AppTheme.cardShadow(context) : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 21, color: AppTheme.primaryTextColor(context)),
            if (showDot)
              Positioned(
                top: size * 0.24,
                right: size * 0.26,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppTheme.actionColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.surfaceColor(context),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Bell that opens notifications, dotted while any are unread.
class V2BellButton extends StatelessWidget {
  final bool onPhoto;
  final double size;

  const V2BellButton({super.key, this.onPhoto = false, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final hasUnread = context.select<NotificationController, bool>(
      (controller) => controller.unreadCount > 0,
    );
    return V2CircleButton(
      icon: Icons.notifications_none_rounded,
      tooltip: 'Notifications',
      showDot: hasUnread,
      onPhoto: onPhoto,
      size: size,
      onTap: () => Navigator.push(
        context,
        FadePageRoute(page: const NotificationsScreen()),
      ),
    );
  }
}

/// The account avatar. Opens the profile, which in v2 has no tab of its own.
class V2ProfileButton extends StatelessWidget {
  final double size;

  /// Draws a light ring so the avatar holds its edge on a photo.
  final bool onPhoto;

  const V2ProfileButton({super.key, this.size = 44, this.onPhoto = false});

  @override
  Widget build(BuildContext context) {
    final name = context.select<AuthController, String>(
      (controller) => controller.currentUser?.preferredName ?? '',
    );
    final photo = context.select<AuthController, String>(
      (controller) => controller.currentUser?.avatarUrl ?? '',
    );
    final initial = name.isEmpty ? null : name.characters.first.toUpperCase();

    return Semantics(
      button: true,
      label: 'Profile',
      child: OasisPressable(
        onTap: () => Navigator.push(
          context,
          FadePageRoute(page: const V2ProfileScreen()),
        ),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.terracottaColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: onPhoto
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppTheme.pageBackground(context),
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: photo.isNotEmpty
              ? OasisNetworkImage(
                  url: photo,
                  width: size,
                  height: size,
                  placeholderIcon: Icons.person,
                )
              : initial == null
              ? const Icon(Icons.person, size: 20, color: Colors.white)
              : Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTheme.textLg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Equal-width filled chips for switching between sections, the chosen one
/// in terracotta.
class V2SegmentChips extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  const V2SegmentChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < labels.length; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            button: true,
            selected: index == selected,
            child: OasisPressable(
              onTap: () => onSelected(index),
              pressedScale: 0.97,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == selected
                      ? AppTheme.terracottaColor
                      : AppTheme.surfaceColor(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: index == selected
                        ? AppTheme.terracottaColor
                        : AppTheme.borderColor(context),
                  ),
                ),
                child: Text(
                  labels[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTheme.textSm,
                    fontWeight: index == selected
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: index == selected
                        ? Colors.white
                        : AppTheme.primaryTextColor(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

/// Text tabs over a full-width rule, the selected one underlined in
/// terracotta.
class V2UnderlineTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  const V2UnderlineTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTheme.borderColor(context))),
    ),
    child: Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Semantics(
              button: true,
              selected: index == selected,
              child: InkWell(
                onTap: () => onSelected(index),
                child: SizedBox(
                  height: 46,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: AppTheme.textMd,
                          letterSpacing: -0.2,
                          fontWeight: index == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: index == selected
                              ? AppTheme.primaryTextColor(context)
                              : AppTheme.secondaryTextColor(context),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 3,
                          decoration: BoxDecoration(
                            color: index == selected
                                ? AppTheme.terracottaColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

enum V2Tone { positive, pending, negative, neutral }

/// Small status label in the app's status colours. Opaque in every tone, so
/// it can sit on a photo.
class V2StatusPill extends StatelessWidget {
  final String label;
  final V2Tone tone;

  const V2StatusPill({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      V2Tone.positive => (
        AppTheme.successSurface(context),
        AppTheme.successColor,
      ),
      V2Tone.pending => (
        AppTheme.vacantSurface(context),
        AppTheme.isDarkMode(context)
            ? AppTheme.sandColor
            : const Color(0xFF85602F),
      ),
      V2Tone.negative => (
        AppTheme.disputeSurface(context),
        AppTheme.isDarkMode(context)
            ? const Color(0xFFE59A8F)
            : AppTheme.brickRedColor,
      ),
      V2Tone.neutral => (
        AppTheme.borderColor(context),
        AppTheme.secondaryTextColor(context),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

/// Heading above a horizontal shelf, with a "See all" link.
class V2SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const V2SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: AppTheme.sectionTitle(
            context,
          ).copyWith(fontSize: 19, letterSpacing: -0.5),
        ),
      ),
      if (actionLabel != null && onAction != null)
        OasisPressable(
          onTap: onAction,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: AppTheme.cardTitle(
                    context,
                    color: AppTheme.terracottaColor,
                  ).copyWith(fontSize: 13),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppTheme.terracottaColor,
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
