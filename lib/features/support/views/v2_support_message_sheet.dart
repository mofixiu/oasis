import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../services/support_service.dart';

/// Opens the "send us a message" sheet. Pass a booking or conversation when
/// the message is about one, so support can see which.
Future<void> showV2SupportMessageSheet(
  BuildContext context, {
  String title = 'Send us a message',
  SupportCategory initialCategory = SupportCategory.booking,
  String? shortLetBookingId,
  String? conversationId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _SupportMessageSheet(
    title: title,
    initialCategory: initialCategory,
    shortLetBookingId: shortLetBookingId,
    conversationId: conversationId,
  ),
);

class _SupportMessageSheet extends StatefulWidget {
  final String title;
  final SupportCategory initialCategory;
  final String? shortLetBookingId;
  final String? conversationId;

  const _SupportMessageSheet({
    required this.title,
    required this.initialCategory,
    this.shortLetBookingId,
    this.conversationId,
  });

  @override
  State<_SupportMessageSheet> createState() => _SupportMessageSheetState();
}

class _SupportMessageSheetState extends State<_SupportMessageSheet> {
  final _service = SupportService();
  final _message = TextEditingController();
  late SupportCategory _category = widget.initialCategory;
  bool _isSending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.length < 10) {
      OasisToast.error(context, 'Tell us a little more so we can help.');
      return;
    }
    setState(() => _isSending = true);
    try {
      final reference = await _service.createTicket(
        category: _category,
        message: text,
        shortLetBookingId: widget.shortLetBookingId,
        conversationId: widget.conversationId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      OasisToast.success(
        context,
        reference == null
            ? 'Sent. We’ll reply by email.'
            : 'Sent (ref $reference). We’ll reply by email.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 404) {
        await _fallBackToEmail(text);
      } else {
        OasisToast.error(context, error.message);
      }
    } catch (_) {
      if (!mounted) return;
      OasisToast.error(context, 'Could not send that. Try again in a moment.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Until support messages ship, hand the text to the mail app when a
  /// support address is known.
  Future<void> _fallBackToEmail(String text) async {
    final config = await _service.getAppConfig();
    if (!mounted) return;
    if (config.supportEmail.isEmpty) {
      OasisToast.error(
        context,
        'Messaging support is not available yet. Please try again later.',
      );
      return;
    }
    final details = [
      if (widget.shortLetBookingId != null)
        'Booking: ${widget.shortLetBookingId}',
      if (widget.conversationId != null)
        'Conversation: ${widget.conversationId}',
    ].join('\n');
    final uri = Uri(
      scheme: 'mailto',
      path: config.supportEmail,
      query: _encodeQuery({
        'subject': 'Oasis support: ${_category.label}',
        'body': details.isEmpty ? text : '$text\n\n$details',
      }),
    );
    await launchUrl(uri);
    if (mounted) Navigator.pop(context);
  }

  static String _encodeQuery(Map<String, String> params) => params.entries
      .map(
        (entry) =>
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
      )
      .join('&');

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.mutedTextColor(context).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.title, style: AppTheme.sectionTitle(context)),
          const SizedBox(height: 4),
          Text(
            'The Oasis team reads every message and replies by email.',
            style: AppTheme.bodyText(context),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in SupportCategory.values)
                OasisPressable(
                  onTap: () => setState(() => _category = category),
                  pressedScale: 0.96,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: category == _category
                          ? AppTheme.terracottaColor
                          : AppTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: category == _category
                            ? AppTheme.terracottaColor
                            : AppTheme.borderColor(context),
                      ),
                    ),
                    child: Text(
                      category.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: category == _category
                            ? Colors.white
                            : AppTheme.primaryTextColor(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurfaceColor(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _message,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: AppTheme.bodyText(
                context,
                color: AppTheme.primaryTextColor(context),
              ).copyWith(fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'What happened? Include dates and names if you can.',
                hintStyle: AppTheme.bodyText(
                  context,
                  color: AppTheme.mutedTextColor(context),
                ).copyWith(fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 16),
          OasisButton(
            label: 'Send',
            icon: Icons.send_rounded,
            isBusy: _isSending,
            onPressed: _isSending ? null : _send,
          ),
        ],
      ),
    ),
  );
}
