import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/widgets/custom_bottom_navbar.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../../auth/controllers/auth_controller.dart';
import '../controllers/vault_controller.dart';
import '../models/vault_models.dart';
import 'widgets/vault_balance_card.dart';

/// Every movement in and out of the vault, for whoever owns it.
///
/// The ledger is the answer to "where did my money go", so it shows the
/// running balance after each row rather than amounts alone: a list of
/// figures with no balance beside them cannot be reconciled against a bank
/// statement, which is the one thing anyone will want to do with it.
class VaultLedgerScreen extends StatefulWidget {
  /// True when this is a bottom-nav tab rather than a pushed page: an
  /// artisan's earnings live here, so for them it is a destination rather than
  /// somewhere they arrived from the vault card.
  ///
  /// Changes two things: the last row is scrolled clear of the floating nav
  /// bar (an overlay, so nothing beneath it is inset automatically), and the
  /// page keeps its own title instead of borrowing the pushed-route chrome.
  final bool isTabRoot;

  const VaultLedgerScreen({super.key, this.isTabRoot = false});

  @override
  State<VaultLedgerScreen> createState() => _VaultLedgerScreenState();
}

class _VaultLedgerScreenState extends State<VaultLedgerScreen>
    with AutoRefreshMixin<VaultLedgerScreen> {
  @override
  Future<void> onAutoRefresh() => _reload();

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Fetches the next page slightly before the list actually ends, so the
  /// rows are already there by the time the user reaches them.
  void _onScroll() {
    final controller = context.read<VaultController>();
    if (!controller.hasMoreTransactions || controller.isLoading) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      controller.loadMoreTransactions();
    }
  }

  /// The rows and the lifetime totals above them come from two endpoints, so
  /// both are refetched together: a header quoting yesterday's totals over
  /// today's rows is worse than no header at all.
  Future<void> _reload() {
    final controller = context.read<VaultController>();
    return Future.wait([controller.loadTransactions(), controller.loadVault()]);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final transactions = controller.transactions;
    // Tested as "is a tenant" rather than "is not a landlord": an artisan is
    // neither, and topping up is a tenant-only endpoint, so the loose test
    // would offer them an action the backend refuses.
    final isTenant = context.select<AuthController, bool>(
      (auth) => auth.currentRole.isTenant,
    );

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
        automaticallyImplyLeading: !widget.isTabRoot,
        title: Text(
          widget.isTabRoot ? 'Earnings' : 'Vault activity',
          style: AppTheme.cardTitle(context),
        ),
        actions: [
          // The ledger is where someone lands when they are thinking about
          // their balance, so the action on it is one tap away rather than
          // back on the previous screen.
          TextButton(
            onPressed: () =>
                isTenant ? openTopUpSheet(context) : openWithdrawSheet(context),
            child: Text(
              isTenant ? 'Add money' : 'Withdraw',
              style: AppTheme.cardTitle(context, color: AppTheme.actionColor),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _buildBody(context, controller, transactions, isTenant),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    VaultController controller,
    List<VaultTransaction> transactions,
    bool isTenant,
  ) {
    if (!controller.hasLoaded(VaultController.kTransactionsKey) ||
        (controller.isLoading && transactions.isEmpty)) {
      return const OasisSkeletonList(count: 5);
    }

    // A failure with nothing to show is a dead page; a failure with rows
    // already on screen is a banner over them.
    if (controller.hasError && transactions.isEmpty) {
      return OasisErrorState(
        message: controller.errorMessage,
        isConnectionError: controller.errorIsConnection,
        onRetry: _reload,
      );
    }

    if (transactions.isEmpty) {
      return OasisEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Nothing in your vault yet',
        message: isTenant
            ? 'Money you add shows up here, along with every rent payment you '
                  'make from your vault and every withdrawal back to your bank.'
            : 'Rent shows up here the moment it is released from escrow, along '
                  'with every withdrawal you make.',
        // The action that fills this screen, offered at the moment somebody
        // is looking at the reason it is empty.
        actionLabel: isTenant ? 'Add money' : 'Refresh',
        actionIcon: isTenant ? Icons.add_rounded : Icons.refresh_rounded,
        onAction: isTenant ? () => openTopUpSheet(context) : _reload,
      );
    }

    final vault = controller.vault;

    // The totals ride inside the list rather than above it so a pull-to-refresh
    // anywhere on the page still works, header included.
    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        widget.isTabRoot ? CustomBottomNavbar.reservedHeight + 24 : 40,
      ),
      itemCount: transactions.length + 2,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return vault == null
              ? const SizedBox.shrink()
              : _LifetimeTotals(vault: vault, isTenant: isTenant);
        }
        if (index == transactions.length + 1) {
          return _ListFooter(
            isLoadingMore: controller.isLoading,
            hasMore: controller.hasMoreTransactions,
          );
        }
        return OasisEntrance(
          index: index - 1,
          child: _LedgerRow(transaction: transactions[index - 1]),
        );
      },
    );
  }
}

/// What has passed through this vault over its life.
///
/// Three figures for a tenant and two for a landlord, because a landlord never
/// spends from theirs: showing them a permanent "₦0 rent paid" would invite
/// them to wonder what they were meant to have paid.
class _LifetimeTotals extends StatelessWidget {
  final VaultSummary vault;
  final bool isTenant;

  const _LifetimeTotals({required this.vault, required this.isTenant});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerLg,
      ),
      child: Row(
        children: [
          _Total(
            label: isTenant ? 'ADDED' : 'RECEIVED',
            amount: vault.totalCredited,
          ),
          if (isTenant) _Total(label: 'RENT PAID', amount: vault.totalSpent),
          _Total(label: 'WITHDRAWN', amount: vault.totalWithdrawn),
        ],
      ),
    ),
  );
}

class _Total extends StatelessWidget {
  final String label;
  final String amount;

  const _Total({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
        ),
        const SizedBox(height: 3),
        Text(
          OasisCurrency.format(amount),
          style: AppTheme.cardTitle(context),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _LedgerRow extends StatelessWidget {
  final VaultTransaction transaction;

  const _LedgerRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    // Credits are sage, debits are neutral: money leaving because the user
    // asked it to (a withdrawal, a rent payment) is not a warning, so only
    // genuine money-in gets the colour.
    final amountColor = transaction.isCredit
        ? AppTheme.successColor
        : AppTheme.primaryTextColor(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color:
                  (transaction.isCredit
                          ? AppTheme.successColor
                          : AppTheme.profileColor)
                      .withValues(alpha: 0.12),
              borderRadius: AppTheme.cornerMd,
            ),
            child: Icon(
              transaction.isCredit
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              size: 18,
              color: transaction.isCredit
                  ? AppTheme.successColor
                  : AppTheme.profileColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: AppTheme.cardTitle(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Balance ${OasisCurrency.format(transaction.balanceAfter)}',
                  style: AppTheme.labelText(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${transaction.isCredit ? '+' : '−'}'
            '${OasisCurrency.format(transaction.amount)}',
            style: AppTheme.cardTitle(context, color: amountColor),
          ),
        ],
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  final bool isLoadingMore;
  final bool hasMore;

  const _ListFooter({required this.isLoadingMore, required this.hasMore});

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore && hasMore) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: OasisCardSkeleton(),
      );
    }
    if (hasMore) return const SizedBox(height: 24);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: Text('That is everything.', style: AppTheme.labelText(context)),
      ),
    );
  }
}
