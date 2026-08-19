import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../properties/models/property_model.dart';
import '../controllers/marketplace_controller.dart';
import '../models/marketplace_models.dart';
import 'apply_for_unit_sheet.dart';
import 'marketplace_filter_sheet.dart';
import 'marketplace_property_screen.dart';
import 'my_applications_screen.dart';

/// Tenant-facing marketplace: browse properties with available units and
/// apply in one tap.
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<MarketplaceController>().loadMarketplace(),
    );
  }

  Future<void> _openFilters() async {
    final controller = context.read<MarketplaceController>();
    final updated = await showModalBottomSheet<MarketplaceFilters>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MarketplaceFilterSheet(initial: controller.filters),
    );
    if (updated != null) await controller.applyFilters(updated);
  }

  Future<void> _apply(UnitModel unit, MarketplaceProperty listing) async {
    final controller = context.read<MarketplaceController>();
    final result = await showModalBottomSheet<ApplyResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ApplyForUnitSheet(unit: unit, listing: listing),
    );

    if (result == null || !mounted) return;

    final application = await controller.applyForUnit(
      unit.id,
      message: result.message,
    );
    if (!mounted) return;

    if (application != null) {
      LandaToast.success(
        context,
        'Application sent for Unit ${unit.unitNumber}. You will be notified when the landlord responds.',
      );
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
        onRefresh: controller.loadMarketplace,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Find your next home',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Verified listings with units available right now.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.secondaryTextColor(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openFilters,
                            icon: const Icon(Icons.tune, size: 18),
                            label: Text(
                              controller.filters.isEmpty
                                  ? 'Filters'
                                  : 'Filters active',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: controller.filters.isEmpty
                                  ? AppTheme.secondaryTextColor(context)
                                  : AppTheme.actionColor,
                              side: BorderSide(
                                color: controller.filters.isEmpty
                                    ? AppTheme.borderColor(context)
                                    : AppTheme.actionColor,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyApplicationsScreen(),
                              ),
                            ),
                            icon: const Icon(
                              Icons.description_outlined,
                              size: 18,
                            ),
                            label: const Text('My applications'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.secondaryTextColor(
                                context,
                              ),
                              side: BorderSide(
                                color: AppTheme.borderColor(context),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!controller.filters.isEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: controller.clearFilters,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Clear filters',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.actionColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            ..._buildBody(context, controller),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    MarketplaceController controller,
  ) {
    if (!controller.hasLoadedMarketplace ||
        (controller.isLoading && controller.listings.isEmpty)) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.separated(
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (_, __) => const LandaListingSkeleton(),
          ),
        ),
      ];
    }

    if (controller.hasError && controller.listings.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: LandaErrorState(
            message: controller.errorMessage,
            isConnectionError: controller.errorIsConnection,
            onRetry: controller.loadMarketplace,
            scrollable: false,
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
          ),
        ),
      ];
    }

    if (controller.listings.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: LandaEmptyState(
            icon: controller.filters.isEmpty
                ? Icons.home_work_outlined
                : Icons.filter_alt_off_outlined,
            title: controller.filters.isEmpty
                ? 'No listings available yet'
                : 'Nothing matches those filters',
            message: controller.filters.isEmpty
                ? 'Available units will appear here as landlords list them.'
                : 'Try widening your search to see more homes.',
            actionLabel: controller.filters.isEmpty
                ? 'Refresh listings'
                : 'Clear filters',
            actionIcon: controller.filters.isEmpty
                ? Icons.refresh_rounded
                : Icons.filter_alt_off_rounded,
            onAction: controller.filters.isEmpty
                ? controller.loadMarketplace
                : controller.clearFilters,
            scrollable: false,
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
          ),
        ),
      ];
    }

    final appliedUnitIds = controller.appliedUnitIds;
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.separated(
          itemCount: controller.listings.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final listing = controller.listings[index];
            return LandaEntrance(
              index: index,
              child: _MarketplaceCard(
                listing: listing,
                appliedUnitIds: appliedUnitIds,
                applyingUnitId: controller.applyingUnitId,
                onApply: (unit) => _apply(unit, listing),
                onOpen: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MarketplacePropertyScreen(listing: listing),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }
}

class _MarketplaceCard extends StatelessWidget {
  final MarketplaceProperty listing;
  final Set<String> appliedUnitIds;
  final String? applyingUnitId;
  final void Function(UnitModel unit) onApply;
  final VoidCallback onOpen;

  const _MarketplaceCard({
    required this.listing,
    required this.appliedUnitIds,
    required this.applyingUnitId,
    required this.onApply,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final property = listing.property;
    final isVerified = property.verificationStatus.toUpperCase() == 'VERIFIED';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image + header open the full listing; the per-unit Apply buttons
          // below stay as their own tap targets.
          GestureDetector(
            onTap: onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 170,
                      width: double.infinity,
                      // Backend picks the cover (first uploaded photo); fall back to
                      // the first in the list for payloads without cover_photo_url.
                      child: property.displayImageUrl != null
                          ? Image.network(
                              property.displayImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _fallbackImage(),
                            )
                          : _fallbackImage(),
                    ),
                    if (property.hasVideo)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_circle_outline,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'TOUR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (isVerified)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified,
                                color: Colors.white,
                                size: 13,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'VERIFIED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [
                                property.address,
                                property.city,
                                property.state,
                              ].where((part) => part.isNotEmpty).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.secondaryTextColor(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            '${listing.availableUnits.length} '
                            '${listing.availableUnits.length == 1 ? 'UNIT' : 'UNITS'} AVAILABLE',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: Colors.grey,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'View listing',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.actionColor,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: AppTheme.actionColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...listing.availableUnits.map(
            (unit) => _UnitRow(
              unit: unit,
              hasApplied: appliedUnitIds.contains(unit.id),
              isApplying: applyingUnitId == unit.id,
              onApply: () => onApply(unit),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _fallbackImage() => Container(
    color: AppTheme.primaryColor.withValues(alpha: .08),
    child: const Center(
      child: Icon(
        Icons.home_work_outlined,
        size: 56,
        color: AppTheme.primaryColor,
      ),
    ),
  );
}

class _UnitRow extends StatelessWidget {
  final UnitModel unit;
  final bool hasApplied;
  final bool isApplying;
  final VoidCallback onApply;

  const _UnitRow({
    required this.unit,
    required this.hasApplied,
    required this.isApplying,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unit ${unit.unitNumber} · ${LandaCurrency.perYear(unit.rentAmount)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${unit.bedrooms} bed · ${unit.bathrooms} bath',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (hasApplied)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.successSurfaceColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 14, color: AppTheme.successColor),
                  SizedBox(width: 4),
                  Text(
                    'Applied',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.successColor,
                    ),
                  ),
                ],
              ),
            )
          else
            ElevatedButton(
              onPressed: isApplying ? null : onApply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.actionColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isApplying
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Apply',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
