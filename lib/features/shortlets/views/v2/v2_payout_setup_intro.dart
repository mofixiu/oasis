import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/oasis_sheet.dart';
import '../../../../core/widgets/v2_ui.dart';

/// What a host sees on Payments before they have a bank account on file:
/// how getting paid works, then the one step that unlocks it.
///
/// Shown instead of the vault page rather than above it. A ₦0 balance, an
/// empty history and a Withdraw button that cannot work explain nothing to a
/// host who has not been paid yet; this does.
class V2PayoutSetupIntro extends StatelessWidget {
  final VoidCallback onSetUp;
  final VoidCallback onLater;

  /// Shows a way back, for the copy of Payments opened from Profile.
  final bool showBack;

  const V2PayoutSetupIntro({
    super.key,
    required this.onSetUp,
    required this.onLater,
    this.showBack = false,
  });

  static const _steps = [
    (
      Icons.event_available_outlined,
      'A guest books and pays',
      'You approve every request first. The guest pays Oasis, not you, so '
          'nobody hands over cash or a transfer at the door.',
    ),
    (
      Icons.shield_outlined,
      'Oasis holds the money',
      'It stays safe with Oasis through the stay. If something goes wrong, '
          'either side can raise it before the money moves.',
    ),
    (
      Icons.savings_outlined,
      'Paid into your vault',
      'Your payout lands in your Oasis vault 24 hours after checkout, unless '
          'the guest reports a problem first.',
    ),
    (
      Icons.account_balance_outlined,
      'Withdraw to your bank',
      'Move it to your bank whenever you like, protected by your vault PIN. '
          'This is the account you add now.',
    ),
  ];

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
    children: [
      if (showBack) ...[
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
      ],
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppTheme.terracottaColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.payments_outlined,
          size: 30,
          color: AppTheme.terracottaColor,
        ),
      ),
      const SizedBox(height: 18),
      Text('Get paid for your stays', style: V2PageHeader.titleStyle(context)),
      const SizedBox(height: 8),
      Text(
        'Add the bank account your payouts should go to. Here is how money '
        'moves on Oasis.',
        style: AppTheme.bodyText(context).copyWith(fontSize: 14),
      ),
      const SizedBox(height: 26),
      for (var i = 0; i < _steps.length; i++)
        _Step(
          number: i + 1,
          icon: _steps[i].$1,
          title: _steps[i].$2,
          body: _steps[i].$3,
          isLast: i == _steps.length - 1,
        ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 18,
              color: AppTheme.secondaryTextColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You only pick your bank and type the account number. The '
                'account name comes from your bank, so payouts cannot be sent '
                'to the wrong person.',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      OasisSheetButton(
        label: 'Add bank account',
        icon: Icons.account_balance_outlined,
        onPressed: onSetUp,
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: onLater,
          child: Text(
            'Not now',
            style: AppTheme.cardTitle(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        ),
      ),
    ],
  );
}

/// One numbered step, joined to the next by a line down the left.
class _Step extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final String body;
  final bool isLast;

  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor(context),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Icon(icon, size: 19, color: AppTheme.terracottaColor),
            ),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: AppTheme.borderColor(context),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$number. $title', style: AppTheme.cardTitle(context)),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTheme.bodyText(context).copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
