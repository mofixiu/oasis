import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_shimmer.dart';
import '../../../core/widgets/oasis_state_views.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../controllers/fix_controller.dart';
import '../models/fix_models.dart';
import 'widgets/artisan_card.dart';

/// Lets a landlord name the artisan they trust on a unit, one per trade.
///
/// Optional, and it is worth saying why it exists: a tenant with a burst pipe
/// is going to call somebody. This is how a landlord gets a say in who that
/// is, without having to be reachable at the time.
///
/// Returns true when anything changed, so the caller can refresh.
Future<bool> openUnitRecommendationsSheet(
  BuildContext context, {
  required String unitId,
  required String unitLabel,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _UnitRecommendationsSheet(unitId: unitId, unitLabel: unitLabel),
  );
  return changed ?? false;
}

/// Shows the artisans working in [category] and returns the one chosen.
///
/// Public because two flows need it: managing a live unit's recommendations,
/// and choosing them up front while a landlord is still adding units.
Future<ArtisanProfile?> openArtisanPickerSheet(
  BuildContext context, {
  required ArtisanCategory category,
  String? current,

  /// The unit being recommended on, when there is one. Sent to the backend so
  /// the landlord's existing pick comes back marked.
  String? unitId,
}) => showModalBottomSheet<ArtisanProfile>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      _ArtisanPickerSheet(category: category, current: current, unitId: unitId),
);

/// Asks which trade, then who, for a landlord adding a recommendation from
/// scratch rather than filling a row that already names the trade.
///
/// [taken] hides trades already covered: a unit holds one recommendation per
/// category, so offering a second would silently replace the first.
Future<({ArtisanCategory category, ArtisanProfile artisan})?>
pickRecommendedArtisan(
  BuildContext context, {
  Set<String> taken = const {},
}) async {
  // Anchored to the navigator for the same reason [openAddPropertyFlow] is:
  // a fetch and two sheets are awaited in a row, and this runs *inside* the
  // add-property flow, so whatever swaps the shell out from under that flow
  // swaps it out from under this one too. Presenting a sheet from a context
  // whose element has left the tree dies in the framework's own ancestor
  // lookup, before any check here could run.
  final navigator = Navigator.of(context);
  final controller = context.read<FixController>();
  await controller.loadCategories();
  if (!navigator.mounted) return null;

  final available =
      (controller.categories.isEmpty
              ? ArtisanCategory.defaults
              : controller.categories)
          .where((category) => !taken.contains(category.value))
          .toList();
  if (available.isEmpty) return null;

  final category = await showModalBottomSheet<ArtisanCategory>(
    context: navigator.context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryChooserSheet(categories: available),
  );
  if (category == null || !navigator.mounted) return null;

  final artisan = await openArtisanPickerSheet(
    navigator.context,
    category: category,
  );
  if (artisan == null) return null;
  return (category: category, artisan: artisan);
}

class _UnitRecommendationsSheet extends StatefulWidget {
  final String unitId;
  final String unitLabel;

  const _UnitRecommendationsSheet({
    required this.unitId,
    required this.unitLabel,
  });

  @override
  State<_UnitRecommendationsSheet> createState() =>
      _UnitRecommendationsSheetState();
}

class _UnitRecommendationsSheetState extends State<_UnitRecommendationsSheet> {
  /// What is currently set on the unit, by category.
  Map<String, ArtisanRecommendation> _recommendations = {};

  bool _loading = true;
  String? _loadError;

  /// True once anything has been saved, so the caller knows to refresh even
  /// if the sheet is dismissed rather than closed by a button.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final controller = context.read<FixController>();
    // Categories seed the row list: a trade with no recommendation still
    // needs a row, otherwise there is nothing to tap to add one.
    await controller.loadCategories();
    final loaded = await controller.loadUnitRecommendations(widget.unitId);
    if (!mounted) return;

    setState(() {
      _loading = false;
      _loadError = loaded == null ? controller.errorMessage : null;
      _recommendations = {
        for (final recommendation in loaded ?? const <ArtisanRecommendation>[])
          recommendation.category: recommendation,
      };
    });
  }

  Future<void> _choose(ArtisanCategory category) async {
    final controller = context.read<FixController>();
    final chosen = await openArtisanPickerSheet(
      context,
      category: category,
      current: _recommendations[category.value]?.artisanId,
      unitId: widget.unitId,
    );
    if (chosen == null || !mounted) return;

    final saved = await controller.recommendArtisan(
      unitId: widget.unitId,
      category: category.value,
      artisanId: chosen.id,
    );
    if (!mounted) return;

    if (!saved) {
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not save that recommendation. Try again in a moment.',
      );
      return;
    }

    setState(() {
      _changed = true;
      _recommendations[category.value] = ArtisanRecommendation(
        category: category.value,
        categoryLabel: category.label,
        artisanId: chosen.id,
        artisan: chosen,
      );
    });
    OasisToast.success(
      context,
      '${chosen.displayName} is now your ${category.label.toLowerCase()} '
      'recommendation for ${widget.unitLabel}.',
    );
  }

  Future<void> _remove(ArtisanCategory category) async {
    final controller = context.read<FixController>();
    final removed = await controller.removeRecommendation(
      unitId: widget.unitId,
      category: category.value,
    );
    if (!mounted) return;

    if (!removed) {
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not remove that recommendation. Try again in a moment.',
      );
      return;
    }
    setState(() {
      _changed = true;
      _recommendations.remove(category.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FixController>();
    final categories = controller.categories.isEmpty
        ? ArtisanCategory.defaults
        : controller.categories;

    return PopScope(
      // The sheet has no save button, each row commits on its own, so the
      // "did anything change" answer travels out on the pop.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: OasisSheet(
        icon: Icons.handshake_outlined,
        title: 'Recommended artisans',
        subtitle: '${widget.unitLabel} · optional',
        children: [
          Text(
            'Your tenant sees these first when they book a repair, marked as '
            'recommended by you. They can still choose somebody else.',
            style: AppTheme.bodyText(context),
          ),
          const SizedBox(height: 20),

          if (_loading)
            const OasisSkeletonList(count: 3, padding: EdgeInsets.zero)
          else if (_loadError != null)
            OasisErrorBanner(message: _loadError!, onRetry: _load)
          else
            for (final category in categories) ...[
              _RecommendationRow(
                category: category,
                recommendation: _recommendations[category.value],
                busy: controller.isSubmitting,
                onChoose: () => _choose(category),
                onRemove: () => _remove(category),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

/// One trade, and who is named for it.
class _RecommendationRow extends StatelessWidget {
  final ArtisanCategory category;
  final ArtisanRecommendation? recommendation;
  final bool busy;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  const _RecommendationRow({
    required this.category,
    required this.recommendation,
    required this.busy,
    required this.onChoose,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final artisan = recommendation?.artisan;
    final set = recommendation != null;
    final accent = set
        ? AppTheme.successColor
        : AppTheme.mutedTextColor(context);

    return OasisPressable(
      onTap: busy ? null : onChoose,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: set
              ? AppTheme.successSurface(context)
              : AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(
            color: set
                ? AppTheme.successColor.withValues(alpha: 0.35)
                : AppTheme.borderColor(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              set ? Icons.check_circle_rounded : Icons.add_circle_outline,
              size: 20,
              color: accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: AppTheme.cardTitle(
                      context,
                      // The tinted surface is a fixed pale cream in light
                      // mode, so this needs the reading colour rather than
                      // the theme-aware primary.
                      color: set ? AppTheme.readingTextColor(context) : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artisan != null
                        ? '${artisan.displayName}'
                              '${artisan.location.isEmpty ? '' : ' · ${artisan.location}'}'
                        : set
                        ? 'Recommendation set'
                        : 'Nobody recommended yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyText(
                      context,
                      color: set ? AppTheme.readingTextColor(context) : null,
                    ),
                  ),
                ],
              ),
            ),
            if (set)
              OasisPressable(
                onTap: busy ? null : onRemove,
                pressedScale: 0.9,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.disputeColor,
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

/// The artisan directory for one trade, for a landlord choosing whom to
/// vouch for.
class _ArtisanPickerSheet extends StatefulWidget {
  final ArtisanCategory category;
  final String? current;
  final String? unitId;

  const _ArtisanPickerSheet({
    required this.category,
    this.current,
    this.unitId,
  });

  @override
  State<_ArtisanPickerSheet> createState() => _ArtisanPickerSheetState();
}

class _ArtisanPickerSheetState extends State<_ArtisanPickerSheet> {
  List<ArtisanProfile> _artisans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final controller = context.read<FixController>();
    final loaded = await controller.loadArtisanDirectory(
      widget.category.value,
      unitId: widget.unitId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _artisans = loaded ?? const [];
      _error = loaded == null ? controller.errorMessage : null;
    });
  }

  @override
  Widget build(BuildContext context) => OasisSheet(
    icon: Icons.person_search_outlined,
    title: 'Pick a ${widget.category.label.toLowerCase()}',
    subtitle: 'Only verified, active artisans can be recommended.',
    children: [
      if (_loading)
        const OasisSkeletonList(count: 3, padding: EdgeInsets.zero)
      else if (_error != null)
        OasisErrorBanner(message: _error!, onRetry: _load)
      else if (_artisans.isEmpty)
        OasisEmptyState(
          icon: Icons.person_off_outlined,
          title: 'Nobody listed yet',
          message:
              'No verified ${widget.category.label.toLowerCase()} is on Oasis '
              'right now. You can come back and set this later.',
          scrollable: false,
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
        )
      else
        for (final artisan in _artisans) ...[
          ArtisanCard(
            artisan: artisan,
            selected: artisan.id == widget.current,
            onTap: artisan.canBeContacted
                ? () => Navigator.pop(context, artisan)
                : null,
          ),
          const SizedBox(height: 12),
        ],
    ],
  );
}

/// Which trade a new recommendation is for.
class _CategoryChooserSheet extends StatelessWidget {
  final List<ArtisanCategory> categories;

  const _CategoryChooserSheet({required this.categories});

  @override
  Widget build(BuildContext context) => OasisSheet(
    icon: Icons.handshake_outlined,
    title: 'Which trade?',
    subtitle: 'One recommendation per trade.',
    children: [
      for (final category in categories) ...[
        OasisPressable(
          onTap: () => Navigator.pop(context, category),
          pressedScale: 0.99,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurfaceColor(context),
              borderRadius: AppTheme.cornerMd,
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    category.label,
                    style: AppTheme.cardTitle(context),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppTheme.mutedTextColor(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ],
  );
}
