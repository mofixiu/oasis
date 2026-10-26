import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/fade_page_route.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/v2_ui.dart';
import '../../../auth/controllers/auth_controller.dart';
import '../../controllers/saved_shortlets_controller.dart';
import '../../controllers/shortlet_controller.dart';
import '../../models/shortlet_models.dart';
import '../shortlet_browse_screen.dart';
import '../shortlet_listing_screen.dart';
import 'v2_empty_state.dart';
import 'v2_stay_widgets.dart';

/// The shortlets a guest has hearted, two to a row.
class V2SavedScreen extends StatefulWidget {
  const V2SavedScreen({super.key});

  @override
  State<V2SavedScreen> createState() => _V2SavedScreenState();
}

class _V2SavedScreenState extends State<V2SavedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final userId = context.read<AuthController>().currentUser?.id;
    final shortlets = context.read<ShortLetController>();
    await Future.wait([
      if (userId != null) context.read<SavedShortLetsController>().load(userId),
      if (shortlets.browseListings.isEmpty) shortlets.loadBrowseListings(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<SavedShortLetsController>();
    final browse = context.watch<ShortLetController>().browseListings;
    final listings = saved.savedListings(browse);
    final shown = listings;

    return V2StatusBar(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.paddingOf(context).bottom + 28,
              ),
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
                        'Saved',
                        textAlign: TextAlign.center,
                        style: AppTheme.sectionTitle(context),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 18),
                if (!saved.hasLoaded && listings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (listings.isEmpty)
                  V2IllustratedEmptyState(
                    artwork: V2EmptyArtwork.home,
                    title: 'Nothing saved yet.',
                    message:
                        'Tap the heart on any shortlet to keep it here for '
                        'later.',
                    actionLabel: 'Explore shortlets',
                    onAction: () => Navigator.pushReplacement(
                      context,
                      FadePageRoute(
                        page: const ShortLetBrowseScreen(
                          isV2: true,
                          isSearch: true,
                        ),
                      ),
                    ),
                    scrollable: false,
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.62,
                        ),
                    itemCount: shown.length,
                    itemBuilder: (context, index) =>
                        _SavedCard(listing: shown[index]),
                  ),
                // Honest about where saves live until the server keeps them.
                if (listings.isNotEmpty &&
                    saved.hasLoaded &&
                    !saved.isSyncedToServer) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Saved on this phone for now.',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyText(
                      context,
                      color: AppTheme.mutedTextColor(context),
                    ).copyWith(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  final ShortLetListing listing;

  const _SavedCard({required this.listing});

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: () => Navigator.push(
      context,
      FadePageRoute(page: ShortLetListingScreen(listing: listing, isV2: true)),
    ),
    pressedScale: 0.98,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                V2StayPhoto(url: listing.coverPhotoUrl),
                Positioned(
                  top: 8,
                  right: 8,
                  child: V2SaveButton(listing: listing, size: 32),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          listing.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.cardTitle(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 13,
              color: AppTheme.secondaryTextColor(context),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                listing.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyText(context).copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        V2RatingLine(listing: listing, compact: true),
        const SizedBox(height: 6),
        V2NightlyPrice(amount: listing.nightlyPrice, fontSize: 15),
      ],
    ),
  );
}
