import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_variant.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../../shortlets/views/respond_to_caution_claim_sheet.dart';
import '../controllers/notification_controller.dart';
import '../models/notification_model.dart';
import 'broadcast_composer_sheet.dart';

class NotificationsScreen extends StatefulWidget {
  final bool isEmbedded;

  const NotificationsScreen({super.key, this.isEmbedded = false});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with AutoRefreshMixin<NotificationsScreen> {
  @override
  Future<void> onAutoRefresh() =>
      context.read<NotificationController>().loadNotifications();

  /// Marks the row read, and, for the one type that needs it, opens the
  /// response sheet straight from the notification's own payload.
  ///
  /// Only a tenant is ever the one meant to act on a caution-fee-claim
  /// notification: the same type also announces a host's own claim landing,
  /// or a tenant's response coming back to them, and neither of those is
  /// something to respond to a second time.
  Future<void> _handleTap(NotificationItemModel notification) async {
    final controller = context.read<NotificationController>();
    await controller.markRead(notification.id);
    if (!mounted) return;

    final claimId = notification.cautionClaimId;
    final isTenant =
        context.read<AuthController>().currentRole == UserRole.tenant;
    if (notification.type == NotificationType.shortLetCautionFeeClaim &&
        isTenant &&
        claimId != null &&
        claimId.isNotEmpty) {
      await openRespondToCautionClaimSheet(
        context,
        claimId: claimId,
        claimedAmount: notification.cautionClaimAmount,
        hostReason: notification.cautionClaimReason,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationController>();
    final primaryTextColor = AppTheme.primaryTextColor(context);

    final body = Column(
      children: [
        // The type filters are v1 rental events; v2 shows one list.
        if (!isOasisV2) _FilterBar(controller: controller),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.loadNotifications,
            child: _buildBody(context, controller),
          ),
        ),
      ],
    );

    if (widget.isEmbedded) return body;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: primaryTextColor),
        title: Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryTextColor,
          ),
        ),
        actions: [
          // Announcing is a landlord action, and the notification list is
          // where the result of it lands, so the way to send one lives here
          // rather than buried in a settings screen.
          if (context.watch<AuthController>().currentRole == UserRole.owner)
            IconButton(
              tooltip: 'Announce to tenants',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const BroadcastComposerSheet(),
              ),
              icon: const Icon(
                Icons.campaign_outlined,
                color: AppTheme.actionColor,
              ),
            ),
          if (controller.notifications.any((n) => !n.isRead))
            TextButton(
              onPressed: controller.isLoading
                  ? null
                  : () => controller.markAllRead(),
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: AppTheme.actionColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, NotificationController controller) {
    if (!controller.hasLoaded ||
        (controller.isLoading && controller.notifications.isEmpty)) {
      return const OasisContentSwitcher(
        stateKey: 'loading',
        child: OasisSkeletonList(
          count: 5,
          hasAvatar: true,
          hasPill: false,
          padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
        ),
      );
    }

    if (controller.hasError && controller.notifications.isEmpty) {
      return OasisContentSwitcher(
        stateKey: 'error',
        child: OasisErrorState(
          message: controller.errorMessage,
          isConnectionError: controller.errorIsConnection,
          onRetry: controller.loadNotifications,
          padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
        ),
      );
    }

    if (controller.notifications.isEmpty) {
      return OasisContentSwitcher(
        stateKey: 'empty',
        child: OasisEmptyState(
          icon: controller.hasActiveFilter
              ? Icons.filter_alt_off_outlined
              : Icons.notifications_none_outlined,
          title: controller.hasActiveFilter
              ? 'Nothing matches this filter'
              : 'You are all caught up',
          message: controller.hasActiveFilter
              ? 'Try a different filter to see more activity.'
              : 'Agreement, payment, and escrow updates will appear here.',
          actionLabel: controller.hasActiveFilter ? 'Clear filters' : 'Refresh',
          actionIcon: controller.hasActiveFilter
              ? Icons.filter_alt_off_rounded
              : Icons.refresh_rounded,
          onAction: controller.hasActiveFilter
              ? controller.clearFilters
              : controller.loadNotifications,
          padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
        ),
      );
    }

    return OasisContentSwitcher(
      stateKey: 'content',
      child: Column(
        children: [
          if (controller.hasError)
            OasisErrorBanner(
              message: controller.errorMessage!,
              isConnectionError: controller.errorIsConnection,
              onRetry: controller.loadNotifications,
            ),
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              itemCount: controller.notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => OasisEntrance(
                index: index,
                child: _NotificationCard(
                  notification: controller.notifications[index],
                  onTap: () => _handleTap(controller.notifications[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontally scrolling filter chips backed by the backend query params.
class _FilterBar extends StatelessWidget {
  final NotificationController controller;

  const _FilterBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    // Only offer types the backend actually emits.
    const types = [
      NotificationType.agreementReceived,
      NotificationType.agreementSigned,
      NotificationType.agreementExecuted,
      NotificationType.paymentInitiated,
      NotificationType.paymentRecorded,
      NotificationType.escrowDisputed,
      NotificationType.escrowReleased,
    ];

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        children: [
          _Chip(
            label: 'All',
            selected: !controller.hasActiveFilter,
            onSelected: (_) => controller.clearFilters(),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Unread',
            selected: controller.unreadOnly,
            onSelected: (selected) =>
                controller.applyFilters(unreadOnly: selected),
          ),
          const SizedBox(width: 8),
          for (final type in types) ...[
            _Chip(
              label: type.label,
              selected: controller.typeFilter == type,
              accent: type.accentColor,
              onSelected: (selected) => controller.applyFilters(
                type: selected ? type : null,
                clearType: !selected,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? accent;
  final ValueChanged<bool> onSelected;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.actionColor;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : AppTheme.secondaryTextColor(context),
      ),
      backgroundColor: AppTheme.surfaceColor(context),
      selectedColor: color,
      side: BorderSide(color: selected ? color : AppTheme.borderColor(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationItemModel notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = notification.type;
    final isUnread = !notification.isRead;

    return Material(
      color: AppTheme.surfaceColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isUnread ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnread
                  ? type.accentColor.withValues(alpha: 0.35)
                  : AppTheme.borderColor(context),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: type.surfaceColor(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(type.icon, size: 20, color: type.accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            type.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: type.accentColor,
                            ),
                          ),
                        ),
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: type.accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // A broadcast carries a subject of its own; older
                    // notification types do not, and skip straight to the
                    // message rather than repeating the category eyebrow.
                    if (notification.title != null &&
                        notification.title!.trim().isNotEmpty) ...[
                      Text(
                        notification.headline,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: AppTheme.primaryTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: isUnread
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: AppTheme.primaryTextColor(context),
                      ),
                    ),
                    if (notification.actorName != null &&
                        notification.actorName!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'From ${notification.actorName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryTextColor(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _relativeTime(notification.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.mutedTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders an ISO 8601 timestamp as a short relative label.
  static String _relativeTime(String isoTimestamp) {
    final parsed = DateTime.tryParse(isoTimestamp);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed.toLocal());

    if (diff.isNegative) return 'Just now';
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${parsed.toLocal()}'.split(' ').first;
  }
}
