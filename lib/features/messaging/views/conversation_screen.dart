import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../../core/widgets/oasis_popup_notification.dart';
import '../controllers/messaging_controller.dart';
import '../models/conversation_models.dart';
import '../../../core/widgets/oasis_busy.dart';
import '../../../core/widgets/oasis_shimmer.dart';

/// One thread between a landlord and a tenant.
///
/// Messages land here over the realtime socket. The fallback poll is armed
/// alongside it and only does work while the socket is down; either way it
/// stops the moment the screen is left, because an inbox that keeps polling
/// in the background is how a chat feature quietly becomes the most expensive
/// thing in the app.
///
/// Popups are suppressed for as long as this screen is open: a banner
/// announcing a message that is arriving in the thread the user is watching
/// is an interruption about something already on screen.
class ConversationScreen extends StatefulWidget {
  final Conversation conversation;

  const ConversationScreen({super.key, required this.conversation});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();

  /// How many bubbles were on screen last build, so a message arriving over
  /// the socket can scroll itself into view.
  int _renderedMessageCount = 0;

  /// Held rather than read from `context` when the screen is closing.
  ///
  /// Every teardown path here runs at a point where an ancestor lookup is
  /// either unsafe or impossible: `dispose` after the element is detached,
  /// and a lifecycle callback that can fire between the two. The controller
  /// is a process-wide singleton that outlives this screen many times over,
  /// so holding the reference is both safe and the only thing that is.
  late final MessagingController _messaging;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messaging = context.read<MessagingController>();
    OasisPopups.suppress();
    // Post-frame, not inline: openConversation notifies its listeners
    // immediately, and notifying a provider during the first build throws.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = context.read<MessagingController>();
      await controller.openConversation(widget.conversation);
      if (!mounted) return;
      controller.startPolling();
      _scrollToLatest();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OasisPopups.resume();
    // Closed here rather than in `deactivate`, which is where it used to be.
    // `deactivate` runs while the route is still animating out, so clearing
    // the thread there made the screen repaint itself empty on the way off
    // the stack: the user's last sight of a conversation was it emptying.
    _messaging.closeConversation();
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Backgrounding the app should not keep a poll timer alive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _messaging.startPolling();
    } else {
      _messaging.stopPolling();
    }
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  /// Follows a message that arrived while the thread was open, but only if
  /// the user was already at the bottom.
  ///
  /// Someone scrolled up reading yesterday's messages has not asked to be
  /// yanked to the end because the other party is typing; the new bubble is
  /// still there when they scroll back down.
  void _followIfAtBottom() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels > 120) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToLatest();
    });
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;

    _composerController.clear();
    await context.read<MessagingController>().sendMessage(text);
    if (!mounted) return;
    // After the frame, so the new bubble is laid out before we scroll to it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MessagingController>();
    final conversation = controller.activeConversation ?? widget.conversation;
    if (controller.messages.length > _renderedMessageCount) _followIfAtBottom();
    _renderedMessageCount = controller.messages.length;
    final isLandlord =
        context.watch<AuthController>().currentRole == UserRole.owner;
    final myRole = isLandlord ? 'OWNER' : 'TENANT';

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conversation.counterparty.displayName,
              style: AppTheme.cardTitle(context),
            ),
            Text(conversation.subjectLine, style: AppTheme.labelText(context)),
          ],
        ),
      ),
      // `bottom: false` deliberately: the composer sits flush against the
      // bottom edge and absorbs the home-indicator inset into its own padding.
      // Letting SafeArea do it instead leaves a dead strip of page background
      // below the composer.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (controller.hasError && controller.messages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OasisErrorBanner(
                  message: controller.errorMessage!,
                  isConnectionError: controller.errorIsConnection,
                ),
              ),
            Expanded(child: _buildThread(context, controller, myRole)),
            _Composer(
              controller: _composerController,
              enabled: !conversation.status.isClosed,
              isSending: controller.isSending,
              closedNotice: conversation.status.isClosed
                  ? _closedNotice(conversation)
                  : null,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }

  /// Why the thread is read-only, in terms of the relationship that ended.
  String _closedNotice(Conversation conversation) {
    switch (conversation.context) {
      case ConversationContext.application:
        return 'This application is closed, so messages are read-only.';
      case ConversationContext.shortLet:
        return 'This stay is over, so messages are read-only.';
      case ConversationContext.tenancy:
      case ConversationContext.unknown:
        return 'This tenancy has ended, so messages are read-only.';
    }
  }

  Widget _buildThread(
    BuildContext context,
    MessagingController controller,
    String myRole,
  ) {
    // "Not fetched yet" and "fetched, and the thread is genuinely empty" are
    // different states and used to render the same way: `isLoading` is false
    // *before* the post-frame fetch starts, so the first frame matched the
    // empty branch and the screen greeted the user with "Say hello" over a
    // thread that had forty messages in it.
    if (!controller.hasLoaded(MessagingController.kThreadKey) ||
        (controller.isLoading && controller.messages.isEmpty)) {
      // Message-shaped, not a wheel in the middle of an empty screen: the
      // thread is about to be a column of bubbles, so that is what waits here.
      return const OasisSkeletonList(count: 4, padding: EdgeInsets.all(16));
    }

    if (controller.hasError && controller.messages.isEmpty) {
      return OasisErrorState(
        message: controller.errorMessage,
        isConnectionError: controller.errorIsConnection,
        onRetry: () =>
            controller.openConversation(controller.activeConversation!),
      );
    }

    if (controller.messages.isEmpty) {
      final isStay =
          controller.activeConversation?.context ==
          ConversationContext.shortLet;
      return OasisEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Say hello',
        message: isStay
            // A stay thread opens the moment money moves, and the guest
            // usually has exactly two questions. Naming them beats a blank
            // box: it is faster to answer a prompt than to compose one.
            ? 'Arrange the practical bits: what time you are arriving, where '
                  'the key is, the gate code. Messages stay attached to this '
                  'stay.'
            : 'Ask about the unit, arrange a viewing, or sort out something '
                  'in the property. Messages stay attached to this unit.',
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: controller.messages.length,
      itemBuilder: (context, index) {
        final message = controller.messages[index];
        if (message.isSystem) return _SystemLine(message: message);
        return _Bubble(
          message: message,
          isMine: message.isMine(myRole),
          onRetry: message.hasFailed ? () => controller.retry(message) : null,
        );
      },
    );
  }
}

/// A message from one of the two people in the thread.
class _Bubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final VoidCallback? onRetry;

  const _Bubble({required this.message, required this.isMine, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDarkMode(context);
    final mineColor = AppTheme.actionColor;
    final theirsColor = isDark
        ? AppTheme.subtleSurfaceColor(context)
        : AppTheme.surfaceColor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // A pending message is dimmed rather than hidden, so what was
                // typed is always visible even on a bad connection.
                Opacity(
                  opacity: message.isPending ? 0.55 : 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isMine ? mineColor : theirsColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(AppTheme.radiusMd),
                        topRight: const Radius.circular(AppTheme.radiusMd),
                        bottomLeft: Radius.circular(
                          isMine ? AppTheme.radiusMd : AppTheme.radiusSm,
                        ),
                        bottomRight: Radius.circular(
                          isMine ? AppTheme.radiusSm : AppTheme.radiusMd,
                        ),
                      ),
                      border: isMine
                          ? null
                          : Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: Text(
                      message.body,
                      style: AppTheme.bodyText(
                        context,
                        color: isMine
                            ? AppTheme.whiteColor
                            : AppTheme.primaryTextColor(context),
                      ),
                    ),
                  ),
                ),
                if (message.hasFailed)
                  OasisPressable(
                    onTap: onRetry,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 13,
                            color: AppTheme.disputeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Not sent. Tap to retry',
                            style: AppTheme.labelText(
                              context,
                              color: AppTheme.disputeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A backend-written line marking what happened to the relationship.
///
/// Centred and unbubbled, because nobody said it: it is the thread's spine,
/// the same way "your driver has arrived" sits inside a ride's chat.
class _SystemLine extends StatelessWidget {
  final Message message;

  const _SystemLine({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerSm,
        ),
        child: Text(
          message.body,
          textAlign: TextAlign.center,
          style: AppTheme.labelText(context),
        ),
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final String? closedNotice;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.enabled,
    required this.isSending,
    required this.onSend,
    this.closedNotice,
  });

  @override
  Widget build(BuildContext context) {
    // Space taken by the home indicator. Goes to zero while the keyboard is
    // up: MediaQuery.padding is viewPadding minus whatever the keyboard has
    // already consumed, so the composer hugs the keyboard rather than
    // floating above it.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    if (!enabled) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottomInset),
        color: AppTheme.subtleSurfaceColor(context),
        child: Text(
          closedNotice ?? 'This conversation is read-only.',
          textAlign: TextAlign.center,
          style: AppTheme.labelText(context),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        border: Border(top: BorderSide(color: AppTheme.borderColor(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              style: AppTheme.bodyText(context),
              decoration: oasisInputDecoration(context, hint: 'Write a message')
                  .copyWith(
                    counterText: '',
                    // Tighter than the shared form padding so the field matches
                    // the send button's height instead of dwarfing it.
                    contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  ),
            ),
          ),
          const SizedBox(width: 10),
          OasisPressable(
            onTap: isSending ? null : onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.actionColor,
                borderRadius: AppTheme.cornerMd,
              ),
              child: isSending
                  ? const Padding(
                      padding: EdgeInsets.all(17),
                      child: OasisBusyDots(color: AppTheme.whiteColor),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      size: 19,
                      color: AppTheme.whiteColor,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
