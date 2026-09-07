import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/landa_currency.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../../agreements/models/agreement_model.dart';
import '../../../agreements/views/tenancy_agreement_modal.dart';
import '../../../vault/controllers/vault_controller.dart';
import '../../../vault/views/vault_pin_sheet.dart';
import '../../../vault/views/widgets/vault_balance_card.dart';
import '../../controllers/payment_controller.dart';
import '../payment_receipt_modal.dart';
import '../../../../core/widgets/landa_busy.dart';

/// One rent bill: what it costs, when it is due, and how to settle it.
///
/// Used both on the payments screen, where every card is payable now, and on
/// the tenant dashboard, where the point is the opposite: rent that is *not*
/// due yet, so the tenant can see the date coming and save into their vault
/// before it arrives.
///
/// The two states are deliberately the same card rather than two designs. A
/// tenant should recognise the bill they have been saving towards as the same
/// object on the day it becomes payable.
class RentDueCard extends StatelessWidget {
  final TenancyAgreementModel agreement;

  /// Called after money moves, so the screen can refetch. Payment status,
  /// vault balance and the schedule all change together and none of it is
  /// safe to guess locally.
  final Future<void> Function()? onPaid;

  const RentDueCard({super.key, required this.agreement, this.onPaid});

  @override
  Widget build(BuildContext context) {
    final schedule = agreement.upcomingRent;
    final amountDue = schedule?.nextAmountDue ?? agreement.rentAmount;
    // "Payable" is the agreement's own lock plus the schedule saying the bill
    // has actually landed. A date in the future is something to save for, not
    // something to pay.
    final payableNow = agreement.canPayRent && (schedule?.isDueNow ?? false);

    final vault = context.watch<VaultController>();
    final vaultCovers = vault.canCover(amountDue);
    final paying = context.select<PaymentController, bool>(
      (c) => c.isPayingFromVault,
    );

    final unitLabel = agreement.unitNumber.isEmpty
        ? 'Your unit'
        : 'Unit ${agreement.unitNumber}';
    final propertyName = agreement.property?.name;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(
          color: payableNow
              ? AppTheme.actionColor.withValues(alpha: 0.35)
              : AppTheme.borderColor(context),
        ),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  propertyName == null || propertyName.isEmpty
                      ? unitLabel
                      : '$propertyName · $unitLabel',
                  style: AppTheme.cardTitle(context),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                LandaCurrency.format(amountDue),
                style: AppTheme.cardTitle(context, color: AppTheme.actionColor),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (schedule != null)
            _DuePill(schedule: schedule)
          else
            Text(
              'Signed and ready. Rent is held in escrow until you confirm you '
              'have moved in.',
              style: AppTheme.bodyText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),

          // Only worth showing while they are still saving. Once the vault
          // covers the bill the button below says so more usefully.
          //
          // Measured against what has been set aside for *this* unit, not the
          // whole balance: a tenant renting two places would otherwise see the
          // same money counted towards both bills.
          if (!vaultCovers) ...[
            const SizedBox(height: 12),
            _SavingProgress(
              saved: vault.setAsideFor(agreement.id),
              target: amountDue,
            ),
          ],

          const SizedBox(height: 14),
          ..._actions(
            context,
            amountDue: amountDue,
            payableNow: payableNow,
            vaultCovers: vaultCovers,
            isPaying: paying,
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context, {
    required String amountDue,
    required bool payableNow,
    required bool vaultCovers,
    required bool isPaying,
  }) {
    // Not due yet: the only thing to do is get ahead of it.
    if (!payableNow) {
      return [
        _CardButton(
          label: 'Add to vault',
          icon: Icons.savings_outlined,
          outlined: true,
          onPressed: () => _topUp(context, amountDue),
        ),
      ];
    }

    // Money already inside Landa settles in one tap and no checkout, so when
    // the vault covers the bill, that is the offer, with the card route kept
    // as a quiet alternative rather than removed.
    if (vaultCovers) {
      return [
        _CardButton(
          label: 'Pay ${LandaCurrency.format(amountDue)} from vault',
          icon: Icons.account_balance_wallet_outlined,
          isLoading: isPaying,
          onPressed: isPaying ? null : () => _payFromVault(context, amountDue),
        ),
        const SizedBox(height: 8),
        Center(
          child: LandaPressable(
            onTap: () => _payWithCard(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Text(
                'Pay with card instead',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      _CardButton(
        label: 'Pay rent into escrow',
        icon: Icons.payments_outlined,
        onPressed: () => _payWithCard(context),
      ),
      const SizedBox(height: 8),
      _CardButton(
        label: 'Add to vault',
        icon: Icons.savings_outlined,
        outlined: true,
        onPressed: () => _topUp(context, amountDue),
      ),
    ];
  }

  /// Opens the agreement sheet, which owns the provider checkout flow.
  void _payWithCard(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ViewAgreementModal(agreement: agreement),
  );

  Future<void> _topUp(BuildContext context, String amountDue) async {
    final unitLabel = agreement.unitNumber.isEmpty
        ? 'rent'
        : 'rent · Unit ${agreement.unitNumber}';
    final funded = await openTopUpSheet(
      context,
      targetAmount: amountDue,
      targetLabel: unitLabel,
      // Money added from this card is money meant for this bill.
      targetAgreementId: agreement.id,
    );
    if (funded) await onPaid?.call();
  }

  Future<void> _payFromVault(BuildContext context, String amountDue) async {
    // Asked for here rather than inside the controller so the PIN lives only
    // as long as this call: it goes into the one request that needs it and is
    // never held anywhere afterwards.
    final pin = await promptVaultPin(
      context,
      title: 'Confirm ${LandaCurrency.format(amountDue)}',
      subtitle: 'Enter your vault PIN to move this rent into escrow.',
      actionLabel: 'Pay ${LandaCurrency.format(amountDue)}',
    );
    if (!context.mounted || pin == null) return;

    final payments = context.read<PaymentController>();
    final payment = await payments.payRentFromVault(agreement, vaultPin: pin);
    if (!context.mounted) return;

    if (payment == null) {
      // A short balance is the one failure with somewhere to go, so it gets
      // the top-up route rather than a toast the tenant can only read.
      if (payments.vaultBalanceFellShort) {
        await _offerShortfallTopUp(context, amountDue, payments.vaultShortfall);
        return;
      }
      // The payment controller does not own the vault, so the PIN standing is
      // re-read here: the same check a withdrawal makes for itself, worded
      // the same way.
      final vault = context.read<VaultController>();
      await vault.refreshPinStatusAfterFailedAttempt();
      if (!context.mounted) return;
      LandaToast.error(
        context,
        vault.describeFailedAttempt(
          payments.errorMessage ??
              'Could not pay that rent from your vault. Try again in a moment.',
        ),
      );
      return;
    }

    // Receipt first, refresh second. The refresh takes this card out of the
    // tree, rent is no longer due, so anything shown after it would be
    // shown from a dead context and silently skipped.
    LandaToast.success(context, 'Rent paid and held in escrow.');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PaymentReceiptModal(payment: payment),
    );

    // The vault is lighter and the payment list has a new row; neither is
    // safe to patch locally, so both are refetched behind the receipt.
    final vault = context.read<VaultController>();
    // The bill this was saved towards is settled, so the goal goes with it:
    // otherwise the tenant keeps seeing progress towards rent already paid.
    await vault.clearSetAside(agreement.id);
    await vault.loadVault();
    await onPaid?.call();
  }

  /// Offers to add exactly what the bill was short by.
  ///
  /// Reachable because a balance can move between this card rendering and the
  /// tap (another payment, a withdrawal) so "pay from vault" is an offer the
  /// backend is entitled to refuse.
  Future<void> _offerShortfallTopUp(
    BuildContext context,
    String amountDue,
    String? quotedShortfall,
  ) async {
    final vault = context.read<VaultController>();
    // Prefer the backend's figure. Falling back to the balance we hold is a
    // close second, and better than sending the tenant to a blank amount.
    final shortfall =
        quotedShortfall ??
        LandaCurrency.subtract(amountDue, vault.availableBalance) ??
        amountDue;
    final unitLabel = agreement.unitNumber.isEmpty
        ? 'rent'
        : 'rent · Unit ${agreement.unitNumber}';

    LandaToast.error(
      context,
      'Your vault is ${LandaCurrency.format(shortfall)} short of this rent. '
      'Nothing has been charged.',
    );

    final funded = await openTopUpSheet(
      context,
      targetAmount: shortfall,
      targetLabel: unitLabel,
      targetAgreementId: agreement.id,
    );
    if (funded) await onPaid?.call();
  }
}

/// When this bill lands, in the plainest words available.
class _DuePill extends StatelessWidget {
  final RentSchedule schedule;

  const _DuePill({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final (text, color) = _describe(context);

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppTheme.cornerSm,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_outlined, size: 13, color: color),
              const SizedBox(width: 6),
              Text(text, style: AppTheme.labelText(context, color: color)),
            ],
          ),
        ),
        if (schedule.plan != RentPlan.unknown)
          Text(
            schedule.plan.label,
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        if (schedule.instalmentsTotal > 1)
          Text(
            'Payment ${schedule.instalmentsPaid + 1} of '
            '${schedule.instalmentsTotal}',
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
      ],
    );
  }

  /// The sentence and its colour. Lateness is a dispute-red fact, an imminent
  /// bill is a warning, and a date months away is just information: colouring
  /// all three the same would train tenants to ignore the one that matters.
  (String, Color) _describe(BuildContext context) {
    final days = schedule.daysUntilDue;
    final due = schedule.dueDate;

    if (schedule.isOverdue || (days != null && days < 0)) {
      final late = days == null ? null : -days;
      return (
        late == null
            ? 'Overdue'
            : 'Overdue by $late ${late == 1 ? 'day' : 'days'}',
        AppTheme.disputeColor,
      );
    }
    if (days == 0) return ('Due today', AppTheme.disputeColor);
    if (due == null) return ('Due now', AppTheme.actionColor);

    final formatted = DateFormat('d MMM yyyy').format(due);
    if (days == null) return ('Due $formatted', AppTheme.profileColor);
    if (days <= 30) {
      return (
        'Due in $days ${days == 1 ? 'day' : 'days'} · $formatted',
        AppTheme.warningColor,
      );
    }
    return ('Due $formatted', AppTheme.profileColor);
  }
}

/// How far the vault has got towards this bill.
class _SavingProgress extends StatelessWidget {
  final String saved;
  final String target;

  const _SavingProgress({required this.saved, required this.target});

  @override
  Widget build(BuildContext context) {
    final savedKobo = LandaCurrency.minorUnits(saved) ?? 0;
    final targetKobo = LandaCurrency.minorUnits(target) ?? 0;
    if (targetKobo <= 0) return const SizedBox.shrink();

    final fraction = (savedKobo / targetKobo).clamp(0.0, 1.0);
    final remaining = LandaCurrency.subtract(target, saved);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: AppTheme.subtleSurfaceColor(context),
            valueColor: const AlwaysStoppedAnimation(AppTheme.successColor),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${LandaCurrency.format(saved)} saved · '
          '${LandaCurrency.format(remaining ?? target)} to go',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
      ],
    );
  }
}

class _CardButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool outlined;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _CardButton({
    required this.label,
    required this.icon,
    this.outlined = false,
    this.isLoading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = outlined ? AppTheme.actionColor : Colors.white;

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18, color: foreground),
              label: Text(label, style: _labelStyle(foreground)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: AppTheme.actionColor.withValues(alpha: 0.4),
                ),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: isLoading
                  ? const LandaBusyDots(color: Colors.white)
                  : Icon(icon, size: 18, color: foreground),
              label: Text(label, style: _labelStyle(foreground)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.actionColor,
              ),
            ),
    );
  }

  static TextStyle _labelStyle(Color color) =>
      TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold);
}
