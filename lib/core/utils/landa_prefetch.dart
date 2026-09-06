import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Warms the images a screen is about to need, before it is on screen.
///
/// A detail screen opens with a 340pt photograph at the top of it. Left alone,
/// the fetch for that photo starts when the header first builds, which is
/// *after* the push animation has run, so the transition lands on an empty
/// block and the picture arrives a beat later. The card that was tapped
/// already had a smaller version of that same photo decoded and on disk, and
/// the rest of the set is usually one request away.
///
/// So: start them on the tap. 280ms of route animation is 280ms of download
/// that would otherwise happen in full view of the person waiting, and on a
/// slow connection it is the difference between a header that is ready and
/// one that fills in while being looked at.
///
/// Deliberately fire-and-forget. A prefetch is a guess about what somebody
/// will look at next, and a guess that fails (no network, a dead URL, a
/// screen closed before it finished) must never surface as an error or block
/// the navigation it was meant to help.
class LandaPrefetch {
  const LandaPrefetch._();

  /// How many photos ahead to warm.
  ///
  /// The header shows one and a swipe reveals the second, so three covers
  /// what anybody sees in the first few seconds. Fetching a twelve-photo set
  /// on every card tap would spend a tenant's data on pictures they never
  /// scrolled to.
  static const int _lookahead = 3;

  /// Warms the first few of [urls] into the image cache.
  static void images(BuildContext context, Iterable<String?> urls) {
    final wanted = urls
        .whereType<String>()
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .take(_lookahead);

    for (final url in wanted) {
      // The same provider `LandaNetworkImage` will ask for, so the work is
      // shared rather than duplicated: by the time the header builds, this is
      // already a cache hit.
      precacheImage(
        CachedNetworkImageProvider(url),
        context,
        onError: (_, _) {},
      );
    }
  }
}
