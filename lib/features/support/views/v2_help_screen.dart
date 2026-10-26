import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../../core/widgets/v2_ui.dart';
import '../services/support_service.dart';
import 'v2_support_message_sheet.dart';

/// Ways to reach Oasis, and answers to what guests ask most.
class V2HelpScreen extends StatefulWidget {
  const V2HelpScreen({super.key});

  @override
  State<V2HelpScreen> createState() => _V2HelpScreenState();
}

class _V2HelpScreenState extends State<V2HelpScreen> {
  AppConfig _config = AppConfig.buildTime;

  @override
  void initState() {
    super.initState();
    SupportService().getAppConfig().then((config) {
      if (mounted) setState(() => _config = config);
    });
  }

  Future<void> _open(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      OasisToast.error(context, 'Could not open that on this phone.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final whatsAppDigits = _config.supportWhatsApp.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    return V2StatusBar(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.paddingOf(context).bottom + 28,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: V2CircleButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  size: 40,
                  onTap: () => Navigator.maybePop(context),
                ),
              ),
              const SizedBox(height: 14),
              V2PageHeader(
                title: 'Help & support',
                subtitle: _config.supportHours.isEmpty
                    ? 'We’re here when something isn’t right.'
                    : 'We’re here ${_config.supportHours}.',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              _Card(
                children: [
                  _Row(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Send us a message',
                    subtitle: 'We reply by email',
                    onTap: () => showV2SupportMessageSheet(context),
                  ),
                  if (whatsAppDigits.isNotEmpty)
                    _Row(
                      icon: Icons.forum_outlined,
                      title: 'Chat on WhatsApp',
                      subtitle: _config.supportWhatsApp,
                      onTap: () =>
                          _open(Uri.https('wa.me', '/$whatsAppDigits')),
                    ),
                  if (_config.supportEmail.isNotEmpty)
                    _Row(
                      icon: Icons.mail_outline_rounded,
                      title: 'Email us',
                      subtitle: _config.supportEmail,
                      onTap: () => _open(
                        Uri(scheme: 'mailto', path: _config.supportEmail),
                      ),
                    ),
                  if (_config.supportPhone.isNotEmpty)
                    _Row(
                      icon: Icons.call_outlined,
                      title: 'Call us',
                      subtitle: _config.supportPhone,
                      onTap: () =>
                          _open(Uri(scheme: 'tel', path: _config.supportPhone)),
                    ),
                ],
              ),
              const SizedBox(height: 26),
              const V2SectionHeader(title: 'Common questions'),
              const SizedBox(height: 8),
              for (final (question, answer) in _faqs)
                _Faq(question: question, answer: answer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Each answer describes what the app actually does today.
const _faqs = [
  (
    'When am I charged for a shortlet?',
    'Not when you ask. Requesting dates holds nothing and charges nothing. '
        'Once the host approves, you have 24 hours to pay, from your vault '
        'or by card, and the booking is confirmed when payment goes through.',
  ),
  (
    'What is the caution fee?',
    'Some hosts ask for a refundable deposit. It is added to what you pay '
        'and returned 24 hours after checkout, unless the host reports '
        'damage.',
  ),
  (
    'How do cancellations work?',
    'Each shortlet has a cancellation policy (Flexible, Moderate, Strict or '
        'Non-refundable), shown before you book. When you cancel, Oasis '
        'confirms the exact refund before anything is final.',
  ),
  (
    'What is my vault?',
    'Your Oasis balance. Add money ahead of a trip, pay for a booking in one '
        'tap with your vault PIN, and withdraw to your bank account when you '
        'need to.',
  ),
  (
    'When do I get the address and check-in details?',
    'The host shares check-in details, such as gate codes and key pickup, '
        'once your booking is paid for. You can message your host from the '
        'trip at any time after that.',
  ),
  (
    'Something went wrong on my trip. What now?',
    'Open the trip and choose Report a problem, any time until 24 hours '
        'after checkout. The host’s payout is paused and your caution fee '
        'stays held while Oasis looks into it.',
  ),
];

class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0)
            Divider(height: 1, color: AppTheme.borderColor(context)),
          children[index],
        ],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppTheme.terracottaColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.cardTitle(context)),
                Text(
                  subtitle,
                  style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.mutedTextColor(context),
          ),
        ],
      ),
    ),
  );
}

class _Faq extends StatelessWidget {
  final String question;
  final String answer;

  const _Faq({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: AppTheme.terracottaColor,
        collapsedIconColor: AppTheme.mutedTextColor(context),
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        title: Text(question, style: AppTheme.cardTitle(context)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: AppTheme.bodyText(context).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    ),
  );
}
