import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../dashboard/views/widgets/add_property_modal.dart';
import '../controllers/landlord_controller.dart';
import '../models/property_model.dart';
import 'property_detail_screen.dart';
import 'widgets/add_units_modal.dart';
import 'widgets/property_portfolio_card.dart';
import '../../../core/utils/fade_page_route.dart';

/// The landlord's whole portfolio, on a page of its own.
///
/// It used to be an unbounded list at the bottom of the dashboard, which meant
/// the dashboard got longer with every property and the things that actually
/// needed acting on (counter-signatures, applications) were pushed further
/// out of reach. The dashboard now carries a summary box, and everything the
/// list used to do happens here.
class MyPropertiesScreen extends StatefulWidget {
  const MyPropertiesScreen({super.key});

  @override
  State<MyPropertiesScreen> createState() => _MyPropertiesScreenState();
}

class _MyPropertiesScreenState extends State<MyPropertiesScreen>
    with AutoRefreshMixin<MyPropertiesScreen> {
  @override
  Future<void> onAutoRefresh() => _reload();

  Future<void> _reload() =>
      context.read<LandlordController>().loadLandlordProperties();

  void _showAddPropertyModal() => openAddPropertyFlow(context);

  void _showAddUnitModal(PropertyModel property) =>
      AddUnitsModal.open(context, property);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LandlordController>();
    final properties = controller.properties;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
        title: Text('My properties', style: AppTheme.cardTitle(context)),
        actions: [
          IconButton(
            onPressed: _showAddPropertyModal,
            icon: const Icon(Icons.add_rounded, color: AppTheme.actionColor),
            tooltip: 'Add property',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _buildBody(context, controller, properties),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LandlordController controller,
    List<PropertyModel> properties,
  ) {
    if (!controller.hasLoaded(LandlordController.kPropertiesKey) ||
        (controller.isLoading && properties.isEmpty)) {
      return const LandaSkeletonList(count: 3, hasThumbnail: true);
    }

    // A failure with nothing to show is a dead page; a failure with cards
    // already on screen is a banner over them.
    if (controller.hasError && properties.isEmpty) {
      return LandaErrorState(
        message: controller.errorMessage,
        isConnectionError: controller.errorIsConnection,
        onRetry: _reload,
      );
    }

    if (properties.isEmpty) {
      return LandaEmptyState(
        icon: Icons.apartment_outlined,
        title: 'No properties yet',
        message:
            'Add your first property to start listing units and receiving '
            'applications.',
        actionLabel: 'Add property',
        actionIcon: Icons.add_rounded,
        onAction: _showAddPropertyModal,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (controller.hasError)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LandaErrorBanner(
              message: controller.errorMessage!,
              isConnectionError: controller.errorIsConnection,
              onRetry: _reload,
            ),
          ),
        for (final (index, property) in properties.indexed)
          LandaEntrance(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PropertyPortfolioCard(
                property: property,
                units: controller.propertyUnits[property.id] ?? const [],
                onTap: () => Navigator.push(
                  context,
                  FadePageRoute(
                    page: ManagedPropertyDetailScreen(
                      property: property,
                      units: controller.propertyUnits[property.id] ?? const [],
                      onAddUnits: () => _showAddUnitModal(property),
                    ),
                  ),
                ),
                onAddUnits: () => _showAddUnitModal(property),
              ),
            ),
          ),
      ],
    );
  }
}
