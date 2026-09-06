import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../vault/controllers/vault_controller.dart';
import '../../vault/views/widgets/vault_balance_card.dart';
import '../controllers/payment_controller.dart';
import '../models/payment_model.dart';
import '../models/pending_rent.dart';
import 'payment_receipt_modal.dart';
import 'widgets/rent_due_card.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with AutoRefreshMixin<PaymentsScreen> {
  @override
  Future<void> onAutoRefresh() => _reload();

  /// Rent due is derived from agreements as well as payments, and the vault
  /// balance heads the page, so this screen owns all three fetches.
  ///
  /// The vault is fetched for both roles now that tenants have one: a tenant's
  /// balance decides whether rent can be paid without a card, so the page
  /// cannot render its main action correctly without it.
  Future<void> _reload() => Future.wait([
    context.read<PaymentController>().loadPayments(),
    context.read<AgreementController>().loadAgreements(),
    context.read<VaultController>().loadVault(),
    // Read alongside the balance so the Settings row is accurate and a
    // withdrawal or vault payment already knows whether it is asking for a PIN
    // that exists.
    context.read<VaultController>().loadPinStatus(),
    // The per-unit savings plan lives on the device and is keyed to
    // this user, so it loads with everything else the vault needs.
    context.read<VaultController>().loadAllocations(
      context.read<AuthController>().currentUser?.id ?? '',
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    final paymentCtrl = context.watch<PaymentController>();
    final agreementCtrl = context.watch<AgreementController>();
    final isLandlord =
        context.watch<AuthController>().currentRole == UserRole.owner;
    final rentDue = pendingRentAgreements(
      agreements: agreementCtrl.agreements,
      payments: paymentCtrl.payments,
      isLandlord: isLandlord,
    );
    final secondaryTextColor = AppTheme.secondaryTextColor(context);

    if (paymentCtrl.hasError && paymentCtrl.payments.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        appBar: const LandaAppBar(),
        body: RefreshIndicator(
          onRefresh: _reload,
          child: LandaErrorState(
            message: paymentCtrl.errorMessage,
            isConnectionError: paymentCtrl.errorIsConnection,
            onRetry: _reload,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Payment Ledger',
                style: AppTheme.screenTitle(
                  context,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isLandlord
                    ? 'Your vault balance, rent in escrow and every settlement.'
                    : 'Your vault, what rent is due, and every escrow '
                          'transaction.',
                style: AppTheme.bodyText(context, color: secondaryTextColor),
              ),
              const SizedBox(height: 20),

              // The vault leads the page for both roles: it is the balance the
              // rest of the screen explains, and for a tenant it is also what
              // the rent-due card below is going to spend.
              const VaultBalanceCard(),
              const SizedBox(height: 24),

              // Pending payments sit above the ledger: they are the one thing
              // on this screen that needs an action, and this is now the only
              // place they appear. The tenant dashboard used to carry a copy,
              // which meant two screens quietly disagreeing about what was
              // owed. One card per unit, so a tenant with two homes sees both.
              if (rentDue.isNotEmpty) ...[
                Text('PENDING PAYMENTS', style: AppTheme.labelText(context)),
                const SizedBox(height: 8),
                for (final (index, agreement) in rentDue.indexed)
                  LandaEntrance(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RentDueCard(agreement: agreement, onPaid: _reload),
                    ),
                  ),
                const SizedBox(height: 20),
              ],

              // The vault card now sits above the ledger for both roles, so
              // the ledger always needs naming to separate the two.
              Text('LEDGER', style: AppTheme.labelText(context)),
              const SizedBox(height: 8),

              if (paymentCtrl.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LandaErrorBanner(
                    message: paymentCtrl.errorMessage!,
                    isConnectionError: paymentCtrl.errorIsConnection,
                    onRetry: _reload,
                  ),
                ),

              if (!paymentCtrl.hasLoaded() ||
                  (paymentCtrl.isLoading && paymentCtrl.payments.isEmpty))
                const LandaSkeletonList(count: 3, padding: EdgeInsets.zero)
              else if (paymentCtrl.payments.isEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: AppTheme.cornerLg,
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: LandaEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No payment transactions yet',
                    message:
                        'Payments for signed tenancy agreements will appear here.',
                    scrollable: false,
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    actionLabel: 'Check again',
                    actionIcon: Icons.refresh_rounded,
                    onAction: _reload,
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: paymentCtrl.payments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final p = paymentCtrl.payments[index];
                    final isReleased = p.status == PaymentStatus.released;
                    final isDisputed = p.status == PaymentStatus.disputed;
                    // A disputed payment must never read as a normal escrow
                    // hold, so it gets its own colour and icon.
                    final statusSurface = isDisputed
                        ? AppTheme.disputeSurface(context)
                        : isReleased
                        ? AppTheme.successSurface(context)
                        : AppTheme.vacantSurface(context);
                    final statusColor = isDisputed
                        ? AppTheme.disputeColor
                        : isReleased
                        ? AppTheme.successColor
                        : AppTheme.primaryColor;

                    return LandaEntrance(
                      index: index,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor(context),
                          borderRadius: AppTheme.cornerLg,
                          border: Border.all(
                            color: AppTheme.borderColor(context),
                          ),
                          boxShadow: AppTheme.cardShadow(context),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: statusSurface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isDisputed
                                    ? Icons.gavel
                                    : isReleased
                                    ? Icons.verified
                                    : Icons.lock_clock,
                                color: statusColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    LandaCurrency.format(p.amount),
                                    style: AppTheme.sectionTitle(
                                      context,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ref: ${p.reference.substring(0, p.reference.length > 16 ? 16 : p.reference.length)}...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusSurface,
                                    borderRadius: AppTheme.cornerSm,
                                    border: Border.all(
                                      color: statusColor.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    p.status.label,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(24),
                                        ),
                                      ),
                                      builder: (_) =>
                                          PaymentReceiptModal(payment: p),
                                    );
                                  },
                                  child: const Text(
                                    'View Receipt',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.actionColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
