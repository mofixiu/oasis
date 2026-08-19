import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../controllers/payment_controller.dart';
import '../models/payment_model.dart';
import 'payment_receipt_modal.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentController>().loadPayments();
    });
  }

  Future<void> _reload() => context.read<PaymentController>().loadPayments();

  @override
  Widget build(BuildContext context) {
    final paymentCtrl = context.watch<PaymentController>();
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
                'Track all rent escrow transactions and settlement statuses.',
                style: AppTheme.bodyText(context, color: secondaryTextColor),
              ),
              const SizedBox(height: 20),
              if (paymentCtrl.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LandaErrorBanner(
                    message: paymentCtrl.errorMessage!,
                    isConnectionError: paymentCtrl.errorIsConnection,
                    onRetry: _reload,
                  ),
                ),

              if (paymentCtrl.isLoading && paymentCtrl.payments.isEmpty)
                const LandaSkeletonList(count: 3, padding: EdgeInsets.zero)
              else if (paymentCtrl.payments.isEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: AppTheme.cornerLg,
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: const LandaEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No payment transactions yet',
                    message:
                        'Payments for signed tenancy agreements will appear here.',
                    scrollable: false,
                    padding: EdgeInsets.fromLTRB(24, 32, 24, 32),
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
                        ? AppTheme.disputeSurfaceColor
                        : isReleased
                        ? AppTheme.successSurfaceColor
                        : AppTheme.vacantSurfaceColor;
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
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
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
