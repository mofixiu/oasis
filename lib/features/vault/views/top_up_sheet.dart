import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_sheet.dart';
import '../../../core/widgets/landa_toast.dart';
import '../controllers/vault_controller.dart';
import '../models/vault_models.dart';

/// Moves money from the tenant's card or bank into their vault.
///
/// This is the saving half of the tenant vault: rent is a large, infrequent
/// bill, so the vault exists to be filled a bit at a time and spent in one go
/// when the bill lands. Paying out of it is the other half, and lives on the
/// rent-due card.
///
/// The checkout is the same provider flow rent already uses, deliberately: a
/// tenant who has paid rent once has already seen this screen. As there, the
/// app never marks a top-up settled itself: checkout closing means a browser
/// went away, not that money moved, so the backend is asked every time.
class TopUpSheet extends StatefulWidget {
  /// What the tenant is saving towards, when they opened this from a rent
  /// bill. Pre-fills the amount and names the goal; null for a plain top-up.
  final String? targetAmount;

  /// Human label for [targetAmount], e.g. `'Rent · Unit 4B'`.
  final String? targetLabel;

  /// The agreement this money is being saved towards, when the sheet was
  /// opened from a particular bill. What lands in the vault is recorded
  /// against it, so a tenant renting two places sees two separate savings
  /// goals instead of one balance counted twice.
  final String? targetAgreementId;

  const TopUpSheet({
    super.key,
    this.targetAmount,
    this.targetLabel,
    this.targetAgreementId,
  });

  @override
  State<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<TopUpSheet> with WidgetsBindingObserver {
  final _amountController = TextEditingController();

  /// Set once checkout actually opened, so an unrelated app-resume (a
  /// notification, a phone call) does not fire a verify call.
  bool _hasOpenedCheckout = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // A shortfall is the common case: they are here because rent costs more
    // than the vault holds. Offer the difference, not the whole bill.
    final shortfall = _shortfall();
    if (shortfall != null) _amountController.text = shortfall;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_hasOpenedCheckout) return;
    // Provider checkout runs in an in-app browser with no redirect back into
    // Flutter, so returning to the app is the only signal we get that it
    // finished. Ask the backend rather than waiting for a manual tap.
    _verify(silent: true);
  }

  /// What is still missing to cover [TopUpSheet.targetAmount], as whole naira,
  /// or null when there is no target or the vault already covers it.
  String? _shortfall() {
    final target = widget.targetAmount;
    if (target == null) return null;
    final have = context.read<VaultController>().vault?.availableBalance;
    final missing = LandaCurrency.subtract(target, have ?? '0.00');
    if (missing == null || (LandaCurrency.minorUnits(missing) ?? 0) <= 0) {
      return null;
    }
    // Rounded up to the naira: nobody tops up ₦12,340.55, and a keypad
    // pre-filled with kobo invites a top-up a kobo short of the bill.
    final kobo = LandaCurrency.minorUnits(missing)!;
    return ((kobo + 99) ~/ 100).toString();
  }

  /// Digits only: what the API expects, before the decimal places are added.
  String get _rawAmount =>
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _hasAmount => (LandaCurrency.minorUnits(_rawAmount) ?? 0) > 0;

  Future<void> _submit() async {
    final controller = context.read<VaultController>();

    if (!_hasAmount) {
      LandaToast.error(context, 'Enter an amount to add.');
      return;
    }

    setState(() => _errorMessage = null);
    final topUp = await controller.startTopUp('$_rawAmount.00');
    if (!mounted) return;

    if (topUp == null) {
      setState(
        () => _errorMessage =
            controller.errorMessage ??
            'Could not start that top-up. Try again in a moment.',
      );
      return;
    }

    // Already settled: a saved card can clear without any checkout at all.
    if (topUp.status.isSettled) {
      await controller.loadVault();
      if (!mounted) return;
      _finish(topUp);
      return;
    }

    await _openCheckout(topUp);
  }

  Future<void> _openCheckout(VaultTopUp topUp) async {
    final url = topUp.authorizationUrl;
    final checkoutUri = url == null ? null : Uri.tryParse(url);
    if (checkoutUri == null || !checkoutUri.hasScheme) {
      setState(
        () => _errorMessage =
            'The backend did not return a valid checkout link for this '
            'top-up. Your money has not left your account.',
      );
      return;
    }

    // Keep checkout inside the app the way rent payment does, rather than
    // handing the user off to Safari and hoping they come back.
    final opened = await launchUrl(
      checkoutUri,
      mode: LaunchMode.inAppWebView,
      webViewConfiguration: const WebViewConfiguration(
        enableJavaScript: true,
        enableDomStorage: true,
      ),
    );
    if (!mounted) return;
    setState(() {
      _hasOpenedCheckout = opened;
      if (!opened) {
        _errorMessage = 'Unable to open checkout. Please try again.';
      }
    });
  }

  /// Asks the backend where the top-up got to.
  ///
  /// [silent] is the automatic check on app-resume: it still celebrates a
  /// settled top-up, but says nothing about one that is merely still pending,
  /// because that is a background poll rather than something the user asked
  /// for.
  Future<void> _verify({bool silent = false}) async {
    final controller = context.read<VaultController>();
    if (controller.isToppingUp) return;

    final verified = await controller.verifyTopUp();
    if (!mounted) return;

    if (verified == null) {
      if (!silent) {
        setState(
          () => _errorMessage =
              controller.errorMessage ??
              'Unable to confirm that top-up. Please try again.',
        );
      }
      return;
    }

    if (verified.status.isSettled) {
      _finish(verified);
      return;
    }
    if (silent) return;

    setState(
      () => _errorMessage = switch (verified.status) {
        TopUpStatus.pending || TopUpStatus.unknown =>
          'This top-up has not gone through yet. Finish checkout, then '
              'check again.',
        TopUpStatus.failed =>
          verified.failureReason.isEmpty
              ? 'That payment did not go through. You have not been charged.'
              : verified.failureReason,
        TopUpStatus.abandoned =>
          'Checkout was cancelled. Nothing has left your account.',
        TopUpStatus.succeeded => null,
      },
    );
  }

  void _finish(VaultTopUp topUp) {
    // Recorded only once the money is actually in. A top-up that never
    // settled must not show up as savings towards anything.
    final agreementId = widget.targetAgreementId;
    if (agreementId != null && agreementId.isNotEmpty) {
      context.read<VaultController>().setAside(
        agreementId: agreementId,
        amount: topUp.amount,
      );
    }

    Navigator.pop(context, true);
    LandaToast.success(
      context,
      widget.targetLabel == null
          ? '${LandaCurrency.format(topUp.amount)} added to your vault.'
          : '${LandaCurrency.format(topUp.amount)} added and set aside for '
                '${widget.targetLabel}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final vault = controller.vault;
    final awaitingCheckout =
        controller.pendingTopUp != null &&
        !(controller.pendingTopUp?.status.isSettled ?? false) &&
        _hasOpenedCheckout;

    return LandaSheet(
      icon: Icons.savings_outlined,
      title: 'Add money to your vault',
      subtitle: widget.targetLabel == null
          ? 'Save towards rent a bit at a time, then pay it in one tap.'
          : 'Top up now and pay ${widget.targetLabel} straight from your '
                'vault.',
      accent: AppTheme.successColor,
      footer: awaitingCheckout
          ? LandaSheetButton(
              label: 'I have completed checkout',
              icon: Icons.verified_outlined,
              isLoading: controller.isToppingUp,
              color: AppTheme.successColor,
              onPressed: () => _verify(),
            )
          : LandaSheetButton(
              label: _hasAmount
                  ? 'Add ${LandaCurrency.format('$_rawAmount.00')}'
                  : 'Add money',
              icon: Icons.arrow_downward_rounded,
              isLoading: controller.isToppingUp,
              color: AppTheme.successColor,
              onPressed: _hasAmount ? _submit : null,
            ),
      children: [
        _BalanceRow(
          balance: vault?.availableBalance ?? '0.00',
          target: widget.targetAmount,
          targetLabel: widget.targetLabel,
        ),
        const SizedBox(height: 18),

        const LandaFieldLabel('Amount'),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppTheme.screenTitle(context),
          decoration: landaInputDecoration(
            context,
            hint: '0',
            prefixIcon: Icons.payments_outlined,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        // Saving for rent means repeating the same few amounts, so they are
        // one tap rather than a keypad each time.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amount in const ['20000', '50000', '100000', '250000'])
              _QuickAmount(
                amount: amount,
                onTap: () => setState(() {
                  _amountController.text = amount;
                }),
              ),
          ],
        ),

        const SizedBox(height: 16),
        const _Notice(
          icon: Icons.lock_outline_rounded,
          message:
              'Money in your vault is yours. Spend it on rent, or withdraw it '
              'back to your bank whenever you like.',
        ),

        if (awaitingCheckout) ...[
          const SizedBox(height: 10),
          const _Notice(
            icon: Icons.schedule_rounded,
            message:
                'We check with your bank the moment you come back from '
                'checkout. Your balance updates once they confirm it.',
          ),
        ],

        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _Notice(
            icon: Icons.error_outline_rounded,
            message: _errorMessage!,
            tint: AppTheme.disputeColor,
          ),
        ],
      ],
    );
  }
}

/// What is in the vault now, and how far it is from the bill being saved for.
class _BalanceRow extends StatelessWidget {
  final String balance;
  final String? target;
  final String? targetLabel;

  const _BalanceRow({required this.balance, this.target, this.targetLabel});

  @override
  Widget build(BuildContext context) {
    final covered = target != null && LandaCurrency.covers(balance, target!);
    final shortfall = target == null || covered
        ? null
        : LandaCurrency.subtract(target!, balance);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'IN YOUR VAULT',
            style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
          ),
          const SizedBox(height: 2),
          Text(
            LandaCurrency.format(balance),
            style: AppTheme.sectionTitle(context),
          ),
          if (target != null) ...[
            const SizedBox(height: 8),
            Text(
              covered
                  ? 'Enough to cover ${targetLabel ?? 'this bill'}.'
                  : '${LandaCurrency.format(shortfall!)} short of '
                        '${targetLabel ?? 'this bill'} '
                        '(${LandaCurrency.format(target!)}).',
              style: AppTheme.labelText(
                context,
                color: covered
                    ? AppTheme.successColor
                    : AppTheme.secondaryTextColor(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAmount extends StatelessWidget {
  final String amount;
  final VoidCallback onTap;

  const _QuickAmount({required this.amount, required this.onTap});

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withValues(alpha: 0.08),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(
          color: AppTheme.successColor.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        LandaCurrency.format('$amount.00'),
        style: AppTheme.cardTitle(context, color: AppTheme.successColor),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color? tint;

  const _Notice({required this.icon, required this.message, this.tint});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: tint ?? AppTheme.mutedTextColor(context)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: AppTheme.labelText(
            context,
            color: tint ?? AppTheme.secondaryTextColor(context),
          ),
        ),
      ),
    ],
  );
}
