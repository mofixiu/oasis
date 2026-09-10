import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'oasis_media_viewer.dart';
import 'oasis_network_image.dart';
import 'oasis_video_player.dart';

/// The full-bleed photo header at the top of a place's detail screen.
///
/// One of these on Stays and one on the rental marketplace, because it is the
/// same job in both: a person has tapped a card and wants to *see the place*.
/// What was there before (a 200pt rounded photo inset inside the page
/// padding, with the video in a second box below it) read as a form with an
/// illustration on it. A listing is sold by its pictures, so the pictures get
/// the top of the screen, edge to edge, and everything else starts below
/// them.
///
/// Three things it does that the old header did not:
///
/// - **Swipes.** Every photo is reachable here rather than only the cover.
/// - **Opens.** Tapping goes full screen with pinch zoom, on the tapped photo.
/// - **Holds its shape while loading.** No spinner, no shimmer: the block is
///   the size of the photo that is coming, and the photo fades onto it.
class OasisMediaHero extends StatefulWidget {
  final List<String> photoUrls;

  /// The walkthrough. Shown as its own page after the photos, marked with a
  /// play badge in the counter row.
  final String? videoUrl;

  /// Height of the header. Tall enough to be the screen's subject on a phone,
  /// short enough that the price and the button are still reachable in one
  /// scroll.
  final double height;

  /// Painted over the photo, bottom-aligned: the title block on the detail
  /// screens. Laid over the image rather than under it so the first thing on
  /// screen is the place and its name together.
  final Widget? overlay;

  /// How far the overlay sits above the bottom of the photo.
  ///
  /// Callers that pull the page up over the header (the Stays screen lifts
  /// its content by a corner radius) have to add that overlap here, or the
  /// sheet lands on the last line of the title.
  final double overlayBottomInset;

  /// Name used as the caption in the full-screen viewer.
  final String? title;

  /// Drawn faintly when there is nothing to show at all.
  final IconData emptyIcon;

  /// Ties the first photo to the card that opened this screen, so the picture
  /// grows into place instead of a new screen arriving over it.
  ///
  /// Only the first page carries it: that is the photo the card was showing,
  /// and it is the only one the flight has a counterpart for. Once the pager
  /// moves off page one the tag is dropped, because a Hero must be unique on
  /// screen and flying back to a card showing a different picture would be a
  /// worse animation than none.
  final Object? heroTag;

  const OasisMediaHero({
    super.key,
    required this.photoUrls,
    this.videoUrl,
    this.height = 340,
    this.overlay,
    this.overlayBottomInset = 18,
    this.title,
    this.emptyIcon = Icons.home_work_outlined,
    this.heroTag,
  });

  @override
  State<OasisMediaHero> createState() => _OasisMediaHeroState();
}

class _OasisMediaHeroState extends State<OasisMediaHero> {
  final _controller = PageController();
  int _index = 0;

  bool get _hasVideo => widget.videoUrl?.isNotEmpty ?? false;

  /// Photos plus the video page. Never zero: an empty listing still renders
  /// one page, which is the placeholder.
  int get _pageCount {
    final count = widget.photoUrls.length + (_hasVideo ? 1 : 0);
    return count == 0 ? 1 : count;
  }

  bool get _isOnVideoPage => _hasVideo && _index == _pageCount - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    openOasisMediaViewer(
      context,
      photoUrls: widget.photoUrls,
      videoUrl: widget.videoUrl,
      // Land on whatever they were looking at. Opening a gallery on photo one
      // when the viewer had swiped to photo five is the kind of small
      // disregard that adds up.
      initialIndex: _index,
      title: widget.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photoUrls;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photos.isEmpty && !_hasVideo)
            OasisNetworkImage(
              url: null,
              placeholderIcon: widget.emptyIcon,
              heroTag: widget.heroTag,
            )
          else
            PageView.builder(
              controller: _controller,
              onPageChanged: (index) => setState(() => _index = index),
              itemCount: _pageCount,
              itemBuilder: (context, index) {
                if (_hasVideo && index == _pageCount - 1) {
                  // The video page is a still with a play badge, not a live
                  // player: an inline player inside a pager fights the swipe,
                  // and its controls sit where the page indicator is. Tapping
                  // opens the viewer, which is where a video should be
                  // watched anyway.
                  return _VideoPage(videoUrl: widget.videoUrl!, onTap: _open);
                }
                return GestureDetector(
                  onTap: _open,
                  child: OasisNetworkImage(
                    url: photos[index],
                    fit: BoxFit.cover,
                    placeholderIcon: widget.emptyIcon,
                    heroTag: index == 0 && _index == 0 ? widget.heroTag : null,
                  ),
                );
              },
            ),

          // Top scrim. The back button and the status bar sit on this, and a
          // white icon over a photo of a white wall is unreadable without it.
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: _Scrim(fromTop: true),
          ),

          // Bottom scrim, deeper: it carries the title block, and text needs
          // more cover than an icon does.
          if (widget.overlay != null)
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 230,
              child: _Scrim(fromTop: false),
            ),

          if (widget.overlay != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: widget.overlayBottomInset,
              child: widget.overlay!,
            ),

          // Counter rather than dots. Eleven dots is a smear; "3 / 11" is a
          // number, and it also tells someone how much there is left to look
          // at before they have to decide whether to keep swiping.
          if (_pageCount > 1)
            Positioned(
              top: 0,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _CounterPill(
                    label: '${_index + 1} / $_pageCount',
                    icon: _isOnVideoPage
                        ? Icons.play_circle_outline_rounded
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One page of the pager: the walkthrough's own first frame, with a play
/// badge over it.
///
/// The frame comes from the video rather than from the listing's cover photo,
/// which is what this page used to show. A photograph of the gate standing in
/// for a video of the rooms meant tapping play cut to an unrelated scene:
/// the poster was not a preview of anything, it was a different picture that
/// happened to be lying around.
class _VideoPage extends StatelessWidget {
  final String videoUrl;
  final VoidCallback onTap;

  const _VideoPage({required this.videoUrl, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: OasisVideoPoster(
      url: videoUrl,
      overlay: const Center(child: OasisVideoPlayButton(size: 66)),
    ),
  );
}

/// A soft top-or-bottom gradient over the photo.
///
/// Four stops rather than two: a straight linear fade to transparent has a
/// visible edge where it lands, and on a photo of an even sky that edge reads
/// as a band across the picture.
class _Scrim extends StatelessWidget {
  final bool fromTop;

  const _Scrim({required this.fromTop});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: fromTop ? 0.55 : 0.88),
            Colors.black.withValues(alpha: fromTop ? 0.28 : 0.62),
            Colors.black.withValues(alpha: fromTop ? 0.10 : 0.26),
            Colors.transparent,
          ],
          stops: const [0.0, 0.35, 0.7, 1.0],
        ),
      ),
    ),
  );
}

/// "3 / 11" over the photo, in the frosted-pill language the rest of the
/// media chrome uses.
class _CounterPill extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _CounterPill({required this.label, this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: AppTheme.textXs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ],
    ),
  );
}

/// The round, frosted control that floats on a photo header: the back button
/// on both detail screens.
///
/// A bare white arrow on a photograph is legible on a dark roof and invisible
/// on a bright sky. This one carries its own contrast.
class OasisMediaCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const OasisMediaCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
