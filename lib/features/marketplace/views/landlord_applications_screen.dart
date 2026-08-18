import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../agreements/controllers/agreement_controller.dart';
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

class _LandlordApplicationsScreenState
    extends State<LandlordApplicationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<MarketplaceController>().loadLandlordApplications(),
    );
  }

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
      LandaToast.success(
        context,
        'Application approved. A pending tenancy agreement has been sent to the tenant.',
      );
      // Approval creates an agreement and occupies the unit server-side, so
      // refresh the screens that render those.
      context.read<AgreementController>().loadAgreements();
      context.read<LandlordController>().loadLandlordProperties();
    } else if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  Future<void> _reject(RentalApplication application) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Reject application?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
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
      LandaToast.success(context, 'Application rejected.');
    } else if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MarketplaceController>();

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(),
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
                  const Text(
                    'Applications',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.pendingLandlordApplicationCount > 0
                        ? '${controller.pendingLandlordApplicationCount} awaiting your review'
                        : 'Tenant applications for your available units.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.secondaryTextColor(context),
                    ),
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

    // Skeleton until the first fetch settles — including the window between
    // mount and the post-frame callback that starts it.
    if (!controller.hasLoadedLandlordApplications ||
        (controller.isLoading && applications.isEmpty)) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => LandaShimmer(
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    if (applications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 70, 32, 100),
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: AppTheme.mutedTextColor(context),
          ),
          const SizedBox(height: 16),
          Text(
            controller.errorMessage ?? 'No applications yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When tenants apply for your available units, their applications appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: applications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final application = applications[index];
        return _LandlordApplicationCard(
          application: application,
          isBusy: controller.isLoading,
          onApprove: () => _approve(application),
          onReject: () => _reject(application),
        );
      },
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
    onSelected: onSelected,
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
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _LandlordApplicationCard({
    required this.application,
    required this.isBusy,
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor(context)),
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

          if (application.rentAmount != null)
            _DetailRow(
              icon: Icons.payments_outlined,
              text: '₦${application.rentAmount}/yr',
            ),
          if (application.createdAt.isNotEmpty)
            _DetailRow(
              icon: Icons.schedule_outlined,
              text: 'Applied ${_relativeTime(application.createdAt)}',
            ),

          // Only a still-pending application can be acted on; the backend
          // rejects approve/reject on settled ones.
          if (application.status.isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isBusy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.disputeColor,
                      side: BorderSide(
                        color: AppTheme.disputeColor.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isBusy ? null : onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.actionColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Approve',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
