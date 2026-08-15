import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/auth_token_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../agreements/views/tenancy_agreement_modal.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../auth/views/identity_verification_screen.dart';
import '../../payments/controllers/payment_controller.dart';
import '../../properties/controllers/landlord_controller.dart';
import '../../properties/models/property_model.dart';
import '../../properties/views/property_detail_screen.dart';
import '../../properties/views/widgets/add_units_modal.dart';
import 'widgets/add_property_modal.dart';
import 'widgets/landlord_header.dart';

class LandlordDashboardScreen extends StatefulWidget {
  const LandlordDashboardScreen({super.key});

  @override
  State<LandlordDashboardScreen> createState() =>
      _LandlordDashboardScreenState();
}

class _LandlordDashboardScreenState extends State<LandlordDashboardScreen> {
  bool _isVerifiedBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
      _checkBannerState();
    });
  }

  void _checkBannerState() async {
    final dismissed = await AuthTokenStorage.isVerifiedBannerDismissed();
    if (mounted) {
      setState(() => _isVerifiedBannerDismissed = dismissed);
    }
  }

  void _loadAllData() {
    context.read<LandlordController>().loadLandlordProperties();
    context.read<AgreementController>().loadAgreements();
    context.read<PaymentController>().loadPayments();
    context.read<AuthController>().refreshProfile();
  }

  void _showAddPropertyModal() {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.8;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints.tightFor(height: sheetHeight),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AddPropertyModal(),
    );
  }

  void _showAddUnitModal(PropertyModel property) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.8;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints.tightFor(height: sheetHeight),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddUnitsModal(property: property),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landlordCtrl = context.watch<LandlordController>();
    final agreementCtrl = context.watch<AgreementController>();
    final authCtrl = context.watch<AuthController>();
    final user = authCtrl.currentUser;
    final isVerified = user?.verificationStatus == VerificationStatus.verified;

    final pendingCounterSignatures = agreementCtrl.agreements
        .where((a) => a.awaitingLandlordSignature)
        .toList();
    final secondaryTextColor = AppTheme.secondaryTextColor(context);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(),
      body: RefreshIndicator(
        onRefresh: () async => _loadAllData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
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
                                    ? 'Your NIN & selfie identity check is complete.'
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

              const LandlordHeader(),
              const SizedBox(height: 24),

              // Agreements the tenant has signed while still PENDING.
              if (pendingCounterSignatures.isNotEmpty) ...[
                const Text(
                  'PENDING COUNTER-SIGNATURES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.warningColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  children: pendingCounterSignatures.map((a) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.edit_note,
                                color: Colors.amber.shade900,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tenant Signed Unit ${a.unitNumber}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tenant (${a.tenantEmail}) signed this agreement. Counter-sign to execute it and unlock rent payment.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: agreementCtrl.isLoading
                                  ? null
                                  : () async {
                                      final success = await agreementCtrl
                                          .signAgreement(a.id);
                                      if (!context.mounted) return;
                                      if (success) {
                                        LandaToast.success(
                                          context,
                                          'Agreement executed. Rent payment is now unlocked.',
                                        );
                                        _loadAllData();
                                      } else if (agreementCtrl.errorMessage !=
                                          null) {
                                        LandaToast.error(
                                          context,
                                          agreementCtrl.errorMessage!,
                                        );
                                      }
                                    },
                              icon: const Icon(
                                Icons.draw,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Counter-Sign & Execute Agreement',
                                style: TextStyle(
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
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              if (agreementCtrl.agreements.isNotEmpty) ...[
                const Text(
                  'AGREEMENTS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  children: agreementCtrl.agreements.map((agreement) {
                    final isExecuted = agreement.isExecuted;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.borderColor(context),
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          isExecuted
                              ? Icons.verified_outlined
                              : Icons.description_outlined,
                          color: isExecuted
                              ? AppTheme.successColor
                              : AppTheme.warningColor,
                        ),
                        title: Text(
                          'Unit ${agreement.unitNumber} · ${agreement.tenantEmail}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        subtitle: Text(agreement.progressTitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          builder: (_) =>
                              ViewAgreementModal(agreement: agreement),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Properties List Section
              const Text(
                'MY PROPERTIES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              if (landlordCtrl.isLoading && landlordCtrl.properties.isEmpty)
                const ShimmerListSkeleton(count: 2)
              else if (landlordCtrl.properties.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Text('No properties added yet.'),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _showAddPropertyModal,
                          icon: const Icon(
                            Icons.add,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Add Your First Property',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.actionColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Column(
                  children: landlordCtrl.properties.map((prop) {
                    final units = landlordCtrl.propertyUnits[prop.id] ?? [];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManagedPropertyDetailScreen(
                              property: prop,
                              units: units,
                              onAddUnits: () => _showAddUnitModal(prop),
                            ),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor(context),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.borderColor(context),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        prop.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${prop.address}, ${prop.city}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_home_outlined,
                                      color: AppTheme.actionColor,
                                    ),
                                    onPressed: () => _showAddUnitModal(prop),
                                    tooltip: 'Add units in batch',
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Units: ${units.length}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                  Text(
                                    units.any((u) => u.isOccupied)
                                        ? 'Occupied'
                                        : 'Vacant',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: units.any((u) => u.isOccupied)
                                          ? AppTheme.successColor
                                          : AppTheme.vacantColor,
                                    ),
                                  ),
                                ],
                              ),
                              if (units.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: units.map((u) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: u.isOccupied
                                            ? AppTheme.successSurfaceColor
                                            : AppTheme.vacantSurfaceColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Unit ${u.unitNumber} (₦${u.rentAmount})',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: u.isOccupied
                                              ? AppTheme.successColor
                                              : AppTheme.primaryColor,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
