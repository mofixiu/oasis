import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/oasis_haptics.dart';
import '../../../core/widgets/oasis_network_image.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/utils/oasis_refresh.dart';
import '../../../core/utils/nearby_search.dart';
import '../../../core/widgets/custom_bottom_navbar.dart';
import '../../../core/widgets/oasis_app_bar.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_near_me.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_search_field.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../../../core/widgets/v2_ui.dart';
import '../../reviews/views/widgets/rating_stars.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_models.dart';
import 'my_shortlet_bookings_screen.dart';
import 'shortlet_listing_screen.dart';
import 'v2/v2_empty_state.dart';
import 'v2/v2_stay_widgets.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/utils/oasis_prefetch.dart';
import '../../../core/utils/oasis_input_formatters.dart';

/// The Stays tab: where a tenant browses places by the night.
///
/// A tab of its own rather than a filter on Discover. Someone looking for a
/// home and someone looking for a weekend are on different errands, and a
/// booking has its own money and its own deadlines to come back to, which is
/// what earns it a permanent place in the bar.
class ShortLetBrowseScreen extends StatefulWidget {
  final bool isV2;

  /// V2 only: the pushed Search screen (field and results) rather than the
  /// Discover tab (photo grid).
  final bool isSearch;

  const ShortLetBrowseScreen({
    super.key,
    this.isV2 = false,
    this.isSearch = false,
  });

  @override
  State<ShortLetBrowseScreen> createState() => _ShortLetBrowseScreenState();
}

class _ShortLetBrowseScreenState extends State<ShortLetBrowseScreen>
    with NearbySearchMixin, AutoRefreshMixin<ShortLetBrowseScreen> {
  /// Whether Stays has already offered to use location this app session.
  ///
  /// Static, because the bottom bar builds this tab from scratch every time
  /// the tenant switches back to it. As instance state it would re-prompt on
  /// every visit, and would quietly switch distance sorting back on for
  /// someone who had just tapped "See all" to turn it off.
  static bool _hasOfferedLocation = false;

  /// Owned here rather than by the search field: switching to a nearby search
  /// clears the typed query, and the box has to empty with it or it would
  /// still show a place name that is no longer filtering anything.
  late final TextEditingController _searchController;

  /// The first fetch is driven by [initState] rather than the mixin, because
  /// it has to finish before the location prompt runs: the prompt decides
  /// whether to offer nearby sorting based on whether a search is already in
  /// effect, and asking that question mid-fetch gets the wrong answer.
  @override
  bool get refreshOnMount => false;

  @override
  Future<void> onAutoRefresh() => _reload();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: context.read<ShortLetController>().searchQuery,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await refreshNow();
      // The v2 Discover grid is for browsing; nearby sorting belongs to
      // Search, where the Near me control is.
      if (mounted && (!widget.isV2 || widget.isSearch)) {
        await _requestLocationOnce();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Back to every listing, in the controller and in the box.
  ///
  /// Deliberately leaves the dates: they never hid anything, so dropping them
  /// would throw away a choice the tenant did not ask to undo.
  Future<void> _clearSearch() async {
    _searchController.clear();
    await context.read<ShortLetController>().clearBrowseSearch();
  }

  /// Picks the stay the list should be checked against.
  ///
  /// Bounded to the next year rather than a host's own window, because this
  /// asks about every listing at once and no single host's calendar governs
  /// it. Each stay's own window still decides the answer, which is why the
  /// backend does the checking.
  Future<void> _pickDates() async {
    final controller = context.read<ShortLetController>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      currentDate: today,
      initialDateRange: controller.searchDates,
      helpText: 'Check availability for',
      saveText: 'Done',
    );
    if (picked == null || !mounted) return;
    await controller.setSearchDates(picked);
  }

  Future<void> _clearDates() =>
      context.read<ShortLetController>().setSearchDates(null);

  /// Opens the price-range sheet and applies whatever the tenant sets.
  ///
  /// Labelled by [ShortLetController.hasSearchDates] rather than a fixed
  /// string: the backend filters by nightly price with no dates and by total
  /// stay price once they are set, and the field has to say which one it is
  /// asking for.
  Future<void> _pickPriceRange() async {
    final controller = context.read<ShortLetController>();
    final result = await showModalBottomSheet<_PriceRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PriceRangeSheet(
        minPrice: controller.minPrice,
        maxPrice: controller.maxPrice,
        byTotalStay: controller.hasSearchDates,
      ),
    );
    if (result == null || !mounted) return;
    await controller.setPriceFilter(minPrice: result.min, maxPrice: result.max);
  }

  Future<void> _clearPriceRange() =>
      context.read<ShortLetController>().setPriceFilter();

  /// Applies the bedroom floor, or clears it when the tenant taps the chip
  /// that is already on.
  Future<void> _setBedrooms(int? minimum) {
    final controller = context.read<ShortLetController>();
    OasisHaptics.select();
    return controller.setBedroomsFilter(
      controller.minBedrooms == minimum ? null : minimum,
    );
  }

  /// Listings and the tenant's own bookings together: the header counts
  /// bookings that need paying, so it would be wrong on first paint without
  /// them.
  Future<void> _reload() {
    final controller = context.read<ShortLetController>();
    return Future.wait([
      controller.loadBrowseListings(),
      controller.loadMyBookings(),
    ]);
  }

  /// Asks for location the first time the tenant opens Stays, and sorts by
  /// distance if they allow it.
  ///
  /// Quiet on every failure. Nearby is a convenience on this screen, not the
  /// way it works, typing an area name finds the same listings, so a
  /// refusal leaves the full list on screen with nothing to dismiss. Only an
  /// explicit tap on Near me gets an explanation back.
  Future<void> _requestLocationOnce() async {
    if (_hasOfferedLocation) return;
    _hasOfferedLocation = true;
    // Never over the top of a search the tenant already has running: the
    // controller outlives this screen, so returning to the tab can find one
    // already in place.
    if (context.read<ShortLetController>().isBrowseNarrowed) return;
    await _useNearby(explain: false);
  }

  Future<void> _useNearby({bool explain = true}) => useNearby(
    explain: explain,
    onLocated: (latitude, longitude) async {
      // Coordinates replace the typed query rather than combining with it,
      // so the box empties to match what is actually being searched.
      _searchController.clear();
      if (!mounted) return;
      await context.read<ShortLetController>().searchNearby(
        latitude: latitude,
        longitude: longitude,
      );
    },
  );

  void _openBookings() => Navigator.push(
    context,
    FadePageRoute(page: MyShortLetBookingsScreen(isV2: widget.isV2)),
  );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();
    if (widget.isV2) return _buildV2(context, controller);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: OasisAppBar(shortLetOnlyProfile: widget.isV2),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _buildBody(context, controller),
      ),
    );
  }

  void _openListing(ShortLetController controller, ShortLetListing listing) {
    OasisPrefetch.images(context, listing.photoUrls);
    Navigator.push(
      context,
      FadePageRoute(
        page: ShortLetListingScreen(
          listing: listing,
          isV2: widget.isV2,
          requestedDates: controller.searchDates,
        ),
      ),
    );
  }

  /// How many of dates, price and bedrooms are narrowing the list.
  static int _activeFilterCount(ShortLetController controller) => [
    controller.hasSearchDates,
    controller.minPrice != null || controller.maxPrice != null,
    controller.minBedrooms != null,
  ].where((on) => on).length;

  Future<void> _clearFilters() async {
    final controller = context.read<ShortLetController>();
    if (controller.hasSearchDates) await controller.setSearchDates(null);
    if (controller.minPrice != null || controller.maxPrice != null) {
      await controller.setPriceFilter();
    }
    if (controller.minBedrooms != null) {
      await controller.setBedroomsFilter(null);
    }
  }

  /// Dates, price and bedrooms live in one sheet behind the Filters button,
  /// so browsing is not led by a row of controls.
  void _openFilters() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _V2FilterSheet(
      onPickDates: _pickDates,
      onClearDates: _clearDates,
      onPickPrice: _pickPriceRange,
      onClearPrice: _clearPriceRange,
      onSetBedrooms: _setBedrooms,
      onClearAll: _clearFilters,
    ),
  );

  void _openSearch() => Navigator.push(
    context,
    FadePageRoute(page: const ShortLetBrowseScreen(isV2: true, isSearch: true)),
  );

  Widget _buildV2(BuildContext context, ShortLetController controller) {
    final filterCount = _activeFilterCount(controller);
    final isTab = !widget.isSearch;
    // Above the floating tab bar on the tab, above the home indicator when
    // pushed.
    final fabBottom = isTab
        ? CustomBottomNavbar.reservedHeight + 4
        : MediaQuery.paddingOf(context).bottom + 20;

    return V2StatusBar(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _reload,
                child: widget.isSearch
                    ? _buildV2Search(context, controller, filterCount)
                    : _buildV2Discover(context, controller),
              ),
            ),
            Positioned(
              right: 20,
              bottom: fabBottom,
              child: _V2FilterButton(count: filterCount, onTap: _openFilters),
            ),
          ],
        ),
      ),
    );
  }

  /// Loading, error and empty states shared by Discover and Search, or null
  /// when there are results to show.
  List<Widget>? _v2StateFor(
    ShortLetController controller,
    List<ShortLetListing> listings,
  ) {
    if (!controller.hasLoaded(ShortLetController.kBrowseKey) ||
        (controller.isLoading && listings.isEmpty)) {
      return const [
        SizedBox(
          height: 420,
          child: OasisSkeletonList(
            count: 3,
            hasThumbnail: true,
            padding: EdgeInsets.zero,
          ),
        ),
      ];
    }
    if (controller.hasError && listings.isEmpty) {
      return [
        SizedBox(
          height: 360,
          child: OasisErrorState(
            message: controller.errorMessage,
            isConnectionError: controller.errorIsConnection,
            onRetry: _reload,
          ),
        ),
      ];
    }
    if (listings.isEmpty) {
      final narrowed = controller.isBrowseNarrowed;
      return [
        V2IllustratedEmptyState(
          artwork: V2EmptyArtwork.home,
          title: narrowed
              ? 'A little more room to explore.'
              : 'New shortlets are on their way.',
          message: narrowed
              ? 'Nothing matches that search and those filters. Clear them '
                    'to see every shortlet.'
              : 'There are no shortlets to show just now. Check again soon.',
          actionLabel: narrowed ? 'Clear search and filters' : null,
          onAction: narrowed
              ? () async {
                  await _clearFilters();
                  await _clearSearch();
                }
              : null,
          scrollable: false,
        ),
      ];
    }
    return null;
  }

  /// The Discover tab: a photo grid, and what is trending.
  Widget _buildV2Discover(BuildContext context, ShortLetController controller) {
    final shown = controller.browseListings;
    final trending = [...shown.where((listing) => listing.hasRating)]
      ..sort((a, b) => b.averageRating!.compareTo(a.averageRating!));
    final gridFirst = shown.take(6).toList();
    final gridRest = shown.skip(6).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
      children: [
        V2PageHeader(
          title: 'Discover',
          padding: EdgeInsets.zero,
          trailing: V2CircleButton(
            icon: Icons.search_rounded,
            tooltip: 'Search shortlets',
            onTap: _openSearch,
          ),
        ),
        const SizedBox(height: 16),
        // An approved booking expires if it is not paid for in time, so the
        // reminder stays here while one is waiting.
        if (controller.bookingsAwaitingPayment.isNotEmpty) ...[
          _MyBookingsRow(
            bookingCount: controller.liveBookings.length,
            awaitingPayment: controller.bookingsAwaitingPayment.length,
            onTap: _openBookings,
          ),
          const SizedBox(height: 16),
        ],
        ...?_v2StateFor(controller, shown),
        if (shown.isNotEmpty) ...[
          _V2InspireGrid(
            listings: gridFirst,
            onOpen: (listing) => _openListing(controller, listing),
          ),
          if (trending.length > 1) ...[
            const SizedBox(height: 26),
            const V2SectionHeader(title: 'Trending now'),
            const SizedBox(height: 12),
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: trending.length.clamp(0, 6),
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _V2TrendingCard(
                  listing: trending[index],
                  onTap: () => _openListing(controller, trending[index]),
                ),
              ),
            ),
          ],
          if (gridRest.isNotEmpty) ...[
            const SizedBox(height: 26),
            const V2SectionHeader(title: 'More shortlets'),
            const SizedBox(height: 12),
            _V2InspireGrid(
              listings: gridRest,
              onOpen: (listing) => _openListing(controller, listing),
            ),
          ],
        ],
      ],
    );
  }

  /// The pushed Search screen: where to, then the results as rows.
  Widget _buildV2Search(
    BuildContext context,
    ShortLetController controller,
    int filterCount,
  ) {
    final listings = controller.browseListings;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Row(
          children: [
            V2CircleButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              size: 40,
              onTap: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Text(
                'Search',
                textAlign: TextAlign.center,
                style: AppTheme.sectionTitle(context),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 18),
        OasisSearchField(
          controller: _searchController,
          hintText: 'Where to? Area or city',
          onChanged: controller.searchBrowseListings,
          trailing: NearMeButton(
            isActive: controller.isSearchingNearby,
            isLoading: isLocating,
            onPressed: controller.isSearchingNearby ? _clearSearch : _useNearby,
            activeHint: 'Show every shortlet',
          ),
        ),
        if (controller.isSearchingNearby) ...[
          const SizedBox(height: 10),
          NearbyNotice(
            message: 'Showing shortlets near you, closest first.',
            onClear: _clearSearch,
          ),
        ],
        // The filters are tucked away, so say when they are narrowing
        // things: otherwise a short list looks like a short catalogue.
        if (filterCount > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 15,
                color: AppTheme.secondaryTextColor(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$filterCount ${filterCount == 1 ? 'filter' : 'filters'} on',
                  style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                ),
              ),
              TextButton(onPressed: _clearFilters, child: const Text('Clear')),
            ],
          ),
        ],
        const SizedBox(height: 16),
        ...?_v2StateFor(controller, listings),
        for (var index = 0; index < listings.length; index++)
          OasisEntrance(
            index: index,
            child: _V2ResultRow(
              listing: listings[index],
              onTap: () => _openListing(controller, listings[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ShortLetController controller) {
    final listings = controller.browseListings;

    // "Has this ever come back?", not "is it running now?". Before the first
    // fetch both were false and the list was empty, so the screen announced
    // "No short stays yet" and only then showed the stays, which is exactly
    // the flash of a wrong empty state this branch now prevents.
    if (!controller.hasLoaded(ShortLetController.kBrowseKey) ||
        (controller.isLoading && listings.isEmpty)) {
      return const OasisSkeletonList(count: 4);
    }

    if (controller.hasError && listings.isEmpty) {
      return OasisErrorState(
        message: controller.errorMessage,
        isConnectionError: controller.errorIsConnection,
        onRetry: _reload,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Clears the floating bottom bar, which overlays this screen rather
      // than insetting it.
      padding: const EdgeInsets.fromLTRB(
        20,
        4,
        20,
        CustomBottomNavbar.reservedHeight + 16,
      ),
      children: [
        Text(
          'Short stays',
          style: AppTheme.screenTitle(context, color: AppTheme.primaryColor),
        ),
        const SizedBox(height: 4),
        Text(
          'Verified places to stay by the night. Ask the host for your dates, '
          'then pay once they say yes.',
          style: AppTheme.bodyText(context),
        ),
        const SizedBox(height: 16),

        OasisSearchField(
          controller: _searchController,
          hintText: 'Search by area or city',
          onChanged: controller.searchBrowseListings,
          trailing: NearMeButton(
            isActive: controller.isSearchingNearby,
            isLoading: isLocating,
            onPressed: controller.isSearchingNearby ? _clearSearch : _useNearby,
            activeHint: 'Show every stay',
          ),
        ),
        if (controller.isSearchingNearby) ...[
          const SizedBox(height: 10),
          NearbyNotice(
            message: 'Showing stays near you, closest first.',
            onClear: _clearSearch,
          ),
        ],
        const SizedBox(height: 10),
        _DateFilterRow(
          dates: controller.searchDates,
          onPick: _pickDates,
          onClear: _clearDates,
        ),
        const SizedBox(height: 10),
        _PriceFilterRow(
          minPrice: controller.minPrice,
          maxPrice: controller.maxPrice,
          byTotalStay: controller.hasSearchDates,
          onPick: _pickPriceRange,
          onClear: _clearPriceRange,
        ),
        const SizedBox(height: 10),
        _BedroomsFilterRow(
          minBedrooms: controller.minBedrooms,
          onSelect: _setBedrooms,
        ),
        const SizedBox(height: 16),

        _MyBookingsRow(
          bookingCount: controller.liveBookings.length,
          awaitingPayment: controller.bookingsAwaitingPayment.length,
          onTap: _openBookings,
        ),
        const SizedBox(height: 20),

        if (listings.isEmpty)
          widget.isV2
              ? V2IllustratedEmptyState(
                  artwork: V2EmptyArtwork.home,
                  title: controller.isBrowseNarrowed
                      ? 'A little more room to explore.'
                      : 'New stays are on their way.',
                  message: controller.isBrowseNarrowed
                      ? 'We could not find a place for those filters. Clear '
                            'them and see every stay.'
                      : 'There are no short stays to show just now. Check '
                            'again soon or visit your trips.',
                  actionLabel: controller.isBrowseNarrowed
                      ? 'Clear filters'
                      : 'View your trips',
                  onAction: controller.isBrowseNarrowed
                      ? _clearSearch
                      : _openBookings,
                  scrollable: false,
                )
              : OasisEmptyState(
                  icon: controller.isBrowseNarrowed
                      ? Icons.search_off_rounded
                      : Icons.holiday_village_outlined,
                  // The narrowing is not always a place any more: a bedroom
                  // floor or a price range can empty the list on its own, so the
                  // copy stops blaming the area unless the area is what was set.
                  title: controller.isBrowseNarrowed
                      ? 'Nothing matches that'
                      : 'No short stays yet',
                  message: controller.isBrowseNarrowed
                      ? 'No place by the night fits what you have asked for right '
                            'now. Loosen one of the filters, or see every stay.'
                      : 'Nobody is offering a place by the night right now. Pull '
                            'down to check again.',
                  scrollable: false,
                  padding: const EdgeInsets.fromLTRB(8, 32, 8, 16),
                  actionLabel: controller.isBrowseNarrowed
                      ? 'See all stays'
                      : 'My bookings',
                  actionIcon: controller.isBrowseNarrowed
                      ? Icons.filter_alt_off_rounded
                      : Icons.luggage_outlined,
                  onAction: controller.isBrowseNarrowed
                      ? _clearSearch
                      : _openBookings,
                )
        else
          for (var index = 0; index < listings.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: OasisEntrance(
                index: index,
                child: _ListingCard(
                  listing: listings[index],
                  // An unavailable stay is still worth opening: the tenant
                  // may want other dates, or the host's other terms, so it
                  // stays tappable and is marked instead of disabled.
                  onTap: () {
                    // Warmed on the tap rather than when the header builds,
                    // so the push animation is spent downloading instead of
                    // waiting. The card's own photo is already cached; this
                    // is for the ones a swipe reveals next.
                    OasisPrefetch.images(context, listings[index].photoUrls);
                    Navigator.push(
                      context,
                      FadePageRoute(
                        page: ShortLetListingScreen(
                          listing: listings[index],
                          isV2: widget.isV2,
                          requestedDates: controller.searchDates,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
      ],
    );
  }
}

/// Picks the dates the list is checked against, and shows which they are.
///
/// Worded as a check rather than a filter, because that is what it does: no
/// stay disappears for being booked up, it comes back marked. Calling it a
/// filter would promise a shorter list than the tenant gets.
class _DateFilterRow extends StatelessWidget {
  final DateTimeRange? dates;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DateFilterRow({
    required this.dates,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final range = dates;
    final isSet = range != null;
    final format = DateFormat('d MMM');

    return OasisPressable(
      onTap: onPick,
      pressedScale: 0.99,
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 12, isSet ? 6 : 14, 12),
        decoration: BoxDecoration(
          color: isSet
              ? AppTheme.actionColor.withValues(alpha: 0.07)
              : AppTheme.inputFillColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(
            color: isSet
                ? AppTheme.actionColor.withValues(alpha: 0.4)
                : AppTheme.borderColor(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: isSet
                  ? AppTheme.actionColor
                  : AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isSet
                    ? '${format.format(range.start)} – '
                          '${format.format(range.end)}'
                    : 'Check dates',
                style: AppTheme.bodyText(
                  context,
                  color: isSet
                      ? AppTheme.primaryTextColor(context)
                      : AppTheme.mutedTextColor(context),
                ),
              ),
            ),
            if (isSet)
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.mutedTextColor(context),
                ),
                onPressed: onClear,
                tooltip: 'Clear dates',
              )
            else
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

/// How many bedrooms the stay needs to have, as a row of floors.
///
/// Chips rather than a sheet, unlike price and dates. There are only five
/// answers anybody gives and every one of them fits on the row, so making a
/// tenant open a sheet to say "two bedrooms" would cost two taps to express
/// something a single tap can.
///
/// Every chip is a *floor*: "2+" means two or more. Nobody with three
/// children rules out a four-bedroom flat, and an exact-match filter would
/// hide the places they would happily have taken.
class _BedroomsFilterRow extends StatelessWidget {
  final int? minBedrooms;
  final ValueChanged<int?> onSelect;

  const _BedroomsFilterRow({required this.minBedrooms, required this.onSelect});

  /// Stops at 4+. Nightly lets larger than that are rare enough in Lagos that
  /// a fifth chip would be dead space on every phone that ever renders it.
  static const List<int> _floors = [1, 2, 3, 4];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.king_bed_outlined,
        size: 18,
        color: minBedrooms == null
            ? AppTheme.mutedTextColor(context)
            : AppTheme.actionColor,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _BedroomChip(
                label: 'Any',
                isSelected: minBedrooms == null,
                onTap: () => onSelect(null),
              ),
              for (final floor in _floors) ...[
                const SizedBox(width: 8),
                _BedroomChip(
                  label: '$floor+',
                  isSelected: minBedrooms == floor,
                  onTap: () => onSelect(floor),
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

class _BedroomChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BedroomChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    pressedScale: 0.96,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.actionColor.withValues(alpha: 0.10)
            : AppTheme.inputFillColor(context),
        borderRadius: AppTheme.cornerSm,
        border: Border.all(
          color: isSelected
              ? AppTheme.actionColor.withValues(alpha: 0.4)
              : AppTheme.borderColor(context),
        ),
      ),
      child: Text(
        label,
        style: AppTheme.bodyText(
          context,
          color: isSelected
              ? AppTheme.actionColor
              : AppTheme.secondaryTextColor(context),
        ).copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500),
      ),
    ),
  );
}

/// The min/max the tenant chose, or null where they left a bound open.
///
/// A tiny value type rather than reusing [ShortLetController]'s own strings,
/// so the sheet can hand back "nothing changed" as a plain null and the
/// screen never confuses "the tenant cleared the range" with "the tenant
/// dismissed the sheet".
class _PriceRange {
  final String? min;
  final String? max;

  const _PriceRange({this.min, this.max});
}

/// Shows the active price range, and opens the sheet that sets it.
///
/// Same shape as [_DateFilterRow] deliberately: a tenant who has learned one
/// filter row should not have to learn a second layout for the other.
class _PriceFilterRow extends StatelessWidget {
  final String? minPrice;
  final String? maxPrice;
  final bool byTotalStay;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _PriceFilterRow({
    required this.minPrice,
    required this.maxPrice,
    required this.byTotalStay,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isSet = minPrice != null || maxPrice != null;

    return OasisPressable(
      onTap: onPick,
      pressedScale: 0.99,
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 12, isSet ? 6 : 14, 12),
        decoration: BoxDecoration(
          color: isSet
              ? AppTheme.actionColor.withValues(alpha: 0.07)
              : AppTheme.inputFillColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(
            color: isSet
                ? AppTheme.actionColor.withValues(alpha: 0.4)
                : AppTheme.borderColor(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.payments_outlined,
              size: 18,
              color: isSet
                  ? AppTheme.actionColor
                  : AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isSet
                    ? _label(minPrice, maxPrice)
                    : (byTotalStay ? 'Total stay price' : 'Nightly price'),
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyText(
                  context,
                  color: isSet
                      ? AppTheme.primaryTextColor(context)
                      : AppTheme.mutedTextColor(context),
                ),
              ),
            ),
            if (isSet)
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.mutedTextColor(context),
                ),
                onPressed: onClear,
                tooltip: 'Clear price range',
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.mutedTextColor(context),
              ),
          ],
        ),
      ),
    );
  }

  static String _label(String? min, String? max) {
    if (min != null && max != null) {
      return '${OasisCurrency.format(min)} – ${OasisCurrency.format(max)}';
    }
    if (min != null) return 'From ${OasisCurrency.format(min)}';
    return 'Up to ${OasisCurrency.format(max!)}';
  }
}

/// Collects a min/max price, digits only, with the one rule the backend
/// itself enforces made impossible to submit: a max below the min.
///
/// [byTotalStay] only changes the label, "nightly price" versus "total stay
/// price", because that is genuinely the only thing that changes. The
/// backend decides which one it is filtering by from whether dates are set,
/// not from anything this sheet sends.
class _PriceRangeSheet extends StatefulWidget {
  final String? minPrice;
  final String? maxPrice;
  final bool byTotalStay;

  const _PriceRangeSheet({
    required this.minPrice,
    required this.maxPrice,
    required this.byTotalStay,
  });

  @override
  State<_PriceRangeSheet> createState() => _PriceRangeSheetState();
}

class _PriceRangeSheetState extends State<_PriceRangeSheet> {
  // Seeded in the grouped shape the field types in, so reopening the sheet
  // shows the same "50,000" the tenant left in it rather than a bare 50000.
  late final _minController = TextEditingController(
    text: OasisThousandsFormatter.groupAmount(widget.minPrice),
  );
  late final _maxController = TextEditingController(
    text: OasisThousandsFormatter.groupAmount(widget.maxPrice),
  );

  @override
  void initState() {
    super.initState();
    _minController.addListener(() => setState(() {}));
    _maxController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  int? get _min =>
      int.tryParse(OasisThousandsFormatter.digitsOf(_minController.text));
  int? get _max =>
      int.tryParse(OasisThousandsFormatter.digitsOf(_maxController.text));

  /// The one thing this sheet will not let the tenant send: a range the
  /// backend can only reject. Digit-only formatters already rule out text
  /// and negative numbers, so this is the sole remaining check.
  bool get _isInvertedRange {
    final min = _min;
    final max = _max;
    return min != null && max != null && max < min;
  }

  void _apply() {
    if (_isInvertedRange) return;
    Navigator.pop(
      context,
      _PriceRange(
        min: _min == null ? null : '$_min.00',
        max: _max == null ? null : '$_max.00',
      ),
    );
  }

  void _clear() => Navigator.pop(context, const _PriceRange());

  @override
  Widget build(BuildContext context) {
    final unit = widget.byTotalStay ? 'the stay' : 'night';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusLg),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.mutedTextColor(
                    context,
                  ).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.byTotalStay ? 'Total stay price' : 'Nightly price',
              style: AppTheme.sectionTitle(context),
            ),
            const SizedBox(height: 4),
            Text(
              'What you would pay for $unit, in naira.',
              style: AppTheme.bodyText(context),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PriceField(controller: _minController, label: 'MIN'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PriceField(
                    controller: _maxController,
                    label: 'MAX',
                    hasError: _isInvertedRange,
                  ),
                ),
              ],
            ),
            if (_isInvertedRange) ...[
              const SizedBox(height: 8),
              Text(
                'Max price cannot be lower than min price.',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.disputeColor,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isInvertedRange ? null : _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.actionColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppTheme.cornerMd,
                  ),
                ),
                child: const Text(
                  'Apply',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (widget.minPrice != null || widget.maxPrice != null)
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _clear,
                  child: const Text('Clear price range'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool hasError;

  const _PriceField({
    required this.controller,
    required this.label,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
      ),
      const SizedBox(height: 6),
      // Digits only: a price field a tenant cannot type letters or a minus
      // sign into is a price field that cannot be sent invalid, rather than
      // one that reports it was invalid after the fact.
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: const [OasisThousandsFormatter()],
        style: AppTheme.cardTitle(context),
        decoration:
            oasisInputDecoration(
              context,
              hint: '0',
              prefixIcon: Icons.currency_exchange_outlined,
            ).copyWith(
              enabledBorder: hasError
                  ? OutlineInputBorder(
                      borderRadius: AppTheme.cornerMd,
                      borderSide: const BorderSide(
                        color: AppTheme.disputeColor,
                      ),
                    )
                  : null,
            ),
      ),
    ],
  );
}

/// Standing link to the tenant's own bookings, badged when one needs paying.
///
/// An approved booking expires 24 hours after approval, so "you owe money on
/// a stay" is the one thing on this screen that is time-limited: it gets a
/// permanent home rather than living only in a notification.
class _MyBookingsRow extends StatelessWidget {
  final int bookingCount;
  final int awaitingPayment;
  final VoidCallback onTap;

  const _MyBookingsRow({
    required this.bookingCount,
    required this.awaitingPayment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final urgent = awaitingPayment > 0;

    return OasisPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: urgent
              ? AppTheme.warningColor.withValues(alpha: 0.08)
              : AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(
            color: urgent
                ? AppTheme.warningColor.withValues(alpha: 0.35)
                : AppTheme.borderColor(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              urgent ? Icons.timer_outlined : Icons.luggage_outlined,
              size: 20,
              color: urgent
                  ? AppTheme.warningColor
                  : AppTheme.secondaryTextColor(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My bookings', style: AppTheme.cardTitle(context)),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(bookingCount, awaitingPayment),
                    style: AppTheme.labelText(
                      context,
                      color: urgent
                          ? AppTheme.warningColor
                          : AppTheme.secondaryTextColor(context),
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
      ),
    );
  }

  static String _subtitle(int total, int awaitingPayment) {
    if (awaitingPayment > 0) {
      return '$awaitingPayment ${awaitingPayment == 1 ? 'booking is' : 'bookings are'} '
          'approved and waiting to be paid';
    }
    if (total == 0) return 'Nothing booked yet';
    return '$total ${total == 1 ? 'booking' : 'bookings'} in progress';
  }
}

/// Floating "Filters" button, with the number of filters that are on.
class _V2FilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _V2FilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: count == 0 ? 'Filters' : 'Filters, $count on',
    excludeSemantics: true,
    child: OasisPressable(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppTheme.terracottaColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.terracottaColor.withValues(alpha: 0.35),
              blurRadius: 16,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            const Text(
              'Filters',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppTheme.textMd,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: AppTheme.terracottaColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Every filter in one place: dates, price and bedrooms. Each applies as it
/// is set, so the list behind the sheet is already up to date when it closes.
class _V2FilterSheet extends StatelessWidget {
  final Future<void> Function() onPickDates;
  final Future<void> Function() onClearDates;
  final Future<void> Function() onPickPrice;
  final Future<void> Function() onClearPrice;
  final Future<void> Function(int?) onSetBedrooms;
  final Future<void> Function() onClearAll;

  const _V2FilterSheet({
    required this.onPickDates,
    required this.onClearDates,
    required this.onPickPrice,
    required this.onClearPrice,
    required this.onSetBedrooms,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();
    final dates = controller.searchDates;
    final hasPrice = controller.minPrice != null || controller.maxPrice != null;
    final format = DateFormat('d MMM');
    final count = controller.browseListings.length;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.mutedTextColor(context).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Filters', style: AppTheme.sectionTitle(context)),
              ),
              TextButton(
                onPressed: _hasAny(controller) ? onClearAll : null,
                child: const Text('Clear all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _V2FilterRow(
            icon: Icons.calendar_today_outlined,
            title: 'Dates',
            value: dates == null
                ? 'Any dates'
                : '${format.format(dates.start)} – ${format.format(dates.end)}',
            isSet: dates != null,
            onTap: onPickDates,
            onClear: onClearDates,
          ),
          _V2FilterRow(
            icon: Icons.payments_outlined,
            title: controller.hasSearchDates
                ? 'Total price'
                : 'Price per night',
            value: hasPrice
                ? _PriceFilterRow._label(
                    controller.minPrice,
                    controller.maxPrice,
                  )
                : 'Any price',
            isSet: hasPrice,
            onTap: onPickPrice,
            onClear: onClearPrice,
          ),
          const SizedBox(height: 14),
          Text('Bedrooms', style: AppTheme.cardTitle(context)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final floor in const <int?>[null, 1, 2, 3, 4]) ...[
                if (floor != null) const SizedBox(width: 8),
                Expanded(
                  child: _V2AreaChip(
                    label: floor == null ? 'Any' : '$floor+',
                    isSelected: controller.minBedrooms == floor,
                    onTap: () => onSetBedrooms(floor),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          OasisButton(
            label: controller.isLoading
                ? 'Updating…'
                : 'Show $count ${count == 1 ? 'shortlet' : 'shortlets'}',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  static bool _hasAny(ShortLetController controller) =>
      controller.hasSearchDates ||
      controller.minPrice != null ||
      controller.maxPrice != null ||
      controller.minBedrooms != null;
}

class _V2FilterRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool isSet;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _V2FilterRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.isSet,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: AppTheme.cornerMd,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor(context)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryTextColor(context)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.cardTitle(context)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTheme.bodyText(
                    context,
                    color: isSet ? AppTheme.actionColor : null,
                  ).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          if (isSet)
            IconButton(
              tooltip: 'Clear $title',
              onPressed: onClear,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppTheme.secondaryTextColor(context),
              ),
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.mutedTextColor(context),
            ),
        ],
      ),
    ),
  );
}

/// A pill in a single-choice row: areas on Discover, bedrooms in filters.
class _V2AreaChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _V2AreaChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    child: OasisPressable(
      onTap: onTap,
      pressedScale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.terracottaColor
              : AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: isSelected
                ? AppTheme.terracottaColor
                : AppTheme.borderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : AppTheme.primaryTextColor(context),
          ),
        ),
      ),
    ),
  );
}

/// Two columns of tall photo cards, for browsing by eye.
class _V2InspireGrid extends StatelessWidget {
  final List<ShortLetListing> listings;
  final ValueChanged<ShortLetListing> onOpen;

  const _V2InspireGrid({required this.listings, required this.onOpen});

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    padding: EdgeInsets.zero,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.72,
    ),
    itemCount: listings.length,
    itemBuilder: (context, index) => _V2InspireCard(
      listing: listings[index],
      onTap: () => onOpen(listings[index]),
    ),
  );
}

class _V2InspireCard extends StatelessWidget {
  final ShortLetListing listing;
  final VoidCallback onTap;

  const _V2InspireCard({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${listing.title}, ${listing.location}',
    excludeSemantics: true,
    child: OasisPressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            V2StayPhoto(url: listing.coverPhotoUrl),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.72),
                  ],
                  stops: const [0.4, 1],
                ),
              ),
            ),
            if (listing.isUnavailableForPeriod)
              Positioned(
                top: 10,
                left: 10,
                child: V2StatusPill(
                  label: 'Not free then',
                  tone: V2Tone.neutral,
                ),
              ),
            Positioned(
              top: 10,
              right: 10,
              child: V2SaveButton(listing: listing, size: 32),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${OasisCurrency.format(listing.nightlyPrice)} / night',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: AppTheme.terracottaColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A wide photo card on the Trending row.
class _V2TrendingCard extends StatelessWidget {
  final ShortLetListing listing;
  final VoidCallback onTap;

  const _V2TrendingCard({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: listing.title,
    excludeSemantics: true,
    child: OasisPressable(
      onTap: onTap,
      pressedScale: 0.98,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 250,
          child: Stack(
            fit: StackFit.expand,
            children: [
              V2StayPhoto(url: listing.coverPhotoUrl),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    stops: const [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            '${listing.ratingLabel} · ${listing.location}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A search result: photo on the left, the facts beside it.
class _V2ResultRow extends StatelessWidget {
  final ShortLetListing listing;
  final VoidCallback onTap;

  const _V2ResultRow({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cover = listing.coverPhotoUrl;
    final isUnavailable = listing.isUnavailableForPeriod;
    final meta = AppTheme.bodyText(context).copyWith(fontSize: 12);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: OasisPressable(
        onTap: onTap,
        pressedScale: 0.99,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 124,
                height: 124,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: isUnavailable ? 0.55 : 1,
                      child: cover == null
                          ? const V2StayPhoto(url: null)
                          : OasisNetworkImage(
                              url: cover,
                              placeholderIcon: Icons.holiday_village_outlined,
                              heroTag: oasisMediaHeroTag(
                                'shortlet',
                                listing.id,
                              ),
                            ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: V2SaveButton(listing: listing, size: 30),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.cardTitle(
                      context,
                    ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (listing.location.isNotEmpty) listing.location,
                      if (listing.distanceLabel != null) listing.distanceLabel!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyText(context).copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  V2NightlyPrice(amount: listing.nightlyPrice, fontSize: 15),
                  const SizedBox(height: 4),
                  V2RatingLine(listing: listing, compact: true),
                  // The deposit is a cost the guest cannot opt out of, so it
                  // is on the row they compare on.
                  if (listing.hasCautionFee) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+ ${OasisCurrency.format(listing.cautionFee)} '
                      'refundable deposit',
                      style: meta,
                    ),
                  ],
                  // The backend's own sentence: it knows about bookings this
                  // app cannot see.
                  if (isUnavailable) ...[
                    const SizedBox(height: 6),
                    Text(
                      listing.unavailableLabel,
                      style: meta.copyWith(
                        color: AppTheme.isDarkMode(context)
                            ? const Color(0xFFE59A8F)
                            : AppTheme.brickRedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  final ShortLetListing listing;
  final VoidCallback onTap;

  const _ListingCard({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cover = listing.coverPhotoUrl;
    final isUnavailable = listing.isUnavailableForPeriod;

    return OasisPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: AppTheme.cornerLg,
          border: Border.all(color: AppTheme.borderColor(context)),
          boxShadow: AppTheme.cardShadow(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  // A listing whose photo will not load is still bookable,
                  // so a missing or failed image degrades to the same quiet
                  // block rather than a broken-image glyph, and the photo
                  // fades onto that block instead of snapping into place.
                  child: OasisNetworkImage(
                    url: cover,
                    placeholderIcon: Icons.holiday_village_outlined,
                    // Flies into the listing header, so tapping a card grows
                    // its photo rather than pushing a screen over it.
                    heroTag: oasisMediaHeroTag('shortlet', listing.id),
                  ),
                ),
                // Taken dates are said in words below as well; the wash is
                // only there to make the state readable while scrolling.
                if (isUnavailable)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: AppTheme.pageBackground(
                          context,
                        ).withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                if (isUnavailable)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.mutedTextColor(context),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_busy_outlined,
                            color: Colors.white,
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'NOT FREE THEN',
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
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    style: AppTheme.cardTitle(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (listing.location.isNotEmpty ||
                      listing.distanceLabel != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (listing.location.isNotEmpty)
                          Flexible(
                            child: Text(
                              listing.location,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.labelText(
                                context,
                                color: AppTheme.secondaryTextColor(context),
                              ),
                            ),
                          ),
                        // Only ever present on a location-aware search, so it
                        // never has to explain what it is measured from.
                        if (listing.distanceLabel != null) ...[
                          if (listing.location.isNotEmpty)
                            Text(
                              '  ·  ',
                              style: AppTheme.labelText(
                                context,
                                color: AppTheme.mutedTextColor(context),
                              ),
                            ),
                          Icon(
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
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${OasisCurrency.format(listing.nightlyPrice)} / night',
                          style: AppTheme.cardTitle(
                            context,
                            color: AppTheme.actionColor,
                          ),
                        ),
                      ),
                      // An unrated listing shows the minimum-nights line
                      // alone rather than "0 reviews": a new host has no
                      // rating, and a zero would read as a bad one.
                      if (listing.hasRating) ...[
                        RatingStars(rating: listing.averageRating!, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          '${listing.ratingLabel} (${listing.reviewCount})',
                          style: AppTheme.labelText(
                            context,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                      ] else
                        Text(
                          'Min ${listing.minimumNights} '
                          '${listing.minimumNights == 1 ? 'night' : 'nights'}',
                          style: AppTheme.labelText(
                            context,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                    ],
                  ),
                  // The deposit is a cost the guest cannot opt out of, so it
                  // belongs on the card they are comparing on rather than
                  // waiting to surprise them at checkout.
                  if (listing.hasCautionFee) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 13,
                          color: AppTheme.vacantColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '+ ${OasisCurrency.format(listing.cautionFee)} '
                          'refundable deposit',
                          style: AppTheme.labelText(
                            context,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // The backend's own sentence: it knows about blocked dates
                  // and rival bookings this app cannot see, so it is shown as
                  // written rather than reworded into a guess.
                  if (isUnavailable) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppTheme.secondaryTextColor(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            listing.unavailableLabel,
                            style: AppTheme.labelText(
                              context,
                              color: AppTheme.secondaryTextColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
