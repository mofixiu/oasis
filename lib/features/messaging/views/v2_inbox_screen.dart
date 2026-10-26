import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/v2_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../notifications/controllers/notification_controller.dart';
import '../../notifications/views/broadcast_composer_sheet.dart';
import '../../notifications/views/notifications_screen.dart';
import '../controllers/messaging_controller.dart';
import 'conversations_screen.dart';

enum _InboxSection { messages, notifications }

/// Brings guest and host messages and account updates into the V2 Inbox tab.
class V2InboxScreen extends StatefulWidget {
  final VoidCallback onExplore;

  const V2InboxScreen({super.key, required this.onExplore});

  @override
  State<V2InboxScreen> createState() => _V2InboxScreenState();
}

class _V2InboxScreenState extends State<V2InboxScreen> {
  _InboxSection _selectedSection = _InboxSection.messages;

  void _announceToTenants() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const BroadcastComposerSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final notifications = context.watch<NotificationController>();
    final messaging = context.watch<MessagingController>();
    final isShowingNotifications =
        _selectedSection == _InboxSection.notifications;

    return V2StatusBar(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              V2PageHeader(
                title: 'Inbox',
                subtitle: 'Messages, updates and support.',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isShowingNotifications &&
                        auth.currentRole == UserRole.owner) ...[
                      V2CircleButton(
                        icon: Icons.campaign_outlined,
                        tooltip: 'Announce to guests',
                        onTap: _announceToTenants,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (isShowingNotifications &&
                        notifications.notifications.any(
                          (item) => !item.isRead,
                        )) ...[
                      V2CircleButton(
                        icon: Icons.done_all_rounded,
                        tooltip: 'Mark all read',
                        onTap: notifications.isLoading
                            ? null
                            : () => notifications.markAllRead(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const V2ProfileButton(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: V2SegmentChips(
                  labels: [
                    messaging.unreadCount > 0
                        ? 'Messages (${messaging.unreadCount})'
                        : 'Messages',
                    notifications.unreadCount > 0
                        ? 'Updates (${notifications.unreadCount})'
                        : 'Updates',
                  ],
                  selected: _selectedSection.index,
                  onSelected: (index) => setState(
                    () => _selectedSection = _InboxSection.values[index],
                  ),
                ),
              ),
              Expanded(
                child: _selectedSection == _InboxSection.messages
                    ? ConversationsScreen(
                        isV2: true,
                        isTabRoot: true,
                        isEmbedded: true,
                        onExplore: widget.onExplore,
                      )
                    : const NotificationsScreen(isEmbedded: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
