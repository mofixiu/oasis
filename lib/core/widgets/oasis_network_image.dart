import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one way a remote image reaches the screen.
///
/// Every photo in this app is somebody's home, and how it arrives is most of
/// what the app feels like. Three rules, all of them reactions to what was
/// there before:
///
/// **No spinner.** A circular progress indicator over a photo says "the
/// software is working" when the only thing the viewer cares about is the
/// room. It also lies about progress: it spins at the same speed whether the
/// image is 40% in or stalled, and on a grid it produces a screen of
/// competing little wheels. What replaces it is a still, tinted block the
/// exact shape of the image that is coming.
///
/// **No shimmer either.** A sweeping highlight is right for a list of cards
/// whose *layout* is unknown; it is wrong for a single photo whose frame is
/// already drawn and whose only missing part is the picture. Animating that
/// space draws the eye to the emptiness. The placeholder here holds still.
///
/// **Fade, never pop.** A decoded image is cross-faded over its placeholder,
/// so a gallery settles rather than flickering. An image already in the cache
/// is drawn immediately with no fade at all: animating something that was
/// never absent is the other way to look cheap.
///
/// **Cached to disk.** `Image.network` keeps decoded frames in memory and
/// nothing else, so scrolling a list and coming back re-downloaded every
/// photo: on a Nigerian connection that is the difference between a screen
/// that reopens instantly and one that reloads from scratch every time.
/// `CachedNetworkImage` writes them to disk, so the second visit costs
/// nothing and the photos a tenant has already seen survive going offline.
class OasisNetworkImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Rounds the image and its placeholder together, so the corner radius is
  /// right from the first frame rather than appearing when the photo does.
  final BorderRadius? borderRadius;

  /// Drawn faintly on the placeholder and on failure. Null shows a plain
  /// block, which is what a small thumbnail wants.
  final IconData? placeholderIcon;

  /// How long the cross-fade runs. Slow enough to read as deliberate, short
  /// enough that nobody waits on it.
  final Duration fadeDuration;

  /// Darkens the image, for photos that sit under white text.
  final double scrimOpacity;

  /// Ties this image to the same photo on the screen being opened, so tapping
  /// a card grows its picture into the detail header rather than sliding a
  /// new screen over it. Null opts out: two live images may not share a tag,
  /// so lists pass something unique per row.
  final Object? heroTag;

  const OasisNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon,
    this.fadeDuration = const Duration(milliseconds: 320),
    this.scrimOpacity = 0,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final address = url?.trim() ?? '';
    final placeholder = _OasisImagePlaceholder(
      icon: placeholderIcon,
      width: width,
      height: height,
    );
    final image = address.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: address,
            width: width,
            height: height,
            fit: fit,
            fadeInDuration: fadeDuration,
            fadeInCurve: Curves.easeOut,
            // A photo already on disk is drawn on the first frame with no
            // fade. Animating something that was never absent is the other
            // way to look cheap.
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
            // Built by hand rather than left to the package's own layout,
            // which centres the image inside a loose box. That is the
            // letterboxing this widget exists to prevent: `BoxFit.cover` with
            // nothing to cover renders a portrait photo as a thin strip with
            // bars down both sides of a card that was the right shape all
            // along.
            imageBuilder: (context, provider) => Image(
              image: provider,
              width: width,
              height: height,
              fit: fit,
              // Keeps the previous frame up while a new URL decodes, so
              // paging a gallery never flashes the placeholder between shots.
              gaplessPlayback: true,
            ),
            placeholder: (_, _) => placeholder,
            // A photo that will not load is not worth a broken-glyph icon and
            // an error message. The unit is still real and still bookable:
            // it just shows the same quiet block as one with no photo.
            errorWidget: (_, _, _) => placeholder,
          );

    final painted = scrimOpacity <= 0
        ? image
        : Stack(
            fit: StackFit.passthrough,
            children: [
              image,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: scrimOpacity),
                  ),
                ),
              ),
            ],
          );

    // Isolated from the list around it. Without this, one photo fading in
    // repaints every card sharing its layer: on a marketplace scroll that is
    // a dozen cards repainting per frame for one image that finished
    // decoding, which is exactly the jank a photo grid is judged on.
    final clipped = RepaintBoundary(
      child: borderRadius == null
          ? painted
          : ClipRRect(borderRadius: borderRadius!, child: painted),
    );

    if (heroTag == null) return clipped;
    return Hero(
      tag: heroTag!,
      // The default flight rebuilds the subtree in an unbounded overlay,
      // where a cover-fitted photo has no box to fill and collapses mid-air.
      // Cross-fading the two ends inside the flight's own bounds keeps the
      // shape honest at every frame of the journey.
      flightShuttleBuilder: (_, animation, _, fromContext, toContext) {
        final from = fromContext.widget as Hero;
        final to = toContext.widget as Hero;
        return AnimatedBuilder(
          animation: animation,
          builder: (_, _) => Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: 1 - animation.value, child: from.child),
              Opacity(opacity: animation.value, child: to.child),
            ],
          ),
        );
      },
      child: clipped,
    );
  }
}

/// What occupies an image's space before, or instead of, the photo.
///
/// A flat tinted block with a barely-there icon. It is deliberately the same
/// widget for "loading", "no photo" and "failed to load": from the viewer's
/// side those are the same event (there is no picture here), and giving each
/// its own treatment only teaches them to read three states where one will do.
class _OasisImagePlaceholder extends StatelessWidget {
  final IconData? icon;

  /// Carried from the image so a fixed-size thumbnail's placeholder occupies
  /// exactly the space the photo will. Null means "fill whatever you are
  /// given", which is what a hero or a card image wants.
  final double? width;
  final double? height;

  const _OasisImagePlaceholder({this.icon, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDarkMode(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // A shade off the page rather than a grey: the block should read as
        // part of the surface it sits in, not as a hole in it.
        color: dark ? const Color(0xFF1E1E1E) : const Color(0xFFEDE8E2),
      ),
      alignment: Alignment.center,
      child: icon == null
          ? null
          : Icon(
              icon,
              size: 30,
              color: AppTheme.mutedTextColor(context).withValues(alpha: 0.35),
            ),
    );
  }
}

/// The tag shared by a card's photo and the header it opens into.
///
/// A function rather than a raw string at both ends, because the two ends
/// live in different files and a Hero only flies when the tags match exactly:
/// a typo produces no error, just a transition that silently stops
/// happening. [kind] keeps a property and a short let on the same unit from
/// colliding.
Object oasisMediaHeroTag(String kind, String id) => 'oasis-media:$kind:$id';
