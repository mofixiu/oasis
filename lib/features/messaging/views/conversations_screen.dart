import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_network_image.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../controllers/messaging_controller.dart';
import '../models/conversation_models.dart';
import 'conversation_screen.dart';
import 'v2_message_time.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../shortlets/views/v2/v2_empty_state.dart';

/// The message inbox.
///
/// There is no "new message" button, because there is no one to pick from: a
/// thread is created from an application or a tenancy, in the place where that
/// relationship already appears. This screen only lists what exists.
class ConversationsScreen extends StatefulWidget {
  final bool isV2;
  final bool isTabRoot;
  final bool isEmbedded;
  final VoidCallback? onExplore;

  const ConversationsScreen({
    super.key,
    this.isV2 = false,
    this.isTabRoot = false,
    this.isEmbedded = false,
    this.onExplore,
  });

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen>
    with AutoRefreshMixin<ConversationsScreen> {
  /// Polls while open. The open thread has its own faster poll; this is the
  /// list, where a new message on a thread the user is not reading would
  /// otherwise only appear on a manual pull.
  @override
  Duration? get autoRefreshInterval => kOasisPollInterval;

  @override
  Future<void> onAutoRefresh() => _reload();

  Future<void> _reload() =>
      context.read<MessagingController>().loadConversations();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MessagingController>();

    final body = RefreshIndicator(
      onRefresh: _reload,
      child: _buildBody(context, controller),
    );

    if (widget.isEmbedded) return body;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: !widget.isTabRoot,
        iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
        title: Text('Messages', style: AppTheme.cardTitle(context)),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, MessagingController controller) {
    final conversations = controller.conversations;

    if (!controller.hasLoaded(MessagingController.kInboxKey) ||
        (controller.isLoading && conversations.isEmpty)) {
      return const OasisSkeletonList(count: 4);
    }

    if (controller.hasError && conversations.isEmpty) {
      return OasisErrorState(
        message: controller.errorMessage,
        isConnectionError: controller.errorIsConnection,
        onRetry: _reload,
      );
    }

    if (conversations.isEmpty) {
      if (widget.isV2) {
        return V2IllustratedEmptyState(
          artwork: V2EmptyArtwork.inbox,
          title: 'A conversation starts with a booking.',
          message:
              'Once a host confirms your booking, your messages and arrival '
              'details will be waiting here.',
          actionLabel: 'Explore shortlets',
          onAction: widget.onExplore ?? () => Navigator.maybePop(context),
        );
      }
      return OasisEmptyState(
        icon: Icons.forum_outlined,
        title: 'No conversations yet',
        message:
            'Messages open up once you apply for a unit or take one on. '
            'You can start a conversation from the application itself.',
        // Back to where a conversation can actually be started, rather than
        // leaving them on a screen whose only instruction is "go elsewhere".
        actionLabel: 'Back to your applications',
        actionIcon: Icons.arrow_back_rounded,
        onAction: () => Navigator.pop(context),
      );
    }

    if (widget.isV2) {
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 6, 20, widget.isTabRoot ? 118 : 40),
        itemCount: conversations.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          indent: 70,
          color: AppTheme.borderColor(context),
        ),
        itemBuilder: (context, index) =>
            _V2ConversationRow(conversation: conversations[index]),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 8, 20, widget.isTabRoot ? 118 : 40),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => OasisEntrance(
        index: index,
        child: _ConversationRow(conversation: conversations[index]),
      ),
    );
  }
}

/// A thread in the v2 inbox: the stay's photo, its name, when the last
/// message landed, and a line of it.
class _V2ConversationRow extends StatelessWidget {
  final Conversation conversation;

  const _V2ConversationRow({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final last = conversation.lastMessage;
    final title = conversation.propertyName.isNotEmpty
        ? conversation.propertyName
        : conversation.counterparty.displayName;
    final preview = last?.body ?? conversation.subjectLine;
    final when = v2InboxTime(last?.createdAt ?? conversation.createdAt);
    final unread = conversation.hasUnread;

    return InkWell(
      onTap: () => Navigator.push(
        context,
        FadePageRoute(page: ConversationScreen(conversation: conversation)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            V2ThreadAvatar(conversation: conversation, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.cardTitle(
                            context,
                          ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        when,
                        style: AppTheme.bodyText(
                          context,
                          color: unread
                              ? AppTheme.terracottaColor
                              : AppTheme.mutedTextColor(context),
                        ).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.status.isClosed
                              ? 'Closed · $preview'
                              : preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyText(
                            context,
                            color: unread
                                ? AppTheme.primaryTextColor(context)
                                : AppTheme.secondaryTextColor(context),
                          ).copyWith(fontSize: 14),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 10),
                        Semantics(
                          label: '${conversation.unreadCount} unread',
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppTheme.terracottaColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The stay's photo in a circle, or the other person's initial when the
/// thread has no photo.
class V2ThreadAvatar extends StatelessWidget {
  final Conversation conversation;
  final double size;

  const V2ThreadAvatar({
    super.key,
    required this.conversation,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final photo = conversation.propertyPhotoUrl.trim();
    if (photo.isNotEmpty) {
      return ClipOval(
        child: OasisNetworkImage(
          url: photo,
          width: size,
          height: size,
          placeholderIcon: Icons.holiday_village_outlined,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.vacantSurface(context),
        shape: BoxShape.circle,
      ),
      child: Text(
        conversation.counterparty.initial,
        style: AppTheme.cardTitle(
          context,
          color: AppTheme.terracottaColor,
        ).copyWith(fontSize: size * 0.36),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final Conversation conversation;

  const _ConversationRow({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final last = conversation.lastMessage;
    final isClosed = conversation.status.isClosed;

    return OasisPressable(
      onTap: () => Navigator.push(
        context,
        FadePageRoute(page: ConversationScreen(conversation: conversation)),
      ),
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(
            color: conversation.hasUnread
                ? AppTheme.actionColor.withValues(alpha: 0.4)
                : AppTheme.borderColor(context),
          ),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Monogram(counterparty: conversation.counterparty),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.counterparty.displayName,
                          style: AppTheme.cardTitle(context),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.actionColor,
                            borderRadius: AppTheme.cornerSm,
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: AppTheme.labelText(
                              context,
                              color: AppTheme.whiteColor,
                            ).copyWith(fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversation.subjectLine,
                    style: AppTheme.labelText(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (last != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      last.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyText(
                        context,
                        color: AppTheme.secondaryTextColor(context),
                      ),
                    ),
                  ],
                  if (isClosed) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Closed',
                      style: AppTheme.labelText(
                        context,
                        color: AppTheme.mutedTextColor(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Initial tile rather than a photo: the API deliberately exposes no avatars,
/// and a grey circle placeholder would just look like a missing image.
class _Monogram extends StatelessWidget {
  final Counterparty counterparty;

  const _Monogram({required this.counterparty});

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppTheme.profileColor.withValues(alpha: 0.14),
      borderRadius: AppTheme.cornerMd,
    ),
    child: Text(
      counterparty.initial,
      style: AppTheme.cardTitle(context, color: AppTheme.profileColor),
    ),
  );
}
