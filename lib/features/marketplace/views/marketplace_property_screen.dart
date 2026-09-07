import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/utils/landa_refresh.dart';
import '../../../core/widgets/landa_media_hero.dart';
import '../../../core/widgets/landa_media_viewer.dart';
import '../../../core/widgets/landa_network_image.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../../core/widgets/landa_video_player.dart';
import '../../properties/models/property_model.dart';
import '../controllers/marketplace_controller.dart';
import '../models/marketplace_models.dart';
import 'apply_for_unit_sheet.dart';
import '../../../core/widgets/landa_busy.dart';

/// Tenant-facing property detail: photo gallery, tour video, and every
/// available unit with its own apply action.
class MarketplacePropertyScreen extends StatefulWidget {
  final MarketplaceProperty listing;

  const MarketplacePropertyScreen({super.key, required this.listing});

  @override
  State<MarketplacePropertyScreen> createState() =>
      _MarketplacePropertyScreenState();
}

class _MarketplacePropertyScreenState extends State<MarketplacePropertyScreen>
    with AutoRefreshMixin<MarketplacePropertyScreen> {
  /// A landlord can approve or reject while the tenant is on this page, and
  /// another tenant can take the flat. The per-unit status pills read from
  /// the application list, so it is that list, not the listing, that has to
  /// be re-read for them to mean anything.
  ///
  /// Polled, unlike most detail pages: this is one of the few screens in the
  /// app where the user is waiting for somebody else to act.
  @override
  Future<void> onAutoRefresh() =>
      context.read<MarketplaceController>().loadTenantApplications();

  @override
  Duration? get autoRefreshInterval => kLandaPollInterval;

  /// Photos to show: the cover first, then any others, de-duplicated so a
  /// cover that also appears in `photo_urls` isn't shown twice.
  List<String> get _galleryImages {
    final property = widget.listing.property;
    return {
      if (property.coverPhotoUrl != null && property.coverPhotoUrl!.isNotEmpty)
        property.coverPhotoUrl!,
      ...property.photoUrls.where((url) => url.isNotEmpty),
    }.toList();
  }

  Future<void> _apply(UnitModel unit) async {
    final controller = context.read<MarketplaceController>();
    final result = await showModalBottomSheet<ApplyResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ApplyForUnitSheet(unit: unit, listing: widget.listing),
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
    final property = widget.listing.property;
    final images = _galleryImages;
    final isVerified = property.verificationStatus.toUpperCase() == 'VERIFIED';
    final appliedUnitIds = controller.appliedUnitIds;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: AppTheme.pageBackground(context),
            automaticallyImplyLeading: false,
            // A frosted circle rather than a bare white arrow. The old one
            // was invisible against a photo of a white wall, which is most
            // photos of a Lagos building.
            leading: Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: LandaMediaCircleButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              // Photos only. The building's walkthrough keeps its own
              // labelled section below: a tenant applies for a flat, and a
              // clip of the compound is context rather than the thing being
              // decided on. Carrying it in the header as well would show the
              // same video twice on one screen.
              background: LandaMediaHero(
                photoUrls: images,
                title: property.name,
                height: 320,
                heroTag: landaMediaHeroTag('property', property.id),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          property.name,
                          style: AppTheme.screenTitle(
                            context,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                      if (isVerified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successSurface(context),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified,
                                size: 13,
                                color: AppTheme.successColor,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'VERIFIED',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.successColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
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
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryTextColor(context),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Kept for properties that still have one from before the
                  // walkthrough moved onto units. New listings will not have
                  // it, and the per-unit tours below are the ones that matter.
                  if (property.hasVideo) ...[
                    const SizedBox(height: 24),
                    const _SectionLabel('AROUND THE BUILDING'),
                    const SizedBox(height: 10),
                    LandaVideoPlayer(url: property.videoUrl!),
                  ],

                  const SizedBox(height: 28),
                  _SectionLabel(
                    '${widget.listing.availableUnits.length} '
                    '${widget.listing.availableUnits.length == 1 ? 'UNIT' : 'UNITS'} AVAILABLE',
                  ),
                  const SizedBox(height: 10),
                  ...widget.listing.availableUnits.map(
                    (unit) => _UnitCard(
                      unit: unit,
                      hasApplied: appliedUnitIds.contains(unit.id),
                      isApplying: controller.applyingUnitId == unit.id,
                      onApply: () => _apply(unit),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.8,
      color: Colors.grey,
    ),
  );
}

/// One available unit, with its own walkthrough.
///
/// The video is inside the unit card rather than at the top of the screen,
/// because that is the question a tenant is actually asking: not "what is
/// this building like" but "what is *this flat* like". A block of eight
/// answers that eight different ways.
class _UnitCard extends StatelessWidget {
  final UnitModel unit;
  final bool hasApplied;
  final bool isApplying;
  final VoidCallback onApply;

  const _UnitCard({
    required this.unit,
    required this.hasApplied,
    required this.isApplying,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unit.hasVideo) ...[
            // Poster left unprepared: every unit card on this screen is
            // built in one pass, so preparing them all would open a stream
            // per flat the moment the property opened. The tap that asks for
            // a walkthrough is what fetches it.
            LandaVideoPlayer(url: unit.videoUrl!, preparePoster: false),
            const SizedBox(height: 12),
          ],
          // Photos of the flat itself, shown whether or not there is a
          // walkthrough: a tenant applies for one unit, and the building's
          // cover shot tells them nothing about it. Tapping opens the set
          // full screen, which is where the decision actually gets made.
          if (unit.photoUrls.isNotEmpty) ...[
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: unit.photoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) => GestureDetector(
                  onTap: () => openLandaMediaViewer(
                    context,
                    photoUrls: unit.photoUrls,
                    initialIndex: index,
                    title: 'Unit ${unit.unitNumber}',
                  ),
                  child: LandaNetworkImage(
                    url: unit.photoUrls[index],
                    width: 122,
                    height: 92,
                    borderRadius: AppTheme.cornerSm,
                    placeholderIcon: Icons.meeting_room_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unit ${unit.unitNumber}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      LandaCurrency.perYear(unit.rentAmount),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
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
                      horizontal: 20,
                      vertical: 12,
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
        ],
      ),
    );
  }
}
