import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/landa_currency.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../../core/widgets/landa_video_player.dart';
import '../../properties/models/property_model.dart';
import '../controllers/marketplace_controller.dart';
import '../models/marketplace_models.dart';
import 'apply_for_unit_sheet.dart';

/// Tenant-facing property detail: photo gallery, tour video, and every
/// available unit with its own apply action.
class MarketplacePropertyScreen extends StatefulWidget {
  final MarketplaceProperty listing;

  const MarketplacePropertyScreen({super.key, required this.listing});

  @override
  State<MarketplacePropertyScreen> createState() =>
      _MarketplacePropertyScreenState();
}

class _MarketplacePropertyScreenState extends State<MarketplacePropertyScreen> {
  final _galleryController = PageController();
  int _galleryIndex = 0;

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }

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
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppTheme.pageBackground(context),
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: _Gallery(
                images: images,
                controller: _galleryController,
                currentIndex: _galleryIndex,
                onPageChanged: (index) => setState(() => _galleryIndex = index),
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
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
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
                            color: AppTheme.successSurfaceColor,
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

                  if (property.hasVideo) ...[
                    const SizedBox(height: 24),
                    const _SectionLabel('PROPERTY TOUR'),
                    const SizedBox(height: 10),
                    LandaVideoPlayer(
                      url: property.videoUrl!,
                      thumbnailUrl: property.displayImageUrl,
                    ),
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

class _Gallery extends StatelessWidget {
  final List<String> images;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  const _Gallery({
    required this.images,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        color: AppTheme.primaryColor.withValues(alpha: .12),
        child: const Center(
          child: Icon(
            Icons.home_work_outlined,
            size: 72,
            color: AppTheme.primaryColor,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: controller,
          onPageChanged: onPageChanged,
          itemCount: images.length,
          itemBuilder: (context, index) => Image.network(
            images[index],
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppTheme.primaryColor.withValues(alpha: .12),
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ),
        ),
        // Scrim so the back button stays legible over bright photos.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 110,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        if (images.length > 1)
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                images.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: index == currentIndex ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: index == currentIndex
                        ? Colors.white
                        : Colors.white54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
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
      child: Row(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                  horizontal: 20,
                  vertical: 12,
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
