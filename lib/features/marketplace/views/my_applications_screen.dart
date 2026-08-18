import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../controllers/marketplace_controller.dart';
import '../models/marketplace_models.dart';
import 'application_status_pill.dart';

/// The tenant's own submitted applications.
class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<MarketplaceController>().loadTenantApplications(),
    );
  }

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
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => LandaShimmer(
          child: Container(
            height: 92,
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
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
        children: [
          Icon(
            Icons.description_outlined,
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
            'Apply for a unit from the marketplace and track its progress here.',
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: applications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _ApplicationCard(application: applications[index]),
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
              '₦${application.rentAmount}/yr',
              style: TextStyle(
                fontSize: 13,
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
        ],
      ),
    );
  }

  static String _statusHint(ApplicationStatus status) {
    switch (status) {
      case ApplicationStatus.pending:
        return 'Waiting for the landlord to review your application.';
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
