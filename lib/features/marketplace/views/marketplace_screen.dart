import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_network_image.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/utils/nearby_search.dart';
import '../../../core/widgets/custom_bottom_navbar.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_near_me.dart';
import '../../../core/widgets/landa_search_field.dart';
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
import '../../../core/utils/fade_page_route.dart';
import '../../../core/utils/landa_prefetch.dart';
import '../../../core/widgets/landa_busy.dart';

/// Tenant-facing marketplace: browse properties with available units and
/// apply in one tap.
///
/// The Discover tab, and a tab root rather than a pushed route: finding a
/// home is the reason a tenant installs this, and it spent a release as a
/// compass in the app bar competing with the notification bell for a 26px tap
/// target.
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with NearbySearchMixin, AutoRefreshMixin<MarketplaceScreen> {
  /// The first fetch is driven by [initState], because it has to finish
  /// before the location prompt decides whether to offer nearby sorting.
  @override
  bool get refreshOnMount => false;

  @override
  Future<void> onAutoRefresh() =>
      context.read<MarketplaceController>().loadMarketplace();

  /// Whether Discover has already offered to use location this app session.
  ///
  /// Static, because the bottom bar builds this tab from scratch every time
  /// the tenant switches back to it. As instance state it would re-prompt on
  /// every visit, and would quietly switch distance ordering back on for
  /// someone who had just tapped "See all" to turn it off.
  static bool _hasOfferedLocation = false;

  /// Owned here rather than by the search field, so the empty state's "Clear
  /// search" can empty the box as well as the query behind it.
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    // Seeded from the controller: it survives leaving and re-entering this
    // screen, so the box should not come back blank over filtered results.
    _searchController = TextEditingController(
      text: context.read<MarketplaceController>().searchQuery,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await refreshNow();
      if (mounted) await _requestLocationOnce();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Drops the search box, the filter sheet, and the text on screen together.
  Future<void> _clearSearchAndFilters() async {
    _searchController.clear();
    await context.read<MarketplaceController>().clearSearchAndFilters();
  }

  /// Back to everywhere, keeping the filters. What the Near me toggle undoes
  /// itself with: a tenant turning distance off is not asking to have their
  /// rent range widened at the same time.
  Future<void> _clearLocationSearch() async {
    _searchController.clear();
    await context.read<MarketplaceController>().clearLocationSearch();
  }

  /// Offers distance ordering the first time the tenant opens Discover.
  ///
  /// Silent on refusal: see [NearbySearchMixin.useNearby]. Skipped entirely
  /// when something is already narrowing the list: the controller outlives
  /// this screen, so returning to the tab can find a search already running,
  /// and replacing it would throw away a choice the tenant made.
  Future<void> _requestLocationOnce() async {
    if (_hasOfferedLocation) return;
    _hasOfferedLocation = true;
    if (context.read<MarketplaceController>().isNarrowed) return;
    await _useNearby(explain: false);
  }

  Future<void> _useNearby({bool explain = true}) => useNearby(
    explain: explain,
    onLocated: (latitude, longitude) async {
      // Coordinates replace the typed query rather than combining with it, so
      // the box empties to match what is actually being searched.
      _searchController.clear();
      if (!mounted) return;
      await context.read<MarketplaceController>().searchNearby(
        latitude: latitude,
        longitude: longitude,
      );
    },
  );

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
      // Carried so the provisional row reads properly on My applications in
      // the seconds before the real record lands.
      unitNumber: unit.unitNumber,
      rentAmount: unit.rentAmount,
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
      // A tab root now, so no back arrow: there is nothing behind it.
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
                    Text(
                      'Find your next home',
                      style: AppTheme.screenTitle(
                        context,
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
                    LandaSearchField(
                      controller: _searchController,
                      hintText: 'Search by area, city or address',
                      onChanged: controller.search,
                      trailing: NearMeButton(
                        isActive: controller.isSearchingNearby,
                        isLoading: isLocating,
                        onPressed: controller.isSearchingNearby
                            ? _clearLocationSearch
                            : _useNearby,
                        activeHint: 'Show homes everywhere',
                      ),
                    ),
                    if (controller.isSearchingNearby) ...[
                      const SizedBox(height: 10),
                      NearbyNotice(
                        message: 'Showing homes near you, closest first.',
                        onClear: _clearLocationSearch,
                      ),
                    ],
                    const SizedBox(height: 12),
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
                              FadePageRoute(page: const MyApplicationsScreen()),
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
            // Clears the floating bottom bar, which overlays this screen
            // rather than insetting it.
            const SliverToBoxAdapter(
              child: SizedBox(height: CustomBottomNavbar.reservedHeight + 16),
            ),
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
      // A search and a filter narrow the list the same way, so they get the
      // same empty state, and the one button clears both, because clearing
      // only half of what is hiding the listings leaves the tenant staring at
      // the same empty screen.
      final narrowed = controller.isNarrowed;
      return [
        SliverToBoxAdapter(
          child: LandaEmptyState(
            icon: narrowed
                ? Icons.search_off_rounded
                : Icons.home_work_outlined,
            title: narrowed
                ? 'Nothing matches that search'
                : 'No listings available yet',
            message: narrowed
                ? 'Try a different area, or widen your search to see more '
                      'homes.'
                : 'Available units will appear here as landlords list them.',
            actionLabel: narrowed ? 'Clear search' : 'Refresh listings',
            actionIcon: narrowed
                ? Icons.filter_alt_off_rounded
                : Icons.refresh_rounded,
            onAction: narrowed
                ? _clearSearchAndFilters
                : controller.loadMarketplace,
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
                onOpen: () {
                  LandaPrefetch.images(context, [
                    listing.property.displayImageUrl,
                    ...listing.property.photoUrls,
                  ]);
                  Navigator.push(
                    context,
                    FadePageRoute(
                      page: MarketplacePropertyScreen(listing: listing),
                    ),
                  );
                },
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
                      //
                      // A grid of these used to pop in one by one as each
                      // decoded. They now fade onto a block of the right
                      // shape, so a scroll settles instead of flickering.
                      child: LandaNetworkImage(
                        url: property.displayImageUrl,
                        placeholderIcon: Icons.home_work_outlined,
                        heroTag: landaMediaHeroTag('property', property.id),
                      ),
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
                        style: AppTheme.sectionTitle(
                          context,
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
                          // Only ever present on a nearby search, so it never
                          // has to explain what it is measured from.
                          if (listing.distanceLabel != null) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.near_me_rounded,
                              size: 12,
                              color: AppTheme.actionColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              listing.distanceLabel!,
                              style: AppTheme.labelText(
                                context,
                                color: AppTheme.actionColor,
                              ),
                            ),
                          ],
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
                color: AppTheme.successSurface(context),
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
                  ? const LandaBusyDots(color: Colors.white)
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
