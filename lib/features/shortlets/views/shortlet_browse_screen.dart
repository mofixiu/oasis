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
import '../../reviews/views/widgets/rating_stars.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_models.dart';
import 'my_shortlet_bookings_screen.dart';
import 'shortlet_listing_screen.dart';
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
  const ShortLetBrowseScreen({super.key});

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
      if (mounted) await _requestLocationOnce();
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
    FadePageRoute(page: const MyShortLetBookingsScreen()),
  );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const OasisAppBar(),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _buildBody(context, controller),
      ),
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
          OasisEmptyState(
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
      return '$awaitingPayment ${awaitingPayment == 1 ? 'stay is' : 'stays are'} '
          'approved and waiting to be paid';
    }
    if (total == 0) return 'Nothing booked yet';
    return '$total ${total == 1 ? 'stay' : 'stays'} in progress';
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
