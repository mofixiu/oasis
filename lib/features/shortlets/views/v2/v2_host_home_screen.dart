import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/oasis_app_bar.dart';
import '../../../../core/widgets/oasis_network_image.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_shimmer.dart';
import '../../../../core/widgets/oasis_state_views.dart';
import '../../../properties/models/property_model.dart';
import '../../../properties/views/widgets/unit_media_sheet.dart';
import '../../controllers/shortlet_controller.dart';
import '../../models/shortlet_models.dart';
import '../widgets/caution_fee_widgets.dart';
import 'v2_empty_state.dart';

class V2HostHomeScreen extends StatefulWidget {
  final VoidCallback onManageStays;

  const V2HostHomeScreen({super.key, required this.onManageStays});

  @override
  State<V2HostHomeScreen> createState() => _V2HostHomeScreenState();
}

class _V2HostHomeScreenState extends State<V2HostHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<ShortLetController>();
      controller.loadLandlordListings();
      controller.loadLandlordBookings();
    });
  }

  Future<void> _reload() {
    final controller = context.read<ShortLetController>();
    return Future.wait([
      controller.loadLandlordListings(),
      controller.loadLandlordBookings(),
    ]);
  }

  Future<void> _openPhotos(ShortLetListing listing) async {
    if (listing.unitId.isEmpty) return;
    await openUnitMediaSheet(
      context,
      unit: UnitModel(
        id: listing.unitId,
        unitNumber: listing.unitNumber,
        bedrooms: listing.bedrooms,
        bathrooms: listing.bathrooms,
        rentAmount: '0.00',
        isOccupied: false,
        createdAt: '',
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.pageBackground(context),
    appBar: const OasisAppBar(shortLetOnlyProfile: true),
    body: Consumer<ShortLetController>(
      builder: (context, controller, _) {
        if (!controller.hasLoaded(ShortLetController.kListingsKey) &&
            controller.listings.isEmpty) {
          return const OasisSkeletonList(count: 3);
        }
        if (controller.hasError && controller.listings.isEmpty) {
          return OasisErrorState(
            message: controller.errorMessage,
            isConnectionError: controller.errorIsConnection,
            onRetry: _reload,
          );
        }
        if (controller.listings.isEmpty) {
          return V2IllustratedEmptyState(
            artwork: V2EmptyArtwork.hosting,
            title: 'Make room for your first guests.',
            message:
                'List a furnished place by the night, set your house rules, '
                'and decide who you welcome.',
            actionLabel: 'Manage shortlets',
            onAction: widget.onManageStays,
          );
        }

        final toInspect = controller.bookings
            .where((b) => b.isAwaitingCheckoutInspection)
            .toList();
        final liveBookings = controller.liveBookings.length;
        final paidBookings = controller.bookings
            .where((b) => b.status.isPaid)
            .length;
        final featured = controller.listings.first;
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 118),
            children: [
              Text(
                'Your hosting',
                style: AppTheme.screenTitle(context).copyWith(fontSize: 28),
              ),
              const SizedBox(height: 5),
              Text(
                'Places, guests and the next thing to do.',
                style: AppTheme.bodyText(context),
              ),
              const SizedBox(height: 18),
              _HostHero(listing: featured, onManage: widget.onManageStays),
              const SizedBox(height: 20),
              if (toInspect.isNotEmpty) ...[
                _InspectionNudge(
                  count: toInspect.length,
                  soonest: toInspect
                      .map((b) => b.cautionClaimWindowLeft)
                      .whereType<Duration>()
                      .fold<Duration?>(
                        null,
                        (min, left) => min == null || left < min ? left : min,
                      ),
                  onTap: widget.onManageStays,
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                height: 122,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  children: [
                    _MetricCard(
                      label: 'YOUR PLACES',
                      value: '${controller.listings.length}',
                      icon: Icons.holiday_village_outlined,
                      tint: AppTheme.vacantSurface(context),
                    ),
                    const SizedBox(width: 10),
                    _MetricCard(
                      label: 'NEEDS A REPLY',
                      value: '${controller.pendingBookingCount}',
                      icon: Icons.mark_chat_unread_outlined,
                      tint: AppTheme.logoutSurface(context),
                      accent: AppTheme.terracottaColor,
                    ),
                    const SizedBox(width: 10),
                    _MetricCard(
                      label: 'GUEST STAYS',
                      value: '$liveBookings',
                      icon: Icons.luggage_outlined,
                      subtitle: '$paidBookings paid',
                      tint: AppTheme.successSurface(context),
                      accent: AppTheme.successColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _HostNextStep(
                pendingCount: controller.pendingBookingCount,
                onTap: widget.onManageStays,
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your places',
                      style: AppTheme.sectionTitle(context),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onManageStays,
                    child: const Text('Manage'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final listing in controller.listings.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ListingSummary(
                    listing: listing,
                    onTap: widget.onManageStays,
                    onPhotos: () => _openPhotos(listing),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final String? subtitle;
  final Color tint;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    this.accent,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: accent ?? AppTheme.profileColor),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  style: AppTheme.labelText(context).copyWith(fontSize: 9),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppTheme.screenTitle(context).copyWith(fontSize: 25),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyText(context).copyWith(fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingSummary extends StatelessWidget {
  final ShortLetListing listing;
  final VoidCallback onTap;
  final VoidCallback onPhotos;
  const _ListingSummary({
    required this.listing,
    required this.onTap,
    required this.onPhotos,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhotos =
        listing.photoUrls.isNotEmpty || listing.coverPhotoUrl != null;
    final photoCount = listing.photoUrls.isNotEmpty
        ? listing.photoUrls.length
        : (listing.coverPhotoUrl == null ? 0 : 1);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppTheme.borderColor(context)),
        boxShadow: AppTheme.cardShadow(context),
      ),
      child: Column(
        children: [
          OasisPressable(
            onTap: onTap,
            child: Row(
              children: [
                OasisNetworkImage(
                  url: listing.coverPhotoUrl,
                  width: 76,
                  height: 76,
                  placeholderIcon: Icons.holiday_village_outlined,
                  borderRadius: BorderRadius.circular(14),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.cardTitle(context),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        listing.location.isEmpty
                            ? 'Location not set'
                            : listing.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyText(
                          context,
                        ).copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      _ListingStatus(active: listing.isActive),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Divider(height: 1, color: AppTheme.borderColor(context)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 16,
                color: AppTheme.mutedTextColor(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !hasPhotos
                      ? 'Help guests picture the stay'
                      : '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
                  style: AppTheme.bodyText(context).copyWith(fontSize: 11),
                ),
              ),
              if (listing.unitId.isNotEmpty)
                TextButton.icon(
                  onPressed: onPhotos,
                  icon: Icon(
                    !hasPhotos
                        ? Icons.add_photo_alternate_outlined
                        : Icons.edit_outlined,
                    size: 16,
                  ),
                  label: Text(!hasPhotos ? 'Add photos' : 'Manage'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListingStatus extends StatelessWidget {
  final bool active;

  const _ListingStatus({required this.active});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: active
          ? AppTheme.successSurface(context)
          : AppTheme.vacantSurface(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      active ? 'Live' : 'Paused',
      style: AppTheme.labelText(context).copyWith(
        color: active ? AppTheme.successColor : AppTheme.primaryColor,
        fontSize: 10,
      ),
    ),
  );
}

class _HostHero extends StatelessWidget {
  final ShortLetListing listing;
  final VoidCallback onManage;

  const _HostHero({required this.listing, required this.onManage});

  @override
  Widget build(BuildContext context) => Container(
    height: 218,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFF425F55),
      borderRadius: BorderRadius.circular(24),
      boxShadow: AppTheme.cardShadow(context),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (listing.coverPhotoUrl case final photo?)
          OasisNetworkImage(
            url: photo,
            placeholderIcon: Icons.home_work_outlined,
          )
        else
          const _HostHeroArtwork(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x12000000), Color(0xC9000000)],
              stops: [0.15, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.19),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                ),
                child: const Text(
                  'YOUR HOSTING DASHBOARD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Make every stay\nfeel like home.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.12,
                  letterSpacing: -0.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                listing.location.isEmpty
                    ? listing.title
                    : '${listing.title} · ${listing.location}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: onManage,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                  label: const Text('Manage your stays'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HostHeroArtwork extends StatelessWidget {
  const _HostHeroArtwork();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6F8F72), Color(0xFFB65F3C)],
          ),
        ),
      ),
      Positioned(
        right: -30,
        top: -55,
        child: Container(
          height: 210,
          width: 210,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.13),
              width: 28,
            ),
          ),
        ),
      ),
      Positioned(
        right: 29,
        bottom: 35,
        child: Icon(
          Icons.holiday_village_rounded,
          size: 90,
          color: Colors.white.withValues(alpha: 0.24),
        ),
      ),
    ],
  );
}

class _HostNextStep extends StatelessWidget {
  final int pendingCount;
  final VoidCallback onTap;

  const _HostNextStep({required this.pendingCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final needsReply = pendingCount > 0;
    return OasisPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: needsReply
              ? AppTheme.vacantSurface(context)
              : AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: needsReply
                    ? AppTheme.surfaceColor(context)
                    : AppTheme.successSurface(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                needsReply
                    ? Icons.mark_chat_unread_outlined
                    : Icons.check_rounded,
                color: needsReply
                    ? AppTheme.terracottaColor
                    : AppTheme.successColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    needsReply
                        ? '$pendingCount ${pendingCount == 1 ? 'booking needs' : 'bookings need'} a reply'
                        : 'You’re all caught up',
                    style: AppTheme.cardTitle(context),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    needsReply
                        ? 'Open your requests and decide on the dates.'
                        : 'Check your places or update their photos and details.',
                    style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
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

/// A prompt to inspect places guests have just left, before the caution fee
/// goes back to them on its own.
class _InspectionNudge extends StatelessWidget {
  final int count;
  final Duration? soonest;
  final VoidCallback? onTap;

  const _InspectionNudge({
    required this.count,
    required this.soonest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppTheme.isDarkMode(context)
        ? AppTheme.sandColor
        : const Color(0xFF85602F);
    return OasisPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.vacantSurface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ink.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.fact_check_outlined, color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1
                        ? '1 checkout to inspect'
                        : '$count checkouts to inspect',
                    style: AppTheme.cardTitle(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    soonest == null
                        ? 'Refund the caution fee or report damage within 24 '
                              'hours of checkout.'
                        : 'Refund the caution fee or report damage. '
                              '${cautionWindowLabel(soonest!)} on the next one.',
                    style: AppTheme.bodyText(context).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: ink),
          ],
        ),
      ),
    );
  }
}
