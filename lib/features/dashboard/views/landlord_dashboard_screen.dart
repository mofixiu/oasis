import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../agreements/views/tenancy_agreement_modal.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../auth/views/identity_verification_screen.dart';
import '../../marketplace/controllers/marketplace_controller.dart';
import '../../messaging/controllers/messaging_controller.dart';
import '../../notifications/controllers/notification_controller.dart';
import '../../payments/controllers/payment_controller.dart';
import '../../payouts/controllers/payout_controller.dart';
import '../../vault/controllers/vault_controller.dart';
import '../../properties/controllers/landlord_controller.dart';
import '../../properties/models/property_model.dart';
import '../../properties/views/my_properties_screen.dart';
import 'widgets/add_property_modal.dart';
import 'widgets/landlord_header.dart';
import '../../../core/utils/fade_page_route.dart';

class LandlordDashboardScreen extends StatefulWidget {
  const LandlordDashboardScreen({super.key});

  @override
  State<LandlordDashboardScreen> createState() =>
      _LandlordDashboardScreenState();
}

class _LandlordDashboardScreenState extends State<LandlordDashboardScreen>
    with AutoRefreshMixin<LandlordDashboardScreen> {
  @override
  Future<void> onAutoRefresh() => _loadAllData();

  /// Awaited so pull-to-refresh and the retry button both finish when the
  /// data actually has.
  Future<void> _loadAllData() async {
    await Future.wait([
      context.read<LandlordController>().loadLandlordProperties(),
      context.read<AgreementController>().loadAgreements(),
      context.read<PaymentController>().loadPayments(),
      context.read<AuthController>().refreshProfile(),
      context.read<NotificationController>().loadNotifications(),
      // Drives the dot on the Messages button in the app bar. Without it the
      // count is only known once the inbox has been opened, which is exactly
      // the case the dot exists to cover.
      context.read<MessagingController>().refreshUnreadCount(),
      // Drives the pending-applications dot on the bottom nav, so it must be
      // fresh on landing rather than only after visiting that tab.
      context.read<MarketplaceController>().loadLandlordApplications(),
      // Keeps the Settings payout row accurate without waiting for the
      // landlord to be blocked at execution time.
      context.read<PayoutController>().loadPayoutAccount(),
      // Same reason: the Settings row should say whether a vault PIN exists
      // before the landlord is stopped at a withdrawal.
      context.read<VaultController>().loadPinStatus(),
    ]);
  }

  void _showAddPropertyModal() => openAddPropertyFlow(context);

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
    // Only agreements still waiting on a signature belong here. Signed ones
    // are a record and live in the profile: see [AgreementBucket].
    final openAgreements = agreementCtrl.actionRequiredAgreements;

    // Same rule as the tenant dashboard: nothing loaded at all is a dead page
    // and earns the full retry state, a partial failure only earns a banner.
    final failedControllers = <LoadFailureState>[
      landlordCtrl,
      agreementCtrl,
    ].where((c) => c.hasError).toList();
    final isOffline = failedControllers.any((c) => c.errorIsConnection);
    final failureMessage = failedControllers.isEmpty
        ? null
        : failedControllers.first.errorMessage;
    final hasAnyContent =
        landlordCtrl.properties.isNotEmpty ||
        agreementCtrl.agreements.isNotEmpty;

    if (!landlordCtrl.isLoading && failureMessage != null && !hasAnyContent) {
      return Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        appBar: const LandaAppBar(),
        body: RefreshIndicator(
          onRefresh: _loadAllData,
          child: LandaErrorState(
            message: failureMessage,
            isConnectionError: isOffline,
            onRetry: _loadAllData,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (failureMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LandaErrorBanner(
                    message: failureMessage,
                    isConnectionError: isOffline,
                    onRetry: _loadAllData,
                  ),
                ),
              // Verification prompt. Only shown while unverified, once the
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
                    color: AppTheme.vacantSurface(context),
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
                            FadePageRoute(
                              page: const IdentityVerificationScreen(),
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

              if (openAgreements.isNotEmpty) ...[
                const Text(
                  'AGREEMENTS TO SIGN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  children: openAgreements.map((agreement) {
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

              // Properties Summary Box
              //
              // A box rather than the full list: the portfolio grows without
              // limit, and an unbounded list here buries the things that
              // actually need acting on. The numbers are the part a landlord
              // scans on landing; the properties themselves are one tap away.
              Text('MY PROPERTIES', style: AppTheme.labelText(context)),
              const SizedBox(height: 12),
              if (!landlordCtrl.hasLoaded(LandlordController.kPropertiesKey) ||
                  (landlordCtrl.isLoading && landlordCtrl.properties.isEmpty))
                const LandaCardSkeleton()
              else if (landlordCtrl.properties.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: AppTheme.cornerLg,
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: LandaEmptyState(
                    icon: Icons.apartment_outlined,
                    title: 'No properties yet',
                    message:
                        'Add your first property to start listing units and receiving applications.',
                    actionLabel: 'Add property',
                    actionIcon: Icons.add_rounded,
                    onAction: _showAddPropertyModal,
                    scrollable: false,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  ),
                )
              else
                _PortfolioBox(
                  properties: landlordCtrl.properties,
                  unitsByProperty: landlordCtrl.propertyUnits,
                  onTap: () => Navigator.push(
                    context,
                    FadePageRoute(page: const MyPropertiesScreen()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The portfolio at a glance: how much there is, and how much of it is let.
///
/// Occupancy is the number a landlord actually wants on landing: an empty
/// unit is money not being made, so it leads, and the property count sits
/// beside it as context rather than the headline.
class _PortfolioBox extends StatelessWidget {
  final List<PropertyModel> properties;
  final Map<String, List<UnitModel>> unitsByProperty;
  final VoidCallback onTap;

  const _PortfolioBox({
    required this.properties,
    required this.unitsByProperty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final units = properties
        .expand((p) => unitsByProperty[p.id] ?? const <UnitModel>[])
        .toList();
    final occupied = units.where((u) => u.isOccupied).length;
    final needingPhotos = properties.where((p) => p.needsPhotos).length;

    return LandaPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(color: AppTheme.borderColor(context)),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: AppTheme.cornerMd,
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${properties.length} '
                        '${properties.length == 1 ? 'property' : 'properties'}',
                        style: AppTheme.sectionTitle(context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        units.isEmpty
                            ? 'No units added yet'
                            : '$occupied of ${units.length} '
                                  '${units.length == 1 ? 'unit' : 'units'} let',
                        style: AppTheme.labelText(
                          context,
                          color: AppTheme.secondaryTextColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.mutedTextColor(context),
                ),
              ],
            ),
            // The one thing in here that needs fixing, surfaced on the box so
            // it is not hidden a tap away: a listing with no photos never
            // reaches the marketplace at all.
            if (needingPhotos > 0) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.photo_camera_outlined,
                    size: 15,
                    color: AppTheme.warningColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      needingPhotos == 1
                          ? '1 property needs photos before it can be listed.'
                          : '$needingPhotos properties need photos before they '
                                'can be listed.',
                      style: AppTheme.labelText(
                        context,
                        color: AppTheme.warningColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
