import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../controllers/notification_controller.dart';
import '../models/notification_model.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<NotificationController>().loadNotifications(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationController>();
    final primaryTextColor = AppTheme.primaryTextColor(context);

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
      body: Column(
        children: [
          _FilterBar(controller: controller),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.loadNotifications,
              child: _buildBody(context, controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, NotificationController controller) {
    if (!controller.hasLoaded ||
        (controller.isLoading && controller.notifications.isEmpty)) {
      return const LandaContentSwitcher(
        stateKey: 'loading',
        child: LandaSkeletonList(
          count: 5,
          hasAvatar: true,
          hasPill: false,
          padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
        ),
      );
    }

    if (controller.hasError && controller.notifications.isEmpty) {
      return LandaContentSwitcher(
        stateKey: 'error',
        child: LandaErrorState(
          message: controller.errorMessage,
          isConnectionError: controller.errorIsConnection,
          onRetry: controller.loadNotifications,
          padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
        ),
      );
    }

    if (controller.notifications.isEmpty) {
      return LandaContentSwitcher(
        stateKey: 'empty',
        child: LandaEmptyState(
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

    return LandaContentSwitcher(
      stateKey: 'content',
      child: Column(
        children: [
          if (controller.hasError)
            LandaErrorBanner(
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
              itemBuilder: (context, index) => LandaEntrance(
                index: index,
                child: _NotificationCard(
                  notification: controller.notifications[index],
                  onTap: () =>
                      controller.markRead(controller.notifications[index].id),
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
                  color: type.surfaceColor,
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
