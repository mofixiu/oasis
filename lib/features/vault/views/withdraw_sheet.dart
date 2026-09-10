import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../payouts/controllers/payout_controller.dart';
import '../../payouts/views/payout_account_screen.dart';
import '../controllers/vault_controller.dart';
import 'vault_pin_sheet.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/utils/oasis_input_formatters.dart';

/// Moves money from the vault to the user's own bank.
///
/// Serves both roles unchanged: it is the landlord's rent leaving the vault,
/// or a tenant pulling savings back out because plans changed. The money is
/// already theirs either way, so the sheet asks nothing about why.
///
/// This is the only place in the app that needs a payout account. If there
/// isn't one, the sheet does not refuse: it offers to set one up and comes
/// back.
///
/// There is no fee breakdown here: the backend does not quote one, and
/// inventing a figure the provider might not charge would be worse than
/// showing nothing.
class WithdrawSheet extends StatefulWidget {
  const WithdrawSheet({super.key});

  @override
  State<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<WithdrawSheet> {
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The sheet gates on payout standing, so make sure it is loaded rather
    // than relying on whichever screen happened to fetch it last.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final payout = context.read<PayoutController>();
      if (!payout.isVerified) payout.loadPayoutAccount();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// Digits only: what the API expects, before the decimal places are added.
  String get _rawAmount =>
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _hasAmount => _rawAmount.replaceAll(RegExp(r'^0+'), '').isNotEmpty;

  Future<void> _setupPayoutAccount() async {
    final added = await Navigator.push<bool>(
      context,
      FadePageRoute(
        page: const PayoutAccountScreen(
          blockedReason:
              'Add the account your vault balance should be paid into.',
        ),
      ),
    );
    if (!mounted || added != true) return;
    await context.read<VaultController>().loadVault();
  }

  Future<void> _submit() async {
    final controller = context.read<VaultController>();

    if (!_hasAmount) {
      OasisToast.error(context, 'Enter an amount to withdraw.');
      return;
    }

    final amount = '$_rawAmount.00';

    // The PIN is asked for last, once the amount is settled, so the sheet can
    // name the sum being confirmed. It is held only for this one call.
    final pin = await promptVaultPin(
      context,
      title: 'Confirm ${OasisCurrency.format(amount)}',
      subtitle: 'Enter your vault PIN to send this to your bank.',
      actionLabel: 'Withdraw ${OasisCurrency.format(amount)}',
    );
    if (!mounted || pin == null) return;

    final withdrawal = await controller.withdraw(amount, vaultPin: pin);
    if (!mounted) return;

    if (withdrawal == null) {
      // The backend owns the rules (balance, limits, PIN, provider health)
      // so its sentence is shown as written, with the PIN standing the
      // controller just re-read folded in around it.
      OasisToast.error(
        context,
        controller.describeFailedAttempt(
          controller.errorMessage ??
              'Could not start that withdrawal. Try again in a moment.',
        ),
      );
      return;
    }

    Navigator.pop(context);
    OasisToast.success(
      context,
      '${OasisCurrency.format(withdrawal.amount)} requested. '
      '${withdrawal.status.label}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final payout = context.watch<PayoutController>();
    final vault = controller.vault;
    final needsAccount = !payout.isVerified;

    return OasisSheet(
      icon: Icons.arrow_outward_rounded,
      title: 'Withdraw from vault',
      subtitle: needsAccount
          ? 'Add a bank account and your balance is on its way.'
          : 'Money leaves your vault straight away and reaches your bank '
                'shortly after.',
      accent: AppTheme.successColor,
      footer: needsAccount
          ? OasisSheetButton(
              label: 'Add bank account',
              icon: Icons.account_balance_outlined,
              onPressed: _setupPayoutAccount,
            )
          : OasisSheetButton(
              label: _hasAmount
                  ? 'Withdraw ${OasisCurrency.format('$_rawAmount.00')}'
                  : 'Withdraw',
              icon: Icons.arrow_outward_rounded,
              isLoading: controller.isWithdrawing,
              color: AppTheme.successColor,
              onPressed: _hasAmount ? _submit : null,
            ),
      children: [
        _AvailableRow(
          available: vault?.availableBalance ?? '0.00',
          onUseAll: vault == null || !vault.hasAvailableBalance
              ? null
              : () => setState(
                  () => _amountController.text =
                      OasisThousandsFormatter.groupAmount(
                        vault.availableBalance,
                      ),
                ),
        ),
        const SizedBox(height: 18),

        const OasisFieldLabel('Amount'),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: const [OasisThousandsFormatter()],
          enabled: !needsAccount,
          style: AppTheme.screenTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: '0',
            prefixIcon: Icons.payments_outlined,
          ),
          onChanged: (_) => setState(() {}),
        ),

        if (needsAccount) ...[
          const SizedBox(height: 14),
          const _Notice(
            icon: Icons.account_balance_outlined,
            message:
                'Add the bank account your balance should be paid into. Your '
                'money stays safe in the vault until then.',
          ),
        ] else ...[
          const SizedBox(height: 14),
          _Notice(
            icon: Icons.account_balance_outlined,
            message:
                'Paid into ${payout.account?.bankName ?? 'your bank'} '
                        '${payout.account?.accountNumber ?? ''}'
                    .trim(),
          ),
          const SizedBox(height: 10),
          const _Notice(
            icon: Icons.lock_outline_rounded,
            message: 'You will confirm this with your 4-digit vault PIN.',
          ),
          const SizedBox(height: 10),
          const _Notice(
            icon: Icons.schedule_rounded,
            message:
                'Withdrawals are reviewed before the transfer starts, so this '
                'may not arrive instantly.',
          ),
        ],

        if (vault != null && vault.hasPendingWithdrawal) ...[
          const SizedBox(height: 10),
          _Notice(
            icon: Icons.hourglass_top_outlined,
            message:
                '${OasisCurrency.format(vault.pendingWithdrawalBalance)} is '
                'already on its way and is not part of your available balance.',
          ),
        ],
      ],
    );
  }
}

/// What is withdrawable right now, with a shortcut to take all of it.
class _AvailableRow extends StatelessWidget {
  final String available;
  final VoidCallback? onUseAll;

  const _AvailableRow({required this.available, this.onUseAll});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: AppTheme.subtleSurfaceColor(context),
      borderRadius: AppTheme.cornerMd,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AVAILABLE',
                style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
              ),
              const SizedBox(height: 2),
              Text(
                OasisCurrency.format(available),
                style: AppTheme.sectionTitle(context),
              ),
            ],
          ),
        ),
        if (onUseAll != null)
          TextButton(
            onPressed: onUseAll,
            child: Text(
              'Use all',
              style: AppTheme.cardTitle(context, color: AppTheme.actionColor),
            ),
          ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String message;

  const _Notice({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: AppTheme.mutedTextColor(context)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
      ),
    ],
  );
}
