import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/landa_currency.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../agreements/controllers/agreement_controller.dart';
import '../../../auth/controllers/auth_controller.dart';
import '../../../payouts/controllers/payout_controller.dart';
import '../../controllers/vault_controller.dart';
import '../../models/vault_models.dart';
import '../top_up_sheet.dart';
import '../vault_ledger_screen.dart';
import '../withdraw_sheet.dart';
import '../../../../core/utils/fade_page_route.dart';
import '../../../../core/widgets/landa_animated_value.dart';

/// The user's money, at the top of the payments screen.
///
/// Both roles get one, because both roles have a vault: the card only changes
/// which way money is expected to move. A landlord's fills from escrow and
/// empties to their bank. A tenant's is savings: they top it up ahead of a
/// rent bill, pay out of it, and can pull it back to their bank if plans
/// change.
///
/// Deliberately renders its balance even when no payout account exists. The
/// whole point of holding money in a vault is that it no longer depends on
/// having set up a bank account first, so a missing account is a prompt on
/// the Withdraw action, never a barrier to seeing the balance.
class VaultBalanceCard extends StatelessWidget {
  const VaultBalanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final vault = controller.vault;
    // "Is a tenant", not "is not a landlord": an artisan is neither, and
    // topping up is a tenant-only endpoint.
    final isTenant = context.select<AuthController, bool>(
      (auth) => auth.currentRole.isTenant,
    );
    // Payout standing is not part of the vault payload, so it is read from
    // the controller that owns it rather than guessed at from the balance.
    final payoutVerified = context.watch<PayoutController>().isVerified;

    // First load, nothing cached: a skeleton block rather than a spinner, so
    // the card keeps its footprint and the page does not jump when it lands.
    if (vault == null) {
      return _VaultCardShell(
        child: controller.hasError
            ? _VaultUnavailable(message: controller.errorMessage)
            : const _BalancePlaceholder(),
      );
    }

    final blockedReason = _withdrawalBlockedReason(
      vault: vault,
      payoutVerified: payoutVerified,
      isTenant: isTenant,
    );

    return _VaultCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isTenant
                    ? Icons.savings_outlined
                    : Icons.account_balance_wallet_outlined,
                size: 16,
                color: AppTheme.whiteColor.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'VAULT BALANCE',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.whiteColor.withValues(alpha: 0.75),
                  ).copyWith(letterSpacing: 1.1),
                ),
              ),
              // History is a look-up, not an action, so it sits in the header
              // as a quiet link rather than competing with the buttons that
              // move money.
              _HistoryLink(
                onTap: () => Navigator.push(
                  context,
                  FadePageRoute(page: const VaultLedgerScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Tabular figures so a balance that changes does not shuffle its
          // digits sideways as it re-renders, and animated, because this is
          // the one number in the app somebody is looking straight at when it
          // changes. A top-up that simply replaces the figure between frames
          // reads as a redraw; this reads as money arriving.
          LandaAnimatedValue(
            value: LandaCurrency.format(vault.availableBalance),
            style: AppTheme.screenTitle(
              context,
              color: AppTheme.whiteColor,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 4),
          Text(
            _caption(vault, isTenant: isTenant),
            style: AppTheme.bodyText(
              context,
              color: AppTheme.whiteColor.withValues(alpha: 0.7),
            ),
          ),
          // How one balance is split across the bills it is being saved for.
          // Tenants only: a landlord's vault fills from escrow and is not
          // being saved towards anything.
          if (isTenant) const _SetAsideBreakdown(),

          const SizedBox(height: 18),
          Row(
            children: [
              // Adding money is the tenant's main move and leads the row.
              // A landlord never tops up: their vault fills from escrow.
              if (isTenant) ...[
                Expanded(
                  child: _VaultAction(
                    icon: Icons.add_rounded,
                    label: 'Add money',
                    emphasised: true,
                    onTap: () => openTopUpSheet(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _VaultAction(
                    icon: Icons.arrow_outward_rounded,
                    label: 'Withdraw',
                    onTap: () => openWithdrawSheet(context),
                  ),
                ),
              ] else
                Expanded(
                  child: _VaultAction(
                    icon: Icons.arrow_outward_rounded,
                    label: 'Withdraw',
                    emphasised: true,
                    onTap: () => openWithdrawSheet(context),
                  ),
                ),
            ],
          ),
          // Say why Withdraw will not get them anywhere before they tap it.
          // The tap still works: it opens the sheet that fixes the problem.
          if (blockedReason != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppTheme.whiteColor.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    blockedReason,
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.whiteColor.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The line under the balance. Money already on its way out is worth saying
  /// over anything else, whoever is looking.
  static String _caption(VaultSummary vault, {required bool isTenant}) {
    if (vault.hasPendingWithdrawal) {
      return '${LandaCurrency.format(vault.pendingWithdrawalBalance)} on its '
          'way to your bank';
    }
    return isTenant
        ? 'Save towards rent here, then pay it in one tap.'
        : 'Rent lands here when it leaves escrow.';
  }

  /// Why a withdrawal cannot go ahead, or null when it can.
  ///
  /// Two reasons, deliberately ordered: an empty vault is worth saying first,
  /// because telling someone to add a bank account for money they do not have
  /// yet is noise. For a tenant an empty vault is not worth saying at all:
  /// the card is already inviting them to add money, and "nothing to withdraw"
  /// under it reads as a fault rather than a starting point.
  static String? _withdrawalBlockedReason({
    required VaultSummary vault,
    required bool payoutVerified,
    required bool isTenant,
  }) {
    if (!vault.hasAvailableBalance) {
      return isTenant ? null : 'Nothing to withdraw yet.';
    }
    if (!payoutVerified) return 'Add a bank account to withdraw this.';
    return null;
  }
}

/// Opens the withdraw sheet with a fresh intent.
///
/// Shared rather than private because the vault ledger offers the same action
/// from its own screen, and both must start a new intent the same way: a
/// sheet that inherits the previous intent's idempotency key would be merged
/// with it server-side.
void openWithdrawSheet(BuildContext context) {
  context.read<VaultController>().beginWithdrawalIntent();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const WithdrawSheet(),
  );
}

/// Opens the top-up sheet with a fresh intent, optionally aimed at a bill.
///
/// Returns true when money actually landed in the vault, so a caller that was
/// gating something on the balance (the rent-due card, say) can re-check it.
Future<bool> openTopUpSheet(
  BuildContext context, {
  String? targetAmount,
  String? targetLabel,
  String? targetAgreementId,
}) async {
  context.read<VaultController>().beginTopUpIntent();
  final funded = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TopUpSheet(
      targetAmount: targetAmount,
      targetLabel: targetLabel,
      targetAgreementId: targetAgreementId,
    ),
  );
  return funded ?? false;
}

/// What the tenant has earmarked, bill by bill.
///
/// Shown as a plan rather than a set of pots, because that is what it is: one
/// balance, one backend, and nothing actually ring-fenced. The wording says so
/// where it could otherwise be read as separate accounts.
class _SetAsideBreakdown extends StatelessWidget {
  const _SetAsideBreakdown();

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultController>();
    final allocations = vault.allocations;
    if (allocations.isEmpty) return const SizedBox.shrink();

    final agreements = context.watch<AgreementController>().agreements;
    final rows = <({String label, String amount})>[];
    for (final id in allocations.agreementIds) {
      final amount = vault.setAsideFor(id);
      if ((LandaCurrency.minorUnits(amount) ?? 0) <= 0) continue;
      final agreement = agreements.where((a) => a.id == id).firstOrNull;
      rows.add((
        label: agreement == null || agreement.unitNumber.isEmpty
            ? 'A bill'
            : 'Unit ${agreement.unitNumber}',
        amount: amount,
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SET ASIDE FOR',
            style: AppTheme.labelText(
              context,
              color: AppTheme.whiteColor.withValues(alpha: 0.7),
            ).copyWith(letterSpacing: 1.1),
          ),
          const SizedBox(height: 6),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: AppTheme.labelText(
                        context,
                        color: AppTheme.whiteColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  Text(
                    LandaCurrency.format(row.amount),
                    style:
                        AppTheme.labelText(
                          context,
                          color: AppTheme.whiteColor,
                        ).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            // The one sentence that stops this reading as separate accounts.
            allocations.exceedsBalance(vault.availableBalance)
                ? 'Some of this was spent elsewhere, so the amounts have been '
                      'scaled to what is left.'
                : 'A plan, not separate accounts. Anything here can still be '
                      'spent on anything.',
            style: AppTheme.labelText(
              context,
              color: AppTheme.whiteColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card's chrome: a deep terracotta panel that marks this as the one place
/// on the screen holding money, distinct from the ledger rows beneath it.
class _VaultCardShell extends StatelessWidget {
  final Widget child;

  const _VaultCardShell({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.primaryColor,
      borderRadius: AppTheme.cornerLg,
      boxShadow: AppTheme.raisedShadow(context),
    ),
    child: child,
  );
}

class _HistoryLink extends StatelessWidget {
  final VoidCallback onTap;

  const _HistoryLink({required this.onTap});

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'History',
            style: AppTheme.labelText(
              context,
              color: AppTheme.whiteColor.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppTheme.whiteColor.withValues(alpha: 0.85),
          ),
        ],
      ),
    ),
  );
}

class _BalancePlaceholder extends StatelessWidget {
  const _BalancePlaceholder();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'VAULT BALANCE',
        style: AppTheme.labelText(
          context,
          color: AppTheme.whiteColor.withValues(alpha: 0.75),
        ).copyWith(letterSpacing: 1.1),
      ),
      const SizedBox(height: 14),
      Container(
        width: 160,
        height: 26,
        decoration: BoxDecoration(
          color: AppTheme.whiteColor.withValues(alpha: 0.18),
          borderRadius: AppTheme.cornerSm,
        ),
      ),
      const SizedBox(height: 10),
      Container(
        width: 200,
        height: 12,
        decoration: BoxDecoration(
          color: AppTheme.whiteColor.withValues(alpha: 0.12),
          borderRadius: AppTheme.cornerSm,
        ),
      ),
    ],
  );
}

/// Shown when the vault itself could not be loaded. Says so plainly instead of
/// rendering a zero balance, which would read as "your money is gone".
class _VaultUnavailable extends StatelessWidget {
  final String? message;

  const _VaultUnavailable({this.message});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'VAULT BALANCE',
        style: AppTheme.labelText(
          context,
          color: AppTheme.whiteColor.withValues(alpha: 0.75),
        ).copyWith(letterSpacing: 1.1),
      ),
      const SizedBox(height: 10),
      Text(
        'Balance unavailable',
        style: AppTheme.sectionTitle(context, color: AppTheme.whiteColor),
      ),
      const SizedBox(height: 4),
      Text(
        message ?? 'Pull down to try again.',
        style: AppTheme.bodyText(
          context,
          color: AppTheme.whiteColor.withValues(alpha: 0.7),
        ),
      ),
    ],
  );
}

class _VaultAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasised;
  final VoidCallback onTap;

  const _VaultAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: emphasised
            ? AppTheme.whiteColor
            : AppTheme.whiteColor.withValues(alpha: 0.14),
        borderRadius: AppTheme.cornerMd,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: emphasised ? AppTheme.primaryColor : AppTheme.whiteColor,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.cardTitle(
              context,
              color: emphasised ? AppTheme.primaryColor : AppTheme.whiteColor,
            ),
          ),
        ],
      ),
    ),
  );
}
