import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/controllers/auth_controller.dart';
import '../../features/auth/models/user_model.dart';
import '../../features/auth/views/identity_verification_screen.dart';
import '../../features/fix/views/artisan_home_screen.dart';
import '../../features/messaging/controllers/messaging_controller.dart';
import '../../features/messaging/views/v2_inbox_screen.dart';
import '../../features/notifications/controllers/notification_controller.dart';
import '../../features/shortlets/views/landlord_shortlets_screen.dart';
import '../../features/shortlets/views/my_shortlet_bookings_screen.dart';
import '../../features/shortlets/views/shortlet_browse_screen.dart';
import '../../features/shortlets/views/v2/v2_guest_home_screen.dart';
import '../../features/shortlets/views/v2/v2_host_home_screen.dart';
import '../../features/shortlets/views/v2/v2_payments_screen.dart';
import '../theme/app_theme.dart';
import '../utils/oasis_refresh.dart';

/// Role-aware short-stay shell selected only by `APP_VARIANT=v2`.
class V2MainScaffold extends StatefulWidget {
  const V2MainScaffold({super.key});

  @override
  State<V2MainScaffold> createState() => _V2MainScaffoldState();
}

class _V2MainScaffoldState extends State<V2MainScaffold> {
  int _currentIndex = 0;
  final ValueNotifier<int> _activeTab = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // The Home bell and Profile's Updates count read the unread count, but
    // the Updates list that loads it is only built once it is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthController>().currentUser;
      if (user?.verificationStatus != VerificationStatus.verified) return;
      context.read<NotificationController>().loadNotifications();
    });
  }

  @override
  void dispose() {
    _activeTab.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activeTab.value = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.isAuthenticated &&
        auth.currentUser?.verificationStatus != VerificationStatus.verified) {
      return const IdentityVerificationScreen();
    }

    final role = auth.currentRole;
    if (role.isArtisan) return const ArtisanHomeScreen();

    final isHost = role == UserRole.owner;
    final screens = isHost
        ? <Widget>[
            V2HostHomeScreen(onManageStays: () => _selectTab(1)),
            const LandlordShortLetsScreen(isV2: true),
            V2InboxScreen(onExplore: () => _selectTab(1)),
            V2PaymentsScreen(onManageStays: () => _selectTab(1)),
          ]
        : <Widget>[
            V2GuestHomeScreen(onDiscover: () => _selectTab(1)),
            const ShortLetBrowseScreen(isV2: true),
            MyShortLetBookingsScreen(
              isV2: true,
              isTabRoot: true,
              onExplore: () => _selectTab(1),
            ),
            V2InboxScreen(onExplore: () => _selectTab(1)),
            V2PaymentsScreen(
              onExplore: () => _selectTab(1),
              onOpenTrips: () => _selectTab(2),
            ),
          ];

    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
      _activeTab.value = 0;
    }

    final labels = isHost
        ? const ['HOME', 'SHORTLETS', 'INBOX', 'PAYMENTS']
        : const ['HOME', 'DISCOVER', 'TRIPS', 'INBOX', 'PAYMENTS'];
    final icons = isHost
        ? const [
            Icons.dashboard_outlined,
            Icons.holiday_village_outlined,
            Icons.chat_bubble_outline_rounded,
            Icons.payments_outlined,
          ]
        : const [
            Icons.home_outlined,
            Icons.explore_outlined,
            Icons.luggage_outlined,
            Icons.chat_bubble_outline_rounded,
            Icons.payments_outlined,
          ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              for (var i = 0; i < screens.length; i++)
                OasisTabVisibility(
                  activeIndex: _activeTab,
                  index: i,
                  child: screens[i],
                ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _V2BottomBar(
              currentIndex: _currentIndex,
              labels: labels,
              icons: icons,
              onTap: _selectTab,
            ),
          ),
        ],
      ),
    );
  }
}

class _V2BottomBar extends StatelessWidget {
  final int currentIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onTap;

  const _V2BottomBar({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnreadInbox =
        context.select<MessagingController, bool>(
          (controller) => controller.unreadCount > 0,
        ) ||
        context.select<NotificationController, bool>(
          (controller) => controller.unreadCount > 0,
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: SizedBox(
            height: 74,
            child: Row(
              children: [
                for (var index = 0; index < labels.length; index++)
                  Expanded(
                    child: InkWell(
                      onTap: () => onTap(index),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (labels[index] == 'INBOX')
                            _V2UnreadInboxIcon(
                              icon: icons[index],
                              showDot: hasUnreadInbox,
                              selected: currentIndex == index,
                            )
                          else
                            Icon(
                              icons[index],
                              size: 21,
                              color: currentIndex == index
                                  ? AppTheme.terracottaColor
                                  : AppTheme.mutedTextColor(context),
                            ),
                          const SizedBox(height: 5),
                          Text(
                            labels[index],
                            maxLines: 1,
                            style: TextStyle(
                              color: currentIndex == index
                                  ? AppTheme.primaryTextColor(context)
                                  : AppTheme.mutedTextColor(context),
                              fontSize: 8.5,
                              letterSpacing: 0.35,
                              fontWeight: currentIndex == index
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _V2UnreadInboxIcon extends StatelessWidget {
  final IconData icon;
  final bool showDot;
  final bool selected;

  const _V2UnreadInboxIcon({
    required this.icon,
    required this.showDot,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: showDot ? 'Inbox, unread activity' : 'Inbox',
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          icon,
          size: 21,
          color: selected
              ? AppTheme.terracottaColor
              : AppTheme.mutedTextColor(context),
        ),
        if (showDot)
          Positioned(
            right: -3,
            top: -2,
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
  );
}

/// V2 uses a five-item bar with the same reserved inset as the original bar.
const double v2BottomBarReservedHeight = 96;
