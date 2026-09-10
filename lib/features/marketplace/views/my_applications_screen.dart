import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../messaging/views/widgets/message_action_button.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../controllers/marketplace_controller.dart';
import '../models/marketplace_models.dart';
import 'application_status_pill.dart';

/// The tenant's own submitted applications.
class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen>
    with AutoRefreshMixin<MyApplicationsScreen> {
  /// Polls while open. Every row here is waiting on a landlord's decision,
  /// which arrives on their phone rather than this one.
  @override
  Duration? get autoRefreshInterval => kOasisPollInterval;

  @override
  Future<void> onAutoRefresh() =>
      context.read<MarketplaceController>().loadTenantApplications();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MarketplaceController>();
    final primaryTextColor = AppTheme.primaryTextColor(context);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: primaryTextColor),
        title: Text(
          'My applications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryTextColor,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: controller.loadTenantApplications,
        child: _buildBody(context, controller),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MarketplaceController controller) {
    final applications = controller.tenantApplications;

    if (!controller.hasLoadedTenantApplications ||
        (controller.isLoading && applications.isEmpty)) {
      return const OasisContentSwitcher(
        stateKey: 'loading',
        child: OasisSkeletonList(
          hasAvatar: true,
          padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
        ),
      );
    }

    // A failed load no longer hides inside the empty state: "no applications
    // yet" and "we could not reach the server" are different situations and
    // only one of them is fixed by trying again.
    if (controller.hasError && applications.isEmpty) {
      return OasisContentSwitcher(
        stateKey: 'error',
        child: OasisErrorState(
          message: controller.errorMessage,
          isConnectionError: controller.errorIsConnection,
          onRetry: controller.loadTenantApplications,
          padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
        ),
      );
    }

    if (applications.isEmpty) {
      return OasisContentSwitcher(
        stateKey: 'empty',
        child: OasisEmptyState(
          icon: Icons.description_outlined,
          title: 'No applications yet',
          message:
              'Apply for a unit from the marketplace and track its progress here.',
          actionLabel: 'Browse marketplace',
          actionIcon: Icons.storefront_outlined,
          onAction: () => Navigator.pop(context),
          padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
        ),
      );
    }

    return OasisContentSwitcher(
      stateKey: 'content',
      child: Column(
        children: [
          if (controller.hasError)
            OasisErrorBanner(
              message: controller.errorMessage!,
              isConnectionError: controller.errorIsConnection,
              onRetry: controller.loadTenantApplications,
            ),
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              itemCount: applications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => OasisEntrance(
                index: index,
                child: _ApplicationCard(application: applications[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final RentalApplication application;

  const _ApplicationCard({required this.application});

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
          if (application.rentAmount != null) ...[
            const SizedBox(height: 6),
            Text(
              OasisCurrency.perYear(application.rentAmount),
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ],
          if (application.hasMessage) ...[
            const SizedBox(height: 10),
            Text(
              '“${application.message}”',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontStyle: FontStyle.italic,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _statusHint(application.status),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),

          // Applying is what earns the conversation, not approval and not
          // rent paid. A tenant's questions, when they can inspect, what the
          // service charge covers: are the ones they need answered *before*
          // deciding, so the button is here from the moment they apply.
          if (application.status.canMessage) ...[
            const SizedBox(height: 12),
            MessageActionButton(
              applicationId: application.id,
              label: 'Message landlord',
              expanded: true,
            ),
          ],
        ],
      ),
    );
  }

  static String _statusHint(ApplicationStatus status) {
    switch (status) {
      case ApplicationStatus.pending:
        return 'Waiting for the landlord to review your application. You can '
            'message them while you wait. Nothing is owed until an '
            'agreement is signed.';
      case ApplicationStatus.approved:
        return 'Approved. Check your agreements to review and sign the tenancy agreement.';
      case ApplicationStatus.rejected:
        return 'This application was not accepted. You can apply for other available units.';
      case ApplicationStatus.withdrawn:
        return 'This application was withdrawn.';
      case ApplicationStatus.unknown:
        return 'Status unavailable. Pull to refresh.';
    }
  }
}
