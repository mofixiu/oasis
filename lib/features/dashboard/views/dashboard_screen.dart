import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/auth_token_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../agreements/models/agreement_model.dart';
import '../../agreements/views/tenancy_agreement_modal.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../auth/views/identity_verification_screen.dart';
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
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
  bool _isVerifiedBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTenantData();
      _checkBannerState();
    });
  }

  void _checkBannerState() async {
    final dismissed = await AuthTokenStorage.isVerifiedBannerDismissed();
    if (mounted) {
      setState(() => _isVerifiedBannerDismissed = dismissed);
    }
  }

  void _loadTenantData() {
    context.read<LandlordController>().loadTenantAssignedUnit();
    context.read<AgreementController>().loadAgreements();
    context.read<PaymentController>().loadPayments();
    context.read<AuthController>().refreshProfile();
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

    final displayName = user?.email.split("@").first ?? "tenant";
    final secondaryTextColor = AppTheme.secondaryTextColor(context);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(),
      body: RefreshIndicator(
        onRefresh: () async => _loadTenantData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dismissable Verification Status Banner
              if (!isVerified || !_isVerifiedBannerDismissed) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isVerified
                        ? AppTheme.successSurfaceColor
                        : AppTheme.vacantSurfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isVerified
                          ? AppTheme.successColor.withOpacity(0.45)
                          : AppTheme.vacantColor.withOpacity(0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isVerified ? Icons.verified_user : Icons.gpp_maybe,
                        color: isVerified
                            ? AppTheme.successColor
                            : AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (!isVerified) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const IdentityVerificationScreen(),
                                ),
                              );
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isVerified
                                    ? 'IDENTITY VERIFIED'
                                    : 'IDENTITY UNVERIFIED',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isVerified
                                      ? AppTheme.successColor
                                      : AppTheme.primaryColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isVerified
                                    ? 'Your NIN & selfie verification is active.'
                                    : 'Tap to verify your identity with a selfie and NIN.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isVerified
                                      ? AppTheme.successColor
                                      : AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isVerified)
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: AppTheme.successColor,
                          ),
                          onPressed: () async {
                            await AuthTokenStorage.dismissVerifiedBanner();
                            setState(() => _isVerifiedBannerDismissed = true);
                          },
                          tooltip: 'Dismiss',
                        )
                      else
                        const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ],

              // Single-Line Greeting Header
              Text(
                'Welcome, $displayName',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.blackColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your unit tenancy, sign agreements & track escrow payments.',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              const SizedBox(height: 24),

              // Assigned Unit Section
              const Text(
                'MY ASSIGNED UNIT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
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
                            '₦${assignedUnit.rentAmount}',
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
              const Text(
                'TENANCY AGREEMENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (isLoading && tenantAgreements.isEmpty)
                const ShimmerCardSkeleton()
              else if (tenantAgreements.isNotEmpty)
                Column(
                  children: tenantAgreements
                      .map(
                        (agreement) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TenantAgreementCard(agreement: agreement),
                        ),
                      )
                      .toList(),
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 36,
                        color: Colors.grey,
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'No pending tenancy agreement to sign.',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Recent Payment Transactions Section
              const Text(
                'RECENT PAYMENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
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

                    return ListTile(
                      tileColor: AppTheme.surfaceColor(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppTheme.borderColor(context)),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isDisputed
                            ? Colors.orange.shade50
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
                              ? Colors.orange.shade800
                              : isReleased
                              ? AppTheme.successColor
                              : AppTheme.primaryColor,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        '₦${p.amount}',
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
                    );
                  },
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Text(
                    'No payment receipts found.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
