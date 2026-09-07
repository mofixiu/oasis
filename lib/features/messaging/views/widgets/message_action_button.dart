import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../controllers/messaging_controller.dart';
import '../conversation_screen.dart';
import '../../../../core/utils/fade_page_route.dart';
import '../../../../core/widgets/landa_busy.dart';

/// Starts (or re-opens) the conversation attached to a relationship, then
/// opens it.
///
/// Placed on the thing the conversation is about (an application, a tenancy)
/// rather than behind a compose button in the inbox. That is the whole shape
/// of the feature: you cannot message a person, only the counterparty of a
/// live application or tenancy, so the button lives where that relationship is
/// already on screen.
class MessageActionButton extends StatefulWidget {
  /// Exactly one of these identifies the relationship. A landlord must supply
  /// an application or agreement, since a unit can have several applicants.
  final String? applicationId;
  final String? agreementId;
  final String? unitId;

  /// A paid short-let booking. The backend only opens a thread once the stay
  /// is paid for, so a guest and host who have only exchanged a request have
  /// no channel, which is deliberate, and why callers gate the button on the
  /// booking's `canMessage` rather than showing a button that fails.
  final String? shortLetBookingId;

  final String label;

  /// Renders as a full-width outlined button instead of a compact chip.
  final bool expanded;

  const MessageActionButton({
    super.key,
    this.applicationId,
    this.agreementId,
    this.unitId,
    this.shortLetBookingId,
    this.label = 'Message',
    this.expanded = false,
  });

  @override
  State<MessageActionButton> createState() => _MessageActionButtonState();
}

class _MessageActionButtonState extends State<MessageActionButton> {
  bool _isOpening = false;

  Future<void> _open() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);

    final controller = context.read<MessagingController>();
    final conversation = await controller.startConversation(
      applicationId: widget.applicationId,
      agreementId: widget.agreementId,
      unitId: widget.unitId,
      shortLetBookingId: widget.shortLetBookingId,
    );

    if (!mounted) return;
    setState(() => _isOpening = false);

    if (conversation == null) {
      // The refusals here are already sentences worth reading: "You can only
      // message a landlord after applying for one of their units", so the
      // backend's own wording is shown rather than a generic failure.
      LandaToast.error(
        context,
        controller.errorMessage ??
            'Could not open that conversation. Try again in a moment.',
      );
      return;
    }

    Navigator.push(
      context,
      FadePageRoute(page: ConversationScreen(conversation: conversation)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isOpening)
          const LandaBusyDots(color: AppTheme.actionColor)
        else
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 16,
            color: AppTheme.actionColor,
          ),
        const SizedBox(width: 8),
        Text(
          widget.label,
          style: AppTheme.cardTitle(context, color: AppTheme.actionColor),
        ),
      ],
    );

    return LandaPressable(
      onTap: _isOpening ? null : _open,
      child: Container(
        width: widget.expanded ? double.infinity : null,
        height: 42,
        padding: EdgeInsets.symmetric(horizontal: widget.expanded ? 0 : 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.actionColor.withValues(alpha: 0.08),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(
            color: AppTheme.actionColor.withValues(alpha: 0.3),
          ),
        ),
        child: child,
      ),
    );
  }
}
