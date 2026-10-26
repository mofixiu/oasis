import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/oasis_currency.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_shimmer.dart';
import '../../../../core/widgets/v2_ui.dart';
import '../../../auth/controllers/auth_controller.dart';
import '../../../auth/models/user_model.dart';
import '../../../payouts/controllers/payout_controller.dart';
import '../../../payouts/views/payout_account_screen.dart';
import '../../../vault/controllers/vault_controller.dart';
import '../../../vault/views/vault_ledger_screen.dart';
import '../../../vault/views/vault_pin_sheet.dart';
import '../../../vault/views/widgets/vault_balance_card.dart';
import '../../../../core/utils/fade_page_route.dart';
import '../../../../core/widgets/oasis_animated_value.dart';
import '../../controllers/shortlet_controller.dart';
import '../../models/shortlet_models.dart';
import 'v2_stay_widgets.dart';

/// Money, in one place: the vault (saved money a guest pays from, or where a
/// host's payouts land) on top, then the shortlet payments themselves.
class V2PaymentsScreen extends StatefulWidget {
  final VoidCallback? onExplore;
  final VoidCallback? onManageStays;
  final VoidCallback? onOpenTrips;

  /// Opened on its own page (from Profile's Vault tile) rather than as a tab:
  /// shows a way back, and no profile button to loop back to Profile.
  final bool isPushed;

  const V2PaymentsScreen({
    super.key,
    this.onExplore,
    this.onManageStays,
    this.onOpenTrips,
    this.isPushed = false,
  });

  @override
  State<V2PaymentsScreen> createState() => _V2PaymentsScreenState();
}

class _V2PaymentsScreenState extends State<V2PaymentsScreen> {
  /// Kept for the session, so hiding the balance survives switching tabs.
  static bool _hideBalance = false;

  bool get _isHost =>
      context.read<AuthController>().currentRole == UserRole.owner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() {
    final shortlets = context.read<ShortLetController>();
    final vault = context.read<VaultController>();
    return Future.wait([
      _isHost ? shortlets.loadLandlordBookings() : shortlets.loadMyBookings(),
      vault.loadVault(),
      vault.loadTransactions(),
      vault.loadPinStatus(),
      context.read<PayoutController>().loadPayoutAccount(),
    ]);
  }

  void _openLedger() =>
      Navigator.push(context, FadePageRoute(page: const VaultLedgerScreen()));

  @override
  Widget build(BuildContext context) {
    final isHost = context.select<AuthController, bool>(
      (auth) => auth.currentRole == UserRole.owner,
    );
    final shortlets = context.watch<ShortLetController>();
    final vault = context.watch<VaultController>();

    final records = shortlets.bookings.where((booking) {
      if (isHost) {
        return booking.status.isPaid ||
            (booking.paymentId?.isNotEmpty ?? false);
      }
      return booking.status.isPaid ||
          booking.status.needsPayment ||
          (booking.paymentId?.isNotEmpty ?? false);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final due = isHost
        ? const <ShortLetBooking>[]
        : shortlets.bookingsAwaitingPayment;

    return V2StatusBar(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              children: [
                if (widget.isPushed) ...[
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
                V2PageHeader(
                  title: 'Payments',
                  subtitle: isHost
                      ? 'Your vault and payouts.'
                      : 'Your vault and shortlet payments.',
                  trailing: widget.isPushed ? null : const V2ProfileButton(),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 18),
                _VaultHeroCard(
                  isHost: isHost,
                  hidden: _hideBalance,
                  onToggleHidden: () =>
                      setState(() => _hideBalance = !_hideBalance),
                ),
                const SizedBox(height: 20),
                _QuickActions(
                  isHost: isHost,
                  onHistory: _openLedger,
                  onShortcut: isHost
                      ? widget.onManageStays
                      : widget.onOpenTrips,
                ),
                if (due.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _SaveForTripCard(
                    booking: due.first,
                    hidden: _hideBalance,
                    onPay: widget.onOpenTrips,
                  ),
                ],
                const SizedBox(height: 26),
                V2SectionHeader(
                  title: 'Vault activity',
                  actionLabel: vault.transactions.isEmpty ? null : 'See all',
                  onAction: _openLedger,
                ),
                const SizedBox(height: 6),
                _VaultActivity(controller: vault, hidden: _hideBalance),
                const SizedBox(height: 24),
                V2SectionHeader(
                  title: isHost ? 'Payouts' : 'Shortlet payments',
                ),
                const SizedBox(height: 12),
                if (!shortlets.hasLoaded(ShortLetController.kBookingsKey) &&
                    shortlets.bookings.isEmpty)
                  const SizedBox(
                    height: 160,
                    child: OasisSkeletonList(
                      count: 1,
                      padding: EdgeInsets.zero,
                    ),
                  )
                else if (records.isEmpty)
                  _QuietNote(
                    text: isHost
                        ? 'When a guest pays for a booking, its payout is '
                              'tracked here.'
                        : 'Payments for your shortlets will collect here, with '
                              'their status.',
                    actionLabel: isHost ? null : 'Explore shortlets',
                    onAction: isHost ? null : widget.onExplore,
                  )
                else
                  for (final booking in records) ...[
                    _PaymentRecord(booking: booking, isHost: isHost),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 8),
                _TrustNote(isHost: isHost),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The balance, Cowrywise-style: one strong card with the number large, a
/// way to hide it, and the two moves that change it.
class _VaultHeroCard extends StatelessWidget {
  final bool isHost;
  final bool hidden;
  final VoidCallback onToggleHidden;

  const _VaultHeroCard({
    required this.isHost,
    required this.hidden,
    required this.onToggleHidden,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final vault = controller.vault;
    final payoutVerified = context.watch<PayoutController>().isVerified;
    final soft = Colors.white.withValues(alpha: 0.78);

    String? blocked;
    if (vault != null) {
      if (!vault.hasAvailableBalance) {
        blocked = isHost ? 'Nothing to withdraw yet.' : null;
      } else if (!payoutVerified) {
        blocked = 'Add a bank account to withdraw.';
      }
    }

    final String caption;
    if (vault != null && vault.hasPendingWithdrawal) {
      caption =
          '${OasisCurrency.format(vault.pendingWithdrawalBalance)} on its way '
          'to your bank';
    } else {
      caption = isHost
          ? 'Payouts from your bookings land here.'
          : 'Save ahead for your next shortlet, then pay in one tap.';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.terracottaColor,
            Color.lerp(AppTheme.terracottaColor, Colors.black, 0.28)!,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.terracottaColor.withValues(alpha: 0.3),
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_outlined, size: 17, color: soft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Vault balance',
                  style: TextStyle(
                    color: soft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: hidden ? 'Show balance' : 'Hide balance',
                onPressed: onToggleHidden,
                icon: Icon(
                  hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: soft,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: vault == null
                ? Text(
                    controller.hasError
                        ? 'Could not load your vault. Pull down to try again.'
                        : 'Loading…',
                    style: TextStyle(color: soft, fontSize: 15),
                  )
                : OasisAnimatedValue(
                    value: hidden
                        ? '₦ ••••••'
                        : OasisCurrency.format(vault.availableBalance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(caption, style: TextStyle(color: soft, fontSize: 13)),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                if (!isHost) ...[
                  Expanded(
                    child: _HeroAction(
                      icon: Icons.add_rounded,
                      label: 'Add money',
                      filled: true,
                      onTap: () => openTopUpSheet(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _HeroAction(
                    icon: Icons.arrow_outward_rounded,
                    label: 'Withdraw',
                    filled: isHost,
                    onTap: () => openWithdrawSheet(context),
                  ),
                ),
              ],
            ),
          ),
          if (blocked != null) ...[
            const SizedBox(height: 12),
            Text(blocked, style: TextStyle(color: soft, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _HeroAction({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? AppTheme.terracottaColor : Colors.white;
    return OasisPressable(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: AppTheme.textMd,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round shortcuts under the balance: history, PIN, bank, and trips (or
/// shortlets for a host).
class _QuickActions extends StatelessWidget {
  final bool isHost;
  final VoidCallback onHistory;
  final VoidCallback? onShortcut;

  const _QuickActions({
    required this.isHost,
    required this.onHistory,
    required this.onShortcut,
  });

  @override
  Widget build(BuildContext context) {
    final hasPin = context.select<VaultController, bool>((v) => v.hasVaultPin);
    final items = <(IconData, String, VoidCallback)>[
      (Icons.receipt_long_outlined, 'History', onHistory),
      (
        Icons.lock_outline_rounded,
        hasPin ? 'Vault PIN' : 'Set PIN',
        () => openVaultPinManager(context),
      ),
      (
        Icons.account_balance_outlined,
        'Bank',
        () => Navigator.push(
          context,
          FadePageRoute(page: const PayoutAccountScreen()),
        ),
      ),
      if (onShortcut != null)
        (
          isHost ? Icons.holiday_village_outlined : Icons.luggage_outlined,
          isHost ? 'Shortlets' : 'Trips',
          onShortcut!,
        ),
    ];

    return Row(
      children: [
        for (final (icon, label, onTap) in items)
          Expanded(
            child: Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              child: OasisPressable(
                onTap: onTap,
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor(context),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.borderColor(context),
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 22,
                        color: AppTheme.terracottaColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: AppTheme.bodyText(context).copyWith(
                        color: AppTheme.primaryTextColor(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A booking waiting to be paid, shown as a savings target: how much of it
/// the vault already covers, and the one step that closes the gap.
class _SaveForTripCard extends StatelessWidget {
  final ShortLetBooking booking;
  final bool hidden;
  final VoidCallback? onPay;

  const _SaveForTripCard({
    required this.booking,
    required this.hidden,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultController>();
    final balance = vault.availableBalance;
    final balanceMinor = OasisCurrency.minorUnits(balance) ?? 0;
    final totalMinor = OasisCurrency.minorUnits(booking.totalAmount) ?? 0;
    final progress = totalMinor <= 0
        ? 0.0
        : (balanceMinor / totalMinor).clamp(0.0, 1.0);
    final covers = vault.canCover(booking.totalAmount);
    final shortfall =
        OasisCurrency.subtract(booking.totalAmount, balance) ??
        booking.totalAmount;
    final window = v2PayWindow(booking);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.vacantSurface(context),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flag_outlined,
                  size: 20,
                  color: AppTheme.terracottaColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Save for ${booking.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.cardTitle(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      window ?? v2DateRange(booking),
                      style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  hidden
                      ? 'Saved towards ${OasisCurrency.format(booking.totalAmount)}'
                      : '${OasisCurrency.format(balance)} of '
                            '${OasisCurrency.format(booking.totalAmount)}',
                  style: AppTheme.cardTitle(context).copyWith(fontSize: 14),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: AppTheme.cardTitle(
                  context,
                  color: AppTheme.terracottaColor,
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppTheme.subtleSurfaceColor(context),
              color: AppTheme.terracottaColor,
            ),
          ),
          const SizedBox(height: 14),
          if (covers)
            OasisButton(
              label: 'Pay from your vault',
              icon: Icons.lock_outline_rounded,
              onPressed: onPay,
            )
          else
            OasisButton(
              label: 'Add ${OasisCurrency.format(shortfall)}',
              icon: Icons.add_rounded,
              onPressed: () => openTopUpSheet(
                context,
                targetAmount: shortfall,
                targetLabel: booking.title,
              ),
            ),
        ],
      ),
    );
  }
}

/// The latest money in and out of the vault.
class _VaultActivity extends StatelessWidget {
  final VaultController controller;
  final bool hidden;

  const _VaultActivity({required this.controller, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final items = controller.transactions.take(5).toList();
    if (items.isEmpty) {
      return const _QuietNote(
        text:
            'Money you add to your vault, pay from it or withdraw will show '
            'up here.',
      );
    }
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: item.isCredit
                        ? AppTheme.successSurface(context)
                        : AppTheme.vacantSurface(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.isCredit
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    size: 18,
                    color: item.isCredit
                        ? AppTheme.successColor
                        : AppTheme.terracottaColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.cardTitle(
                          context,
                        ).copyWith(fontSize: 14),
                      ),
                      Text(
                        _when(item.createdAt),
                        style: AppTheme.bodyText(
                          context,
                        ).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  hidden
                      ? '••••'
                      : '${item.isCredit ? '+' : '−'}'
                            '${OasisCurrency.format(item.amount)}',
                  style: AppTheme.cardTitle(
                    context,
                    color: item.isCredit
                        ? AppTheme.successColor
                        : AppTheme.primaryTextColor(context),
                  ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _when(String raw) {
    final at = DateTime.tryParse(raw)?.toLocal();
    return at == null ? '' : DateFormat('d MMM, h:mm a').format(at);
  }
}

class _QuietNote extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _QuietNote({required this.text, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: AppTheme.bodyText(context)),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(actionLabel!),
          ),
      ],
    ),
  );
}

class _TrustNote extends StatelessWidget {
  final bool isHost;

  const _TrustNote({required this.isHost});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.primaryColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.14)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 20, color: AppTheme.primaryColor),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            isHost
                ? 'Payout amounts and release timing come from Oasis. '
                      'A guest dispute can pause a payout while it is reviewed.'
                : 'Your payment is held securely while the booking is arranged. '
                      'The booking record includes the amount and status.',
            style: AppTheme.bodyText(context).copyWith(height: 1.45),
          ),
        ),
      ],
    ),
  );
}

class _PaymentRecord extends StatelessWidget {
  final ShortLetBooking booking;
  final bool isHost;

  const _PaymentRecord({required this.booking, required this.isHost});

  @override
  Widget build(BuildContext context) {
    final title = booking.propertyName.isNotEmpty
        ? booking.propertyName
        : 'Shortlet';
    final amount = isHost ? booking.hostPayout : booking.totalAmount;
    final status = isHost
        ? booking.hostPayoutStatusLabel.trim().isNotEmpty
              ? booking.hostPayoutStatusLabel
              : booking.hostPayoutStatus.fallbackLabel
        : booking.status.needsPayment
        ? 'Payment required'
        : booking.status.isPaid
        ? 'Payment confirmed'
        : booking.status.label;
    final icon = isHost
        ? Icons.account_balance_outlined
        : Icons.receipt_long_outlined;
    final releaseAt = booking.hostPayoutStatus == HostPayoutStatus.held
        ? DateTime.tryParse(booking.hostPayoutReleaseAt ?? '')?.toLocal()
        : null;
    final tone = isHost
        ? switch (booking.hostPayoutStatus) {
            HostPayoutStatus.released => V2Tone.positive,
            HostPayoutStatus.blocked => V2Tone.negative,
            HostPayoutStatus.refunded => V2Tone.neutral,
            _ => V2Tone.pending,
          }
        : booking.status.needsPayment
        ? V2Tone.pending
        : booking.status.isPaid
        ? V2Tone.positive
        : v2ToneFor(booking.status);

    return OasisPressable(
      pressedScale: 0.995,
      onTap: null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderColor(context)),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppTheme.primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTheme.cardTitle(context)),
                      const SizedBox(height: 3),
                      Text(
                        v2DateRange(booking),
                        style: AppTheme.bodyText(
                          context,
                        ).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  OasisCurrency.format(amount),
                  style: AppTheme.cardTitle(context).copyWith(fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isHost
                        ? 'Host payout'
                        : '${v2Plural(booking.nights, 'night', 'nights')} · '
                              '${v2Plural(booking.guestCount, 'guest', 'guests')}',
                    style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                V2StatusPill(label: status, tone: tone),
              ],
            ),
            // The exact release time first: the backend's description was
            // written for the old check-in-date rule (API guide 20).
            if (isHost && releaseAt != null) ...[
              const SizedBox(height: 9),
              Text(
                'Releases ${DateFormat('d MMM, h:mm a').format(releaseAt)}, '
                'a day after checkout, unless the guest reports a problem.',
                style: AppTheme.bodyText(context).copyWith(fontSize: 12),
              ),
            ] else if (isHost &&
                booking.hostPayoutStatusDescription.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                booking.hostPayoutStatusDescription,
                style: AppTheme.bodyText(context).copyWith(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
