import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/utils/oasis_haptics.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/widgets/oasis_app_bar.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../messaging/views/widgets/message_action_button.dart';
import '../../properties/controllers/landlord_controller.dart';
import '../controllers/marketplace_controller.dart';
import '../models/marketplace_models.dart';
import 'application_status_pill.dart';
import 'approve_application_sheet.dart';

/// Landlord-facing inbox of rental applications, with approve/reject.
class LandlordApplicationsScreen extends StatefulWidget {
  const LandlordApplicationsScreen({super.key});

  @override
  State<LandlordApplicationsScreen> createState() =>
      _LandlordApplicationsScreenState();
}

class _LandlordApplicationsScreenState extends State<LandlordApplicationsScreen>
    with AutoRefreshMixin<LandlordApplicationsScreen> {
  /// Polls while open. Applications land here from tenants at any hour, and
  /// an applicant is waiting on the landlord for every one of them.
  @override
  Duration? get autoRefreshInterval => kOasisPollInterval;

  @override
  Future<void> onAutoRefresh() =>
      context.read<MarketplaceController>().loadLandlordApplications();

  Future<void> _approve(RentalApplication application) async {
    final controller = context.read<MarketplaceController>();
    final terms = await showModalBottomSheet<ApprovalTerms>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ApproveApplicationSheet(application: application),
    );
    if (terms == null || !mounted) return;

    final success = await controller.approveApplication(
      applicationId: application.id,
      startDate: terms.startDate,
      endDate: terms.endDate,
      rules: terms.rules,
    );
    if (!mounted) return;

    if (success) {
      OasisToast.success(
        context,
        'Application approved. A pending tenancy agreement has been sent to the tenant.',
      );
      // Approval creates an agreement and occupies the unit server-side, so
      // refresh the screens that render those, and this list, whose row is
      // now in a different state than the one the decision echoed back.
      await refreshNow();
      if (!mounted) return;
      context.read<AgreementController>().loadAgreements();
      context.read<LandlordController>().loadLandlordProperties();
    } else if (controller.errorMessage != null) {
      OasisToast.error(context, controller.errorMessage!);
    }
  }

  Future<void> _reject(RentalApplication application) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: const StadiumBorder(),
        title: Text(
          'Reject application?',
          style: AppTheme.sectionTitle(context, color: AppTheme.primaryColor),
        ),
        content: Text(
          'This will decline ${application.tenantEmail ?? 'this tenant'}\'s '
          'application for Unit ${application.unitNumber}. They will be notified.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.disputeColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Reject',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final controller = context.read<MarketplaceController>();
    final success = await controller.rejectApplication(application.id);
    if (!mounted) return;

    if (success) {
      OasisToast.success(context, 'Application rejected.');
      await refreshNow();
    } else if (controller.errorMessage != null) {
      OasisToast.error(context, controller.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MarketplaceController>();

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const OasisAppBar(),
      body: RefreshIndicator(
        onRefresh: controller.loadLandlordApplications,
        child: Column(
          // Without stretch the header Padding only gets loose width
          // constraints and the outer Column's default centre alignment wins,
          // which visually centres the heading despite the inner start.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Applications',
                    style: AppTheme.screenTitle(
                      context,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    controller.pendingLandlordApplicationCount > 0
                        ? '${controller.pendingLandlordApplicationCount} awaiting your review'
                        : 'Tenant applications for your available units.',
                    style: AppTheme.bodyText(context),
                  ),
                ],
              ),
            ),
            _StatusFilterBar(controller: controller),
            Expanded(child: _buildBody(context, controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MarketplaceController controller) {
    final applications = controller.landlordApplications;

    // Skeleton until the first fetch settles: including the window between
    // mount and the post-frame callback that starts it.
    if (!controller.hasLoadedLandlordApplications ||
        (controller.isLoading && applications.isEmpty)) {
      return const OasisContentSwitcher(
        stateKey: 'loading',
        child: OasisSkeletonList(hasAvatar: true, hasAction: true),
      );
    }

    if (controller.hasError && applications.isEmpty) {
      return OasisContentSwitcher(
        stateKey: 'error',
        child: OasisErrorState(
          message: controller.errorMessage,
          isConnectionError: controller.errorIsConnection,
          onRetry: controller.loadLandlordApplications,
        ),
      );
    }

    if (applications.isEmpty) {
      final filtered = controller.landlordStatusFilter != null;
      return OasisContentSwitcher(
        stateKey: 'empty',
        child: OasisEmptyState(
          icon: filtered ? Icons.filter_alt_off_outlined : Icons.inbox_outlined,
          title: filtered ? 'Nothing with that status' : 'No applications yet',
          message: filtered
              ? 'Clear the filter to see every application you have received.'
              : 'When tenants apply for your available units, their applications appear here.',
          actionLabel: filtered ? 'Show all' : 'Refresh',
          actionIcon: filtered
              ? Icons.filter_alt_off_rounded
              : Icons.refresh_rounded,
          onAction: filtered
              ? () => controller.setLandlordStatusFilter(null)
              : controller.loadLandlordApplications,
        ),
      );
    }

    return OasisContentSwitcher(
      stateKey: 'content',
      child: Column(
        children: [
          // The list is still usable, so a failed refresh gets a banner
          // rather than replacing everything with an error page.
          if (controller.hasError)
            OasisErrorBanner(
              message: controller.errorMessage!,
              isConnectionError: controller.errorIsConnection,
              onRetry: controller.loadLandlordApplications,
            ),
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              itemCount: applications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final application = applications[index];
                return OasisEntrance(
                  index: index,
                  child: _LandlordApplicationCard(
                    application: application,
                    // Only a decision in flight disables the buttons; a
                    // background list refresh must not grey out an otherwise
                    // usable card.
                    isBusy: controller.isDecidingApplication,
                    // Spinner belongs on the one button that was pressed.
                    isApproving:
                        controller.decidingApplicationId == application.id &&
                        controller.decidingIsApproval,
                    isRejecting:
                        controller.decidingApplicationId == application.id &&
                        !controller.decidingIsApproval,
                    onApprove: () => _approve(application),
                    onReject: () => _reject(application),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  final MarketplaceController controller;

  const _StatusFilterBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    const statuses = [
      ApplicationStatus.pending,
      ApplicationStatus.approved,
      ApplicationStatus.rejected,
    ];

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          _Chip(
            label: 'All',
            selected: controller.landlordStatusFilter == null,
            onSelected: (_) => controller.setLandlordStatusFilter(null),
          ),
          const SizedBox(width: 8),
          for (final status in statuses) ...[
            _Chip(
              label: status.label[0] + status.label.substring(1).toLowerCase(),
              selected: controller.landlordStatusFilter == status,
              onSelected: (selected) =>
                  controller.setLandlordStatusFilter(selected ? status : null),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (value) {
      OasisHaptics.select();
      onSelected(value);
    },
    showCheckmark: false,
    labelStyle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: selected ? Colors.white : AppTheme.secondaryTextColor(context),
    ),
    backgroundColor: AppTheme.surfaceColor(context),
    selectedColor: AppTheme.actionColor,
    side: BorderSide(
      color: selected ? AppTheme.actionColor : AppTheme.borderColor(context),
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool emphasized;
  final bool muted;

  const _DetailRow({
    required this.icon,
    required this.text,
    this.emphasized = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: muted
              ? AppTheme.mutedTextColor(context)
              : AppTheme.secondaryTextColor(context),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal,
              fontStyle: muted ? FontStyle.italic : FontStyle.normal,
              color: emphasized
                  ? AppTheme.primaryTextColor(context)
                  : muted
                  ? AppTheme.mutedTextColor(context)
                  : AppTheme.secondaryTextColor(context),
            ),
          ),
        ),
      ],
    ),
  );
}

String _relativeTime(String isoTimestamp) {
  final parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return '';
  final diff = DateTime.now().difference(parsed.toLocal());
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return 'on ${isoTimestamp.split('T').first}';
}

class _LandlordApplicationCard extends StatelessWidget {
  final RentalApplication application;
  final bool isBusy;

  /// This card's approval is in flight: its Approve button shows a spinner.
  final bool isApproving;

  /// This card's rejection is in flight.
  final bool isRejecting;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _LandlordApplicationCard({
    required this.application,
    required this.isBusy,
    this.isApproving = false,
    this.isRejecting = false,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final propertyName = application.property?.name ?? 'Property';

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
          Row(
            children: [
              Expanded(
                child: Text(
                  application.unitNumber.isEmpty
                      ? propertyName
                      : '$propertyName · Unit ${application.unitNumber}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ApplicationStatusPill(status: application.status),
            ],
          ),
          const SizedBox(height: 10),

          // Applicant identity. Deciding on an application without knowing who
          // it is from is not actionable, so when the payload carries nothing
          // we say so rather than quietly rendering an empty card.
          if (application.hasApplicantDetails) ...[
            if (application.tenantName != null)
              _DetailRow(
                icon: Icons.person_outline,
                text: application.tenantName!,
                emphasized: true,
              ),
            if (application.tenantEmail != null)
              _DetailRow(
                icon: Icons.mail_outline,
                text: application.tenantEmail!,
              ),
            if (application.tenantPhone != null)
              _DetailRow(
                icon: Icons.phone_outlined,
                text: application.tenantPhone!,
              ),
          ] else
            _DetailRow(
              icon: Icons.person_off_outlined,
              text: 'Applicant details not provided by the server',
              muted: true,
            ),

          if (application.tenantVerificationStatus != null)
            _DetailRow(
              icon:
                  application.tenantVerificationStatus!.toUpperCase() ==
                      'VERIFIED'
                  ? Icons.verified_user_outlined
                  : Icons.gpp_maybe_outlined,
              text: 'Identity ${application.tenantVerificationStatus!}',
            ),
          if (application.rentAmount != null)
            _DetailRow(
              icon: Icons.payments_outlined,
              text: OasisCurrency.perYear(application.rentAmount),
            ),
          if (application.createdAt.isNotEmpty)
            _DetailRow(
              icon: Icons.schedule_outlined,
              text: 'Applied ${_relativeTime(application.createdAt)}',
            ),

          // The applicant's own note, if they left one.
          if (application.hasMessage) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.vacantSurface(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.format_quote,
                    size: 15,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      application.message,
                      // Explicit rather than inherited: this is a stranger's
                      // words, and the landlord is deciding a tenancy on
                      // them. It does not get to depend on whatever
                      // DefaultTextStyle happens to be overhead.
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.readingTextColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Open from the application, not from the approval, and in both
          // directions. A landlord deciding on an applicant usually wants to
          // ask them something first (when they want to move in, whether
          // they have seen the flat), and having to approve them to do it is
          // the wrong way round.
          if (application.status.canMessage) ...[
            const SizedBox(height: 14),
            MessageActionButton(
              applicationId: application.id,
              label: 'Message tenant',
              expanded: true,
            ),
          ],

          // Only a still-pending application can be acted on; the backend
          // rejects approve/reject on settled ones.
          if (application.status.isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OasisButton(
                    label: 'Reject',
                    outlined: true,
                    color: AppTheme.disputeColor,
                    isBusy: isRejecting,
                    onPressed: isBusy ? null : onReject,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OasisButton(
                    label: 'Approve',
                    isBusy: isApproving,
                    onPressed: isBusy ? null : onApprove,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
