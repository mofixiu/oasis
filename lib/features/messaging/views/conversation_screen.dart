import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/app_variant.dart';

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
import '../../../core/utils/fade_page_route.dart';
import '../../shortlets/controllers/shortlet_controller.dart';
import '../../shortlets/models/shortlet_models.dart';
import '../../shortlets/views/v2/v2_booking_details_screen.dart';
import '../../shortlets/views/v2/v2_stay_widgets.dart';
import 'conversations_screen.dart';
import 'v2_message_time.dart';
import '../../support/views/v2_support_message_sheet.dart';
import '../../support/services/support_service.dart';
import '../../../core/widgets/oasis_toast.dart';
import 'package:url_launcher/url_launcher.dart';

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
      appBar: isOasisV2
          ? _v2AppBar(context, conversation)
          : AppBar(
              backgroundColor: AppTheme.pageBackground(context),
              elevation: 0,
              scrolledUnderElevation: 0,
              iconTheme: IconThemeData(
                color: AppTheme.primaryTextColor(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.counterparty.displayName,
                    style: AppTheme.cardTitle(context),
                  ),
                  Text(
                    conversation.subjectLine,
                    style: AppTheme.labelText(context),
                  ),
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

  /// The stay's photo and name, with who is on the other end underneath.
  PreferredSizeWidget _v2AppBar(
    BuildContext context,
    Conversation conversation,
  ) {
    final counterparty = conversation.counterparty;
    final role = switch (counterparty.role.toUpperCase()) {
      'OWNER' || 'LANDLORD' || 'HOST' => 'Host',
      'TENANT' || 'GUEST' => 'Guest',
      _ => '',
    };
    final title = conversation.propertyName.isNotEmpty
        ? conversation.propertyName
        : counterparty.displayName;
    final subtitle = conversation.propertyName.isNotEmpty
        ? [if (role.isNotEmpty) role, counterparty.displayName].join(' · ')
        : (role.isNotEmpty ? role : conversation.subjectLine);

    return AppBar(
      backgroundColor: AppTheme.pageBackground(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
      shape: Border(bottom: BorderSide(color: AppTheme.borderColor(context))),
      actions: [
        IconButton(
          tooltip: 'Booking details',
          onPressed: () => _showV2Details(context, conversation),
          icon: const Icon(Icons.more_horiz_rounded),
        ),
        const SizedBox(width: 4),
      ],
      title: Row(
        children: [
          V2ThreadAvatar(conversation: conversation, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.cardTitle(
                    context,
                  ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The shortlet this thread is about: photo, dates, guests, and the way to
  /// its booking.
  void _showV2Details(BuildContext context, Conversation conversation) {
    ShortLetBooking? booking;
    for (final candidate in context.read<ShortLetController>().bookings) {
      if (candidate.id == conversation.contextId) booking = candidate;
    }
    final place = conversation.propertyName.isNotEmpty
        ? conversation.propertyName
        : (booking?.title ?? conversation.counterparty.displayName);
    final address = booking?.address ?? '';
    final roleWord = switch (conversation.counterparty.role.toUpperCase()) {
      'TENANT' || 'GUEST' => 'guest',
      _ => 'host',
    };
    final phone = conversation.counterparty.phone.trim();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor(sheetContext),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusLg),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                V2StayPhoto(
                  url: conversation.propertyPhotoUrl,
                  height: 190,
                  // The conversation may simply not carry the photo.
                  listingKnown: false,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    18,
                    20,
                    MediaQuery.paddingOf(sheetContext).bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(place, style: AppTheme.sectionTitle(sheetContext)),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: AppTheme.secondaryTextColor(sheetContext),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.bodyText(sheetContext),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (booking != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.subtleSurfaceColor(sheetContext),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                                color: AppTheme.secondaryTextColor(
                                  sheetContext,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v2DateRange(booking),
                                      style: AppTheme.cardTitle(sheetContext),
                                    ),
                                    if (booking.nights > 0)
                                      Text(
                                        v2Plural(
                                          booking.nights,
                                          'night',
                                          'nights',
                                        ),
                                        style: AppTheme.bodyText(
                                          sheetContext,
                                        ).copyWith(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.people_outline_rounded,
                                size: 18,
                                color: AppTheme.secondaryTextColor(
                                  sheetContext,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                v2Plural(booking.guestCount, 'guest', 'guests'),
                                style: AppTheme.cardTitle(sheetContext),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.receipt_long_outlined,
                            color: AppTheme.primaryTextColor(sheetContext),
                          ),
                          title: Text(
                            'View booking details',
                            style: AppTheme.cardTitle(sheetContext),
                          ),
                          subtitle: Text(
                            'Dates, payment, check-in info',
                            style: AppTheme.bodyText(
                              sheetContext,
                            ).copyWith(fontSize: 12),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.mutedTextColor(sheetContext),
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            Navigator.push(
                              context,
                              FadePageRoute(
                                page: V2BookingDetailsScreen(booking: booking!),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 4),
                      _V2SheetRow(
                        icon: Icons.call_outlined,
                        title: 'Call $roleWord',
                        // The backend leaves the number blank until the
                        // booking is paid (API guide 20). Said as that,
                        // rather than as something missing.
                        subtitle: phone.isNotEmpty
                            ? phone
                            : booking == null
                            ? 'Shared once a booking is paid'
                            : booking.status.isPaid
                            ? 'Their number isn’t available'
                            : 'Shared once the booking is paid',
                        onTap: phone.isEmpty
                            ? null
                            : () => launchUrl(Uri(scheme: 'tel', path: phone)),
                      ),
                      _V2SheetRow(
                        icon: Icons.flag_outlined,
                        title: 'Report an issue',
                        subtitle: 'Tell the Oasis team what happened',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showV2SupportMessageSheet(
                            context,
                            title: 'Report an issue',
                            initialCategory: SupportCategory.safety,
                            shortLetBookingId: booking?.id,
                            conversationId: conversation.id,
                          );
                        },
                      ),
                      if (!conversation.status.isClosed) ...[
                        const SizedBox(height: 14),
                        V2DestructiveButton(
                          label: 'Block $roleWord',
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await _confirmBlock(
                              context,
                              conversation,
                              roleWord,
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Asks before blocking, then closes the thread.
  Future<void> _confirmBlock(
    BuildContext context,
    Conversation conversation,
    String roleWord,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: AppTheme.cornerLg),
        title: Text(
          'Block this $roleWord?',
          style: AppTheme.sectionTitle(dialogContext),
        ),
        content: Text(
          'They will not be able to message you, and this conversation '
          'becomes read-only. Your booking itself is not cancelled.',
          style: AppTheme.bodyText(dialogContext),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep talking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Block',
              style: AppTheme.cardTitle(
                dialogContext,
                color: AppTheme.disputeColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messaging = context.read<MessagingController>();
    final blocked = await messaging.blockConversation(conversation);
    if (!context.mounted) return;
    if (blocked) {
      OasisToast.success(context, 'Blocked. They can’t message you any more.');
    } else {
      OasisToast.error(
        context,
        messaging.errorMessage ?? 'Could not block them. Try again.',
      );
    }
  }

  /// Why the thread is read-only, in terms of the relationship that ended.
  String _closedNotice(Conversation conversation) {
    switch (conversation.context) {
      case ConversationContext.application:
        return 'This application is closed, so messages are read-only.';
      case ConversationContext.shortLet:
        return isOasisV2
            ? 'This booking is over, so messages are read-only.'
            : 'This stay is over, so messages are read-only.';
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
                  '${isOasisV2 ? 'booking' : 'stay'}.'
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
        final Widget line = message.isSystem
            ? _SystemLine(message: message)
            : _Bubble(
                message: message,
                isMine: message.isMine(myRole),
                onRetry: message.hasFailed
                    ? () => controller.retry(message)
                    : null,
              );
        if (!isOasisV2) return line;

        // A day label wherever the date changes, as in any messaging app.
        final day = v2LocalTime(message.createdAt);
        final previous = index == 0
            ? null
            : v2LocalTime(controller.messages[index - 1].createdAt);
        final startsDay =
            day != null &&
            (previous == null ||
                previous.year != day.year ||
                previous.month != day.month ||
                previous.day != day.day);
        if (!startsDay) return line;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
              child: Text(
                v2DayLabel(day),
                textAlign: TextAlign.center,
                style: AppTheme.bodyText(
                  context,
                  color: AppTheme.mutedTextColor(context),
                ).copyWith(fontSize: 12),
              ),
            ),
            line,
          ],
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

  /// White for theirs, terracotta for mine, with the time tucked inside.
  Widget _buildV2(BuildContext context) {
    final sentAt = v2LocalTime(message.createdAt);
    final foreground = isMine
        ? AppTheme.whiteColor
        : AppTheme.primaryTextColor(context);
    final meta = isMine
        ? AppTheme.whiteColor.withValues(alpha: 0.78)
        : AppTheme.mutedTextColor(context);
    const corner = Radius.circular(18);
    const tail = Radius.circular(6);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.76,
            ),
            child: Opacity(
              opacity: message.isPending ? 0.55 : 1,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  color: isMine
                      ? AppTheme.terracottaColor
                      : AppTheme.surfaceColor(context),
                  border: isMine
                      ? null
                      : Border.all(color: AppTheme.borderColor(context)),
                  borderRadius: BorderRadius.only(
                    topLeft: corner,
                    topRight: corner,
                    bottomLeft: isMine ? corner : tail,
                    bottomRight: isMine ? tail : corner,
                  ),
                ),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        message.body,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (sentAt != null)
                            Text(
                              DateFormat('h:mm a').format(sentAt),
                              style: TextStyle(color: meta, fontSize: 11),
                            ),
                          if (isMine && !message.isPending) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.isRead
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                              size: 14,
                              color: meta,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (message.hasFailed)
            OasisPressable(
              onTap: onRetry,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Text(
                  'Not sent. Tap to retry',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.disputeColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isOasisV2) return _buildV2(context);
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

  /// A rounded field and a round send button, as in the v2 mockups.
  Widget _buildV2(BuildContext context, double bottomInset) => Container(
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
            style: AppTheme.bodyText(
              context,
              color: AppTheme.primaryTextColor(context),
            ).copyWith(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Type a message…',
              hintStyle: AppTheme.bodyText(
                context,
                color: AppTheme.mutedTextColor(context),
              ).copyWith(fontSize: 15),
              counterText: '',
              filled: true,
              fillColor: AppTheme.subtleSurfaceColor(context),
              contentPadding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Send',
          child: OasisPressable(
            onTap: isSending ? null : onSend,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppTheme.terracottaColor,
                shape: BoxShape.circle,
              ),
              child: isSending
                  ? const Padding(
                      padding: EdgeInsets.all(17),
                      child: OasisBusyDots(color: AppTheme.whiteColor),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      size: 20,
                      color: AppTheme.whiteColor,
                    ),
            ),
          ),
        ),
      ],
    ),
  );

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

    if (isOasisV2) return _buildV2(context, bottomInset);

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

/// A tappable line in the conversation details sheet.
class _V2SheetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _V2SheetRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    enabled: onTap != null,
    onTap: onTap,
    leading: Icon(icon, color: AppTheme.primaryTextColor(context)),
    title: Text(title, style: AppTheme.cardTitle(context)),
    subtitle: Text(
      subtitle,
      style: AppTheme.bodyText(context).copyWith(fontSize: 12),
    ),
    trailing: onTap == null
        ? null
        : Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.mutedTextColor(context),
          ),
  );
}
