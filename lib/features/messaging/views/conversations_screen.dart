import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../controllers/messaging_controller.dart';
import '../models/conversation_models.dart';
import 'conversation_screen.dart';
import '../../../core/utils/fade_page_route.dart';

/// The message inbox.
///
/// There is no "new message" button, because there is no one to pick from: a
/// thread is created from an application or a tenancy, in the place where that
/// relationship already appears. This screen only lists what exists.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

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

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
        title: Text('Messages', style: AppTheme.cardTitle(context)),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _buildBody(context, controller),
      ),
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

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => OasisEntrance(
        index: index,
        child: _ConversationRow(conversation: conversations[index]),
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
