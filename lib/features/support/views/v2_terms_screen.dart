import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../../core/widgets/v2_ui.dart';
import '../../shortlets/models/shortlet_models.dart';
import '../services/support_service.dart';

/// The legal documents, which are published elsewhere and linked from the
/// app config, and the booking policies the app itself enforces.
class V2TermsScreen extends StatefulWidget {
  const V2TermsScreen({super.key});

  @override
  State<V2TermsScreen> createState() => _V2TermsScreenState();
}

class _V2TermsScreenState extends State<V2TermsScreen> {
  AppConfig _config = AppConfig.buildTime;

  @override
  void initState() {
    super.initState();
    SupportService().getAppConfig().then((config) {
      if (mounted) setState(() => _config = config);
    });
  }

  Future<void> _openDocument(String url) async {
    final uri = Uri.tryParse(url);
    final opened =
        uri != null && await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened && mounted) {
      OasisToast.error(context, 'Could not open that document.');
    }
  }

  void _showPolicySheet(String title, List<(String, String)> sections) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor(sheetContext),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusLg),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.paddingOf(sheetContext).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AppTheme.sectionTitle(sheetContext)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (heading, body) in sections) ...[
                        Text(heading, style: AppTheme.cardTitle(sheetContext)),
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: AppTheme.bodyText(
                            sheetContext,
                          ).copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => V2StatusBar(
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
            const V2PageHeader(
              title: 'Terms & policies',
              subtitle: 'The rules that apply when you book with Oasis.',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 20),
            _DocumentRow(
              icon: Icons.description_outlined,
              title: 'Terms of service',
              url: _config.termsUrl,
              onOpen: _openDocument,
            ),
            _DocumentRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              url: _config.privacyUrl,
              onOpen: _openDocument,
            ),
            _PolicyRow(
              icon: Icons.event_busy_outlined,
              title: 'Cancellation policies',
              subtitle: 'What each policy refunds',
              onTap: () => _showPolicySheet('Cancellation policies', [
                for (final policy in ShortLetCancellationPolicy.values)
                  (policy.label, policy.defaultSummary),
                (
                  'Your exact refund',
                  'Oasis confirms the amount when you cancel, before '
                      'anything is final.',
                ),
              ]),
            ),
            _PolicyRow(
              icon: Icons.shield_outlined,
              title: 'Caution fees',
              subtitle: 'Refundable deposits',
              showDivider: false,
              onTap: () => _showPolicySheet('Caution fees', const [
                (
                  'What it is',
                  'Some hosts ask for a refundable deposit. It is shown on '
                      'the shortlet before you book and added to what you pay.',
                ),
                (
                  'When it comes back',
                  'It is returned after checkout, unless the host reports '
                      'damage.',
                ),
                (
                  'If there is a problem',
                  'If you report a problem with your booking, the caution fee '
                      'stays held while Oasis looks into it.',
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DocumentRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String url;
  final ValueChanged<String> onOpen;

  const _DocumentRow({
    required this.icon,
    required this.title,
    required this.url,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => _PolicyRow(
    icon: icon,
    title: title,
    subtitle: url.isEmpty ? 'Coming soon' : 'Opens in your browser',
    onTap: url.isEmpty ? null : () => onOpen(url),
  );
}

class _PolicyRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool showDivider;

  const _PolicyRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.borderColor(context)),
              ),
            )
          : null,
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: onTap == null
                ? AppTheme.mutedTextColor(context)
                : AppTheme.primaryTextColor(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.cardTitle(
                    context,
                    color: onTap == null
                        ? AppTheme.mutedTextColor(context)
                        : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.mutedTextColor(context),
            ),
        ],
      ),
    ),
  );
}
