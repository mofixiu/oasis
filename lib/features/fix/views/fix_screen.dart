import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_entrance.dart';
import '../../../core/widgets/landa_pressable.dart';
import '../../../core/widgets/landa_search_field.dart';
import '../../../core/widgets/landa_shimmer.dart';
import '../../../core/widgets/landa_state_views.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../agreements/controllers/agreement_controller.dart';
import '../../properties/controllers/landlord_controller.dart';
import '../controllers/fix_controller.dart';
import '../models/fix_models.dart';
import 'widgets/artisan_card.dart';

/// One of the tenant's units, as the unit picker sees it.
class _UnitOption {
  final String id;
  final String label;

  const _UnitOption({required this.id, required this.label});
}

/// Find a verified artisan and ring them.
///
/// This screen used to be a marketplace with two halves: browse an artisan,
/// and then track the job you asked them for, from request through accept,
/// quote, pay into escrow, confirm and release. API guide 18 removed every endpoint behind
/// the second half (§7B), and Landa no longer brokers repairs or handles
/// artisan money at all.
///
/// So the screen is now what the first half always was: a directory. The
/// change that makes it work is that the phone number is no longer withheld.
/// It used to be released only once an artisan accepted a job, which is
/// most of why that workflow existed, and it is now on every card. A tenant
/// picks a trade, sees who their landlord vouches for at the top, and calls
/// them.
///
/// The unit picker survives for one reason: recommendations are per unit, so
/// which artisan is highlighted depends on which home the tenant means.
class FixScreen extends StatefulWidget {
  /// Which unit the work is for, when the caller already knows. The picker
  /// still appears if the tenant holds more than one.
  final String? initialUnitId;

  const FixScreen({super.key, this.initialUnitId});

  @override
  State<FixScreen> createState() => _FixScreenState();
}

class _FixScreenState extends State<FixScreen>
    with AutoRefreshMixin<FixScreen> {
  /// The first load is ordered (categories, then artisans keyed on one) so
  /// it is driven by [initState] rather than fired blind by the mixin.
  @override
  bool get refreshOnMount => false;

  @override
  Future<void> onAutoRefresh() => _reload();

  /// Which unit the work is for. Null only while the tenant holds none.
  String? _unitId;

  /// Owned here rather than by the search field, so the empty state's "Clear
  /// search" can empty the box as well as the query behind it.
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: context.read<FixController>().artisanSearch,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstLoad());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Every unit this tenant holds, from their agreements, with the
  /// assigned-unit endpoint as the fallback for a tenant who has been given a
  /// unit before any agreement exists.
  List<_UnitOption> get _units {
    final options = <_UnitOption>[];
    final seen = <String>{};

    for (final tenancy in context.read<AgreementController>().tenancies) {
      final id = tenancy.latest.unit.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      final property = tenancy.latest.property?.name.trim() ?? '';
      options.add(
        _UnitOption(
          id: id,
          label: property.isEmpty
              ? tenancy.label
              : '$property · ${tenancy.label}',
        ),
      );
    }

    final assigned = context.read<LandlordController>().tenantAssignedUnit;
    if (assigned != null && assigned.id.isNotEmpty && seen.add(assigned.id)) {
      final property = assigned.property?.name.trim() ?? '';
      final unit = 'Unit ${assigned.unitNumber}';
      options.add(
        _UnitOption(
          id: assigned.id,
          label: property.isEmpty ? unit : '$property · $unit',
        ),
      );
    }

    return options;
  }

  Future<void> _firstLoad() async {
    _unitId = widget.initialUnitId;

    // Usually the dashboard has already loaded these and handed us a unit. It
    // has not when Fix is opened cold, and without a unit the list loses the
    // landlord's recommendation, which is the most useful thing on it.
    if (_unitId == null && _units.isEmpty) {
      await Future.wait([
        context.read<AgreementController>().loadAgreements(),
        context.read<LandlordController>().loadTenantAssignedUnit(),
      ]);
      if (!mounted) return;
    }

    final units = _units;
    _unitId ??= units.isEmpty ? null : units.first.id;

    final controller = context.read<FixController>();
    // Categories first: the artisan list is keyed on one, so fetching them in
    // parallel would fire the artisan call with nothing selected.
    await controller.loadCategories();
    if (!mounted) return;
    await _reload();
  }

  Future<void> _reload() =>
      context.read<FixController>().loadArtisans(unitId: _unitId);

  Future<void> _selectCategory(String category) =>
      context.read<FixController>().selectCategory(category, unitId: _unitId);

  Future<void> _searchArtisans(String query) =>
      context.read<FixController>().searchArtisans(query, unitId: _unitId);

  Future<void> _clearArtisanSearch() async {
    _searchController.clear();
    await context.read<FixController>().clearArtisanSearch(unitId: _unitId);
  }

  void _selectUnit(String unitId) {
    if (_unitId == unitId) return;
    setState(() => _unitId = unitId);
    // Recommendations are per unit, so the list has to be refetched rather
    // than re-sorted: which artisan is highlighted changes with the unit.
    context.read<FixController>().loadArtisans(unitId: unitId);
  }

  /// Opens the dialler with the artisan's number in it.
  ///
  /// Falls back to copying rather than failing: a device with no dialler. A
  /// tablet, an emulator: still leaves the tenant holding the number, which
  /// is the only thing they actually needed from this screen.
  Future<void> _call(ArtisanProfile artisan) async {
    final phone = artisan.phone;
    if (phone == null || phone.isEmpty) {
      LandaToast.error(
        context,
        '${artisan.displayName} has no phone number on their profile yet.',
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!mounted) return;
    await _copyPhone(phone);
  }

  Future<void> _copyPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (mounted) LandaToast.success(context, 'Phone number copied');
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FixController>();

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: const LandaAppBar(showBackButton: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fix',
                  style: AppTheme.screenTitle(
                    context,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                // Says plainly that the arrangement happens off Landa. The
                // screen used to promise escrow and a quote first, and a
                // tenant who remembers that needs to be told it changed
                // rather than left to discover it on a phone call.
                Text(
                  'Verified artisans near you. Call whoever you want directly. '
                  'You agree the work and the price with them.',
                  style: AppTheme.bodyText(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _directory(context, controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _directory(BuildContext context, FixController controller) {
    final units = _units;
    final artisans = controller.artisans;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        // Only worth showing to a tenant with more than one home, for
        // everyone else it is a control with one option.
        if (units.length > 1) ...[
          Text('RECOMMENDATIONS FOR', style: AppTheme.labelText(context)),
          const SizedBox(height: 8),
          _UnitPicker(units: units, selected: _unitId, onSelected: _selectUnit),
          const SizedBox(height: 20),
        ],

        Text('TRADE', style: AppTheme.labelText(context)),
        const SizedBox(height: 8),
        _CategoryChips(
          categories: controller.categories,
          selected: controller.selectedCategory,
          onSelected: _selectCategory,
        ),
        const SizedBox(height: 16),

        // Below the trade rather than above it: the trade is the required
        // choice, there is no artisan list without one, and area is the
        // optional narrowing on top of it.
        LandaSearchField(
          controller: _searchController,
          hintText: 'Search by area or name',
          onChanged: _searchArtisans,
        ),
        const SizedBox(height: 20),

        if (!controller.hasLoaded(FixController.kArtisansKey) ||
            (controller.isLoading && artisans.isEmpty))
          const LandaSkeletonList(count: 3, padding: EdgeInsets.zero)
        else if (controller.hasError && artisans.isEmpty)
          LandaErrorState(
            message: controller.errorMessage,
            isConnectionError: controller.errorIsConnection,
            onRetry: _reload,
            scrollable: false,
            padding: const EdgeInsets.fromLTRB(8, 24, 8, 24),
          )
        else if (artisans.isEmpty)
          LandaEmptyState(
            icon: controller.hasArtisanSearch
                ? Icons.search_off_rounded
                : Icons.handyman_outlined,
            title: controller.hasArtisanSearch
                ? 'Nobody matches that search'
                : 'No artisans here yet',
            message: controller.hasArtisanSearch
                ? 'No one under this trade matches that area. Clear the '
                      'search to see everyone, or try another trade.'
                : 'Nobody is listed under this trade in your area right now. '
                      'Try another trade, or check back later.',
            actionLabel: controller.hasArtisanSearch ? 'Clear search' : null,
            actionIcon: controller.hasArtisanSearch
                ? Icons.filter_alt_off_rounded
                : null,
            onAction: controller.hasArtisanSearch ? _clearArtisanSearch : null,
            scrollable: false,
            padding: const EdgeInsets.fromLTRB(8, 24, 8, 24),
          )
        else
          for (var index = 0; index < artisans.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LandaEntrance(
                index: index,
                child: ArtisanCard(
                  artisan: artisans[index],
                  // The whole card calls. There is exactly one thing to do
                  // with an artisan now, and making the tenant find a small
                  // button for it would be pretending otherwise.
                  onTap: () => _call(artisans[index]),
                  action: _CallButton(
                    artisan: artisans[index],
                    onCall: () => _call(artisans[index]),
                    onCopy: () => _copyPhone(artisans[index].phone ?? ''),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Call, with copy as the quieter second option.
///
/// Copy earns its place: half of Nigerian repair arranging happens on
/// WhatsApp, and a number the tenant can paste there is worth as much as one
/// the dialler opens.
class _CallButton extends StatelessWidget {
  final ArtisanProfile artisan;
  final VoidCallback onCall;
  final VoidCallback onCopy;

  const _CallButton({
    required this.artisan,
    required this.onCall,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final phone = artisan.phone;
    if (phone == null || phone.isEmpty) {
      // Should not happen now the backend always serves it, but a card whose
      // only action is "call" has to say something when it cannot.
      return Text(
        'No number listed',
        style: AppTheme.labelText(
          context,
          color: AppTheme.mutedTextColor(context),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LandaButton(
          label: 'Call',
          icon: Icons.call_rounded,
          expand: false,
          onPressed: onCall,
        ),
        IconButton(
          onPressed: onCopy,
          tooltip: 'Copy $phone',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.copy_rounded,
            size: 18,
            color: AppTheme.mutedTextColor(context),
          ),
        ),
      ],
    );
  }
}

/// Which of the tenant's homes the recommendations are for.
class _UnitPicker extends StatelessWidget {
  final List<_UnitOption> units;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _UnitPicker({
    required this.units,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final unit in units)
        _Chip(
          label: unit.label,
          isSelected: unit.id == selected,
          onTap: () => onSelected(unit.id),
        ),
    ],
  );
}

/// The trades, as chips.
class _CategoryChips extends StatelessWidget {
  final List<ArtisanCategory> categories;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final category in categories)
        _Chip(
          label: category.label,
          isSelected: category.value == selected,
          onTap: () => onSelected(category.value),
        ),
    ],
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => LandaPressable(
    onTap: onTap,
    pressedScale: 0.96,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
