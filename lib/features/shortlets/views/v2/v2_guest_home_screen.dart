import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/fade_page_route.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_shimmer.dart';
import '../../../../core/widgets/oasis_state_views.dart';
import '../../../../core/widgets/v2_ui.dart';
import '../../../auth/controllers/auth_controller.dart';
import '../../controllers/saved_shortlets_controller.dart';
import '../../controllers/shortlet_controller.dart';
import '../../models/shortlet_models.dart';
import '../shortlet_browse_screen.dart';
import '../shortlet_listing_screen.dart';
import 'v2_empty_state.dart';
import 'v2_stay_widgets.dart';

/// The guest's front door: a photo hero with the search bar, the occasions
/// people book for, trip ideas, and the featured shortlets.
class V2GuestHomeScreen extends StatefulWidget {
  final VoidCallback onDiscover;

  const V2GuestHomeScreen({super.key, required this.onDiscover});

  @override
  State<V2GuestHomeScreen> createState() => _V2GuestHomeScreenState();
}

class _V2GuestHomeScreenState extends State<V2GuestHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ShortLetController>().loadBrowseListings();
      final userId = context.read<AuthController>().currentUser?.id;
      if (userId != null) {
        context.read<SavedShortLetsController>().load(userId);
      }
    });
  }

  void _openListing(ShortLetListing listing) {
    Navigator.push(
      context,
      FadePageRoute(page: ShortLetListingScreen(listing: listing, isV2: true)),
    );
  }

  void _openSearch() => Navigator.push(
    context,
    FadePageRoute(page: const ShortLetBrowseScreen(isV2: true, isSearch: true)),
  );

  /// Every distinct photo across the loaded shortlets, covers first, so the
  /// hero and the trip cards can each show a different room.
  static List<String> _photoPool(List<ShortLetListing> listings) {
    final seen = <String>{};
    final covers = <String>[];
    final rest = <String>[];
    for (final listing in listings) {
      final cover = listing.coverPhotoUrl?.trim();
      if (cover != null && cover.isNotEmpty && seen.add(cover)) {
        covers.add(cover);
      }
      for (final url in listing.photoUrls) {
        final trimmed = url.trim();
        if (trimmed.isNotEmpty && seen.add(trimmed)) rest.add(trimmed);
      }
    }
    return [...covers, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();
    final listings = controller.browseListings;
    final photos = _photoPool(listings);

    final Widget sections;
    if (!controller.hasLoaded(ShortLetController.kBrowseKey) &&
        listings.isEmpty) {
      sections = const SizedBox(
        height: 300,
        child: OasisSkeletonList(
          count: 2,
          hasThumbnail: true,
          padding: EdgeInsets.symmetric(horizontal: 20),
        ),
      );
    } else if (controller.hasError && listings.isEmpty) {
      sections = SizedBox(
        height: 340,
        child: OasisErrorState(
          message: controller.errorMessage,
          isConnectionError: controller.errorIsConnection,
          onRetry: controller.loadBrowseListings,
        ),
      );
    } else if (listings.isEmpty) {
      sections = V2IllustratedEmptyState(
        artwork: V2EmptyArtwork.home,
        title: 'A good shortlet is out there.',
        message:
            'Beautiful places for your next break will show up here. '
            'Explore shortlets and find one that feels right.',
        actionLabel: 'Explore shortlets',
        onAction: widget.onDiscover,
        scrollable: false,
      );
    } else {
      sections = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: V2SectionHeader(
              title: 'Plan your trip',
              actionLabel: 'See all',
              onAction: widget.onDiscover,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _tripIdeas.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _TripIdeaCard(
                title: _tripIdeas[index],
                // Skips the photo the hero is already showing.
                photoUrl: photos.length > 1
                    ? photos[(index + 1) % photos.length]
                    : null,
                onTap: _openSearch,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: V2SectionHeader(
              title: 'Featured shortlets',
              actionLabel: 'See all',
              onAction: widget.onDiscover,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 330,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              clipBehavior: Clip.none,
              itemCount: listings.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) => V2StayCard(
                listing: listings[index],
                onTap: () => _openListing(listings[index]),
              ),
            ),
          ),
        ],
      );
    }

    return V2StatusBar(
      overPhoto: true,
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: RefreshIndicator(
          onRefresh: controller.loadBrowseListings,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 118),
            children: [
              _Hero(
                photoUrl: photos.isEmpty ? null : photos.first,
                onSearch: _openSearch,
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    for (final occasion in _occasions)
                      Expanded(
                        child: _OccasionTile(
                          occasion: occasion,
                          onTap: _openSearch,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              sections,
            ],
          ),
        ),
      ),
    );
  }
}

const _tripIdeas = [
  'Weekend escape',
  'Work trip',
  'Birthday getaway',
  'Girls’ trip',
];

/// Full-bleed photo with the brand, the promise, and the search bar.
class _Hero extends StatelessWidget {
  final String? photoUrl;
  final VoidCallback onSearch;

  const _Hero({required this.photoUrl, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: SizedBox(
        height: top + 380,
        child: Stack(
          fit: StackFit.expand,
          children: [
            V2StayPhoto(url: photoUrl, fallbackAsset: v2FallbackStayPhoto),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.20),
                    Colors.black.withValues(alpha: 0.50),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
            Positioned(
              top: top + 8,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/oasis_wordmark.png',
                    height: 40,
                    fit: BoxFit.contain,
                    semanticLabel: 'Oasis',
                  ),
                  const Spacer(),
                  const V2BellButton(onPhoto: true, size: 40),
                  const SizedBox(width: 10),
                  const V2ProfileButton(size: 40, onPhoto: true),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: top + 112,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Find your\nnext escape',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      height: 1.06,
                      letterSpacing: -1.4,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 18, color: Colors.black38)],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Beautiful shortlets for every plan.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 26,
              child: Semantics(
                button: true,
                label: 'Search shortlets',
                excludeSemantics: true,
                child: OasisPressable(
                  onTap: onSearch,
                  pressedScale: 0.98,
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor(context),
                      borderRadius: BorderRadius.circular(27),
                      boxShadow: AppTheme.raisedShadow(context),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 22,
                          color: AppTheme.secondaryTextColor(context),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Where are you going?',
                          style: AppTheme.bodyText(
                            context,
                          ).copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Occasion {
  final String label;
  final IconData icon;

  const _Occasion(this.label, this.icon);
}

const _occasions = [
  _Occasion('Staycation', Icons.holiday_village_outlined),
  _Occasion('Birthdays', Icons.cake_outlined),
  _Occasion('Baecation', Icons.favorite_border_rounded),
  _Occasion('Parties', Icons.celebration_outlined),
];

/// A rounded tile per occasion, icon over label.
class _OccasionTile extends StatelessWidget {
  final _Occasion occasion;
  final VoidCallback onTap;

  const _OccasionTile({required this.occasion, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: occasion.label,
    excludeSemantics: true,
    child: OasisPressable(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Icon(
              occasion.icon,
              size: 26,
              color: AppTheme.terracottaColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            occasion.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyText(context).copyWith(
              color: AppTheme.primaryTextColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A photo with a trip idea written on it.
class _TripIdeaCard extends StatelessWidget {
  final String title;
  final String? photoUrl;
  final VoidCallback onTap;

  const _TripIdeaCard({
    required this.title,
    required this.photoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: title,
    excludeSemantics: true,
    child: OasisPressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 124,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A trip idea, not a listing, so the bundled backdrop is fine.
              V2StayPhoto(url: photoUrl, fallbackAsset: v2FallbackStayPhoto),
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
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(
                  title,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
