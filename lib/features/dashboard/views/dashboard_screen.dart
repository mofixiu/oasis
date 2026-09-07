import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/load_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_animated_list.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../agreements/models/agreement_model.dart';
import '../../agreements/views/tenancy_agreement_modal.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../../auth/views/identity_verification_screen.dart';
import '../../fix/views/fix_screen.dart';
import '../../messaging/controllers/messaging_controller.dart';
import '../../notifications/controllers/notification_controller.dart';
import '../../payments/controllers/payment_controller.dart';
import '../../properties/models/property_model.dart';
import '../../shortlets/controllers/shortlet_controller.dart';
import '../../shortlets/models/shortlet_models.dart';
import '../../shortlets/views/my_shortlet_bookings_screen.dart';
import 'widgets/my_unit_card.dart';
import 'widgets/upcoming_stays_card.dart';
import '../../properties/controllers/landlord_controller.dart';
import '../../vault/controllers/vault_controller.dart';
import '../../../core/utils/fade_page_route.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// Shown when a tenant has a unit but no agreement on it yet.
///
/// `GET /tenant/assigned-unit/` is the only thing that knows about this state,
/// and it names one unit, which is fine here, because a tenant with no
/// agreements has nothing else to show.
class _AssignedUnitFallbackCard extends StatelessWidget {
  final UnitModel unit;

  const _AssignedUnitFallbackCard({required this.unit});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
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
            Expanded(
              child: Text(
                unit.property?.name ?? 'Assigned property',
                style: AppTheme.sectionTitle(
                  context,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.successSurface(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Unit ${unit.unitNumber}',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.successColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'RENT',
          style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
        ),
        const SizedBox(height: 3),
        Text(
          LandaCurrency.perYear(unit.rentAmount),
          style: AppTheme.sectionTitle(context),
        ),
        const SizedBox(height: 14),
        Text(
          'Your landlord has not sent the tenancy agreement yet. It will '
          'appear here to sign.',
          style: AppTheme.bodyText(context),
        ),
      ],
    ),
  );
}

class _NoUnitCard extends StatelessWidget {
  const _NoUnitCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: AppTheme.cornerLg,
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Row(
      children: [
        Icon(
          Icons.home_work_outlined,
          size: 36,
          color: AppTheme.mutedTextColor(context),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No unit assigned yet', style: AppTheme.cardTitle(context)),
              const SizedBox(height: 2),
              Text(
                'Your landlord will assign your unit and send a tenancy '
                'agreement.',
                style: AppTheme.bodyText(context),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TenantAgreementCard extends StatelessWidget {
  final TenancyAgreementModel agreement;

  const _TenantAgreementCard({required this.agreement});

  @override
  Widget build(BuildContext context) {
    // Green only once the tenancy is actually running. An agreement that is
    // signed but unpaid is a task, and colouring it as done is what let a
    // tenant believe they had moved in.
    final isLive = agreement.isExecuted;
    final actionLabel = agreement.awaitingFirstRent
        ? 'Pay the first rent to start your tenancy'
        : agreement.canPayRent
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
              color: isLive ? AppTheme.successColor : AppTheme.warningColor,
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

class _DashboardScreenState extends State<DashboardScreen>
    with AutoRefreshMixin<DashboardScreen> {
  @override
  Future<void> onAutoRefresh() => _loadTenantData();

  /// Awaits every fetch so pull-to-refresh and the retry button both know
  /// when the dashboard has actually finished reloading.
  Future<void> _loadTenantData() async {
    await Future.wait([
      context.read<LandlordController>().loadTenantAssignedUnit(),
      context.read<AgreementController>().loadAgreements(),
      context.read<PaymentController>().loadPayments(),
      context.read<AuthController>().refreshProfile(),
      context.read<NotificationController>().loadNotifications(),
      // Same reason as the landlord dashboard: the Messages dot cannot wait
      // for the tenant to open the inbox before it knows there is anything
      // in it.
      context.read<MessagingController>().refreshUnreadCount(),
      // Drives the reminder-emails switch in Settings.
      context.read<NotificationController>().loadPreferences(),
      // The pending-payments section shows how far the vault has got towards
      // the next rent bill, so the balance has to be here too.
      context.read<VaultController>().loadVault(),
      context.read<VaultController>().loadPinStatus(),
      // The per-unit savings plan lives on the device and is keyed to
      // this user, so it loads with everything else the vault needs.
      context.read<VaultController>().loadAllocations(
        context.read<AuthController>().currentUser?.id ?? '',
      ),
      // Confirmed stays. A tenant who has just paid for somewhere to sleep
      // this weekend looks at their dashboard for it, before this, the only
      // trace of a successful short-let payment was two taps deep under the
      // Stays tab, which read as the payment not having worked.
      context.read<ShortLetController>().loadMyBookings(),
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
    // The dashboard lists only agreements still waiting on a signature.
    // Once signed, an agreement is a record rather than a task, and lives in
    // the profile: see [AgreementBucket].
    final tenantAgreements = agreementCtrl.actionRequiredAgreements;
    // Every unit this tenant holds. See AgreementController.tenancies for why
    // this comes from agreements rather than the assigned-unit endpoint.
    final tenancies = agreementCtrl.tenancies;
    // The unit Fix acts on: the first tenancy, or the assigned unit for a
    // tenant whose landlord has not sent an agreement yet. Null means this
    // tenant is not in a property, which is what hides the card entirely.
    final fixUnitId = tenancies.isNotEmpty
        ? tenancies.first.latest.unit
        : assignedUnit?.id;
    // Paid, confirmed and not yet checked out of: the stays a tenant would
    // be annoyed to have to go looking for.
    final upcomingStays = context
        .select<ShortLetController, List<ShortLetBooking>>(
          (controller) => controller.confirmedStays,
        );
    final isVerified = user?.verificationStatus == VerificationStatus.verified;
    final isLoading =
        landlordCtrl.isLoading ||
        agreementCtrl.isLoading ||
        paymentCtrl.isLoading;

    // The dashboard is stitched from three independent fetches, so it reports
    // failure the way the user experiences it: if nothing at all loaded it is
    // a dead page and gets the full retry state; if some of it loaded, the
    // failure is a banner over the content that did arrive.
    // Annotated rather than inferred: the three controllers mix in different
    // combinations, and Dart's least-upper-bound lands on ChangeNotifier,
    // which has none of the failure getters this list exists to read.
    final failedControllers = <LoadFailureState>[
      landlordCtrl,
      agreementCtrl,
      paymentCtrl,
    ].where((c) => c.hasError).toList();
    // Deliberately the unfiltered list: a tenant whose only agreement is
    // already signed still has a working page, not a dead one.
    final hasAnyContent =
        assignedUnit != null ||
        agreementCtrl.agreements.isNotEmpty ||
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

              // The tenant's homes: one card per unit.
              //
              // Built from agreements rather than `GET /tenant/assigned-unit/`,
              // which answers with *the first* unit a tenant is assigned and so
              // showed a two-home tenant only one of them. The endpoint is
              // still the fallback for a tenant assigned a unit before any
              // agreement exists.
              Text(
                tenancies.length > 1 ? 'MY UNITS' : 'MY ASSIGNED UNIT',
                style: AppTheme.labelText(context),
              ),
              const SizedBox(height: 8),
              // Shaped like the unit card that lands here: a pill for the
              // unit number, a rent figure, a due-date chip, rather than the
              // featureless slab that used to sit in this space and read as
              // an error state.
              if ((!agreementCtrl.hasLoaded() || isLoading) &&
                  tenancies.isEmpty &&
                  assignedUnit == null)
                const LandaContentSwitcher(
                  stateKey: 'unit-loading',
                  child: LandaCardSkeleton(hasPill: true),
                )
              else if (tenancies.isNotEmpty)
                // Animated by unit, so a tenancy that ends collapses out of
                // the list instead of the ones below it snapping upwards.
                LandaAnimatedList(
                  items: tenancies,
                  keyOf: (tenancy) => tenancy.latest.unit,
                  spacing: 12,
                  itemBuilder: (_, tenancy, index) => LandaEntrance(
                    index: index,
                    child: MyUnitCard(tenancy: tenancy),
                  ),
                )
              else if (assignedUnit != null)
                _AssignedUnitFallbackCard(unit: assignedUnit)
              else
                const _NoUnitCard(),
              const SizedBox(height: 12),

              // Repairs. A card rather than a bottom-nav tab: a tenant needs
              // an artisan a handful of times a year, and a permanent slot in
              // the bar would give Fix more standing than rent or their
              // tenancy. It sits under the units because that is what it acts
              // on, and only appears once there is one.
              //
              // Fix is a repair *to the home you live in*: every job the
              // backend accepts is keyed to a unit, and a tenant who holds
              // none has nothing to raise one against. Shown anyway, the card
              // advertised a feature that could only end in an empty screen.
              if (fixUnitId != null) _FixCard(unitId: fixUnitId),

              // Only when there is one. A tenant who has never booked a stay
              // does not need a permanent advert for the feature on the page
              // about their home: the Stays tab already exists for that.
              if (upcomingStays.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('UPCOMING STAYS', style: AppTheme.labelText(context)),
                const SizedBox(height: 8),
                LandaAnimatedList(
                  items: upcomingStays,
                  keyOf: (stay) => stay.id,
                  spacing: 10,
                  itemBuilder: (_, stay, index) => LandaEntrance(
                    index: index,
                    child: UpcomingStayCard(
                      booking: stay,
                      onTap: () => Navigator.push(
                        context,
                        FadePageRoute(page: const MyShortLetBookingsScreen()),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Signing is the only thing left on this page. Rent, its date
              // and every receipt now live on Payments: one place for money
              // instead of two that disagreed.
              if ((!agreementCtrl.hasLoaded() || isLoading) &&
                  tenantAgreements.isEmpty) ...[
                Text('AGREEMENTS TO SIGN', style: AppTheme.labelText(context)),
                const SizedBox(height: 8),
                // The agreement card is a title, a status line and a
                // full-width button, so that is the silhouette that waits.
                const LandaCardSkeleton(hasPill: false, hasAction: true),
              ] else if (tenantAgreements.isNotEmpty) ...[
                Text('AGREEMENTS TO SIGN', style: AppTheme.labelText(context)),
                const SizedBox(height: 8),
                // The one that matters most: signing an agreement takes it
                // off this list, and a card that simply disappears under the
                // finger that signed it reads as a glitch rather than as the
                // task being done.
                LandaAnimatedList(
                  items: tenantAgreements,
                  keyOf: (agreement) => agreement.id,
                  spacing: 10,
                  itemBuilder: (_, agreement, index) => LandaEntrance(
                    index: index,
                    child: _TenantAgreementCard(agreement: agreement),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry point into Fix from the tenant dashboard.
///
/// Carries a count when something is waiting on the tenant, a price to accept
/// or work to sign off, because both cost money to ignore. An unpaid quote
/// means the repair never starts, and an unconfirmed job means an artisan who
/// has done the work has not been paid.
class _FixCard extends StatelessWidget {
  /// The unit to open Fix on. Never null: the dashboard hides the card
  /// entirely for a tenant who holds no unit, because every Fix job the
  /// backend accepts is raised against one.
  final String unitId;

  const _FixCard({required this.unitId});

  @override
  Widget build(BuildContext context) {
    // No count any more. It used to badge repairs waiting on the tenant:
    // a quote to accept, a finished job to confirm, and API guide 18
    // removed the workflow those belonged to. Fix is a directory now, and a
    // directory has nothing waiting in it.
    return LandaPressable(
      onTap: () => Navigator.push(
        context,
        FadePageRoute(page: FixScreen(initialUnitId: unitId)),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(color: AppTheme.borderColor(context)),
          boxShadow: AppTheme.cardShadow(context),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.actionColor.withValues(alpha: 0.12),
                borderRadius: AppTheme.cornerMd,
              ),
              child: const Icon(
                Icons.handyman_outlined,
                color: AppTheme.actionColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fix', style: AppTheme.sectionTitle(context)),
                  const SizedBox(height: 3),
                  // No longer promises a quote or escrow: Landa introduces
                  // the artisan and stops there.
                  Text(
                    'Find a verified plumber, electrician or cleaner near '
                    'you and call them directly.',
                    style: AppTheme.bodyText(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.mutedTextColor(context),
            ),
          ],
        ),
      ),
    );
  }
}
