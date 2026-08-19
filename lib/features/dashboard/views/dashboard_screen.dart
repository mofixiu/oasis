import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/utils/landa_haptics.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../agreements/models/agreement_model.dart';
import '../../agreements/views/tenancy_agreement_modal.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../auth/views/identity_verification_screen.dart';
import '../../notifications/controllers/notification_controller.dart';
import '../../payments/controllers/payment_controller.dart';
import '../../payments/models/payment_model.dart';
import '../../payments/views/payment_receipt_modal.dart';
import '../../properties/controllers/landlord_controller.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _TenantAgreementCard extends StatelessWidget {
  final TenancyAgreementModel agreement;

  const _TenantAgreementCard({required this.agreement});

  @override
  Widget build(BuildContext context) {
    final isExecuted = agreement.isExecuted;
    final actionLabel = agreement.canPayRent
        ? 'View executed agreement & pay rent'
        : agreement.canTenantSign
        ? 'Review & sign agreement'
        : 'View agreement';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: AppTheme.cornerLg,
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tenancy Agreement · Unit ${agreement.unitNumber}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            agreement.progressTitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isExecuted ? AppTheme.successColor : AppTheme.warningColor,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  builder: (_) => ViewAgreementModal(agreement: agreement),
                );
              },
              icon: Icon(
                agreement.canPayRent
                    ? Icons.payments_outlined
                    : Icons.description_outlined,
                size: 18,
                color: Colors.white,
              ),
              label: Text(
                actionLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.actionColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTenantData());
  }

  /// Awaits every fetch so pull-to-refresh and the retry button both know
  /// when the dashboard has actually finished reloading.
  Future<void> _loadTenantData() async {
    await Future.wait([
      context.read<LandlordController>().loadTenantAssignedUnit(),
      context.read<AgreementController>().loadAgreements(),
      context.read<PaymentController>().loadPayments(),
      context.read<AuthController>().refreshProfile(),
      context.read<NotificationController>().loadNotifications(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final user = authController.currentUser;
    final landlordCtrl = context.watch<LandlordController>();
    final agreementCtrl = context.watch<AgreementController>();
    final paymentCtrl = context.watch<PaymentController>();

    final assignedUnit = landlordCtrl.tenantAssignedUnit;
    final tenantAgreements = agreementCtrl.agreements;
    final isVerified = user?.verificationStatus == VerificationStatus.verified;
    final isLoading =
        landlordCtrl.isLoading ||
        agreementCtrl.isLoading ||
        paymentCtrl.isLoading;

    // The dashboard is stitched from three independent fetches, so it reports
    // failure the way the user experiences it: if nothing at all loaded it is
    // a dead page and gets the full retry state; if some of it loaded, the
    // failure is a banner over the content that did arrive.
    final failedControllers = [
      landlordCtrl,
      agreementCtrl,
      paymentCtrl,
    ].where((c) => c.hasError).toList();
    final hasAnyContent =
        assignedUnit != null ||
        tenantAgreements.isNotEmpty ||
        paymentCtrl.payments.isNotEmpty;
    final isOffline = failedControllers.any((c) => c.errorIsConnection);
    final failureMessage = failedControllers.isEmpty
        ? null
        : failedControllers.first.errorMessage;

    final displayName = user?.email.split("@").first ?? "tenant";
    final secondaryTextColor = AppTheme.secondaryTextColor(context);

    if (!isLoading && failureMessage != null && !hasAnyContent) {
      return Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        appBar: const LandaAppBar(),
        body: RefreshIndicator(
          onRefresh: _loadTenantData,
          child: LandaErrorState(
            message: failureMessage,
            isConnectionError: isOffline,
            onRetry: _loadTenantData,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadTenantData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (failureMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LandaErrorBanner(
                    // Banner owns its own horizontal inset elsewhere; here the
                    // page padding already provides it.
                    message: failureMessage,
                    isConnectionError: isOffline,
                    onRetry: _loadTenantData,
                  ),
                ),
              // Verification prompt. Only shown while unverified — once the
              // user is verified there is nothing to act on, so we don't
              // occupy the top of the dashboard with a status badge.
              if (!isVerified) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.vacantSurfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.vacantColor.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gpp_maybe, color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const IdentityVerificationScreen(),
                            ),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'IDENTITY UNVERIFIED',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Tap to verify your identity with a selfie and NIN.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ],

              // Single-Line Greeting Header
              Text(
                'Welcome, $displayName',
                // profileTextColor rather than a hard-coded black: the old
                // value rendered black-on-black in dark mode.
                style: AppTheme.screenTitle(
                  context,
                  color: AppTheme.profileTextColor(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Manage your unit tenancy, sign agreements & track escrow payments.',
                style: AppTheme.bodyText(context, color: secondaryTextColor),
              ),
              const SizedBox(height: 24),

              // Assigned Unit Section
              Text('MY ASSIGNED UNIT', style: AppTheme.labelText(context)),
              const SizedBox(height: 8),
              if (isLoading && assignedUnit == null)
                const ShimmerCardSkeleton()
              else if (assignedUnit != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            assignedUnit.property?.name ?? 'Assigned Property',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.successSurfaceColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Unit ${assignedUnit.unitNumber}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.successColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${assignedUnit.property?.address ?? ""}, ${assignedUnit.property?.city ?? ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Annual Rent Amount:',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          Text(
                            LandaCurrency.format(assignedUnit.rentAmount),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.home_work_outlined,
                        size: 36,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No Unit Assigned Yet',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Your landlord will assign your unit and send a tenancy bridge agreement.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Tenancy Agreement Inbox
              Text('TENANCY AGREEMENTS', style: AppTheme.labelText(context)),
              const SizedBox(height: 8),
              if (isLoading && tenantAgreements.isEmpty)
                const ShimmerCardSkeleton()
              else if (tenantAgreements.isNotEmpty)
                Column(
                  children: [
                    for (final (index, agreement) in tenantAgreements.indexed)
                      LandaEntrance(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TenantAgreementCard(agreement: agreement),
                        ),
                      ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: AppTheme.cornerLg,
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 32,
                        color: AppTheme.mutedTextColor(context),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'No pending tenancy agreement to sign.',
                          style: AppTheme.bodyText(context),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Recent Payment Transactions Section
              Text('RECENT PAYMENTS', style: AppTheme.labelText(context)),
              const SizedBox(height: 8),
              if (isLoading && paymentCtrl.payments.isEmpty)
                const ShimmerCardSkeleton()
              else if (paymentCtrl.payments.isNotEmpty)
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: paymentCtrl.payments.length > 3
                      ? 3
                      : paymentCtrl.payments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = paymentCtrl.payments[index];
                    final isReleased = p.status == PaymentStatus.released;
                    final isDisputed = p.status == PaymentStatus.disputed;

                    return LandaEntrance(
                      index: index,
                      child: ListTile(
                        tileColor: AppTheme.surfaceColor(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: AppTheme.borderColor(context),
                          ),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: isDisputed
                              ? AppTheme.disputeSurfaceColor
                              : isReleased
                              ? AppTheme.successSurfaceColor
                              : AppTheme.vacantSurfaceColor,
                          child: Icon(
                            isDisputed
                                ? Icons.gavel
                                : isReleased
                                ? Icons.verified
                                : Icons.lock_clock,
                            color: isDisputed
                                ? AppTheme.disputeColor
                                : isReleased
                                ? AppTheme.successColor
                                : AppTheme.primaryColor,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          LandaCurrency.format(p.amount),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        subtitle: Text(
                          p.status.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Colors.grey,
                        ),
                        onTap: () {
                          LandaHaptics.tap();
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            builder: (_) => PaymentReceiptModal(payment: p),
                          );
                        },
                      ),
                    );
                  },
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: AppTheme.cornerLg,
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: Text(
                    'No payment receipts found.',
                    style: AppTheme.bodyText(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
