import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'oasis_network_image.dart';
import 'oasis_video_player.dart';

/// Opens the photos full screen, starting on [initialIndex].
///
/// A route rather than a dialog so the system back gesture closes it and the
/// transition can be owned: it fades up out of black instead of sliding in
/// from the side, which is what makes tapping a photo feel like the photo
/// growing rather than a new screen arriving.
Future<void> openOasisMediaViewer(
  BuildContext context, {
  required List<String> photoUrls,
  int initialIndex = 0,
  String? videoUrl,
  String? title,
}) {
  if (photoUrls.isEmpty && (videoUrl == null || videoUrl.isEmpty)) {
    return Future.value();
  }
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => OasisMediaViewer(
        photoUrls: photoUrls,
        videoUrl: videoUrl,
        initialIndex: initialIndex,
        title: title,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Every photo of one place, full bleed, zoomable.
///
/// This is where somebody actually decides. The listing page is a summary; a
/// guest who is close to spending money on a room opens the pictures and
/// looks at the corners of them, which needs the whole screen, pinch zoom,
/// and nothing else competing for attention.
class OasisMediaViewer extends StatefulWidget {
  final List<String> photoUrls;

  /// The walkthrough, shown as the last page when there is one.
  final String? videoUrl;

  final int initialIndex;
  final String? title;

  const OasisMediaViewer({
    super.key,
    required this.photoUrls,
    this.videoUrl,
    this.initialIndex = 0,
    this.title,
  });

  @override
  State<OasisMediaViewer> createState() => _OasisMediaViewerState();
}

class _OasisMediaViewerState extends State<OasisMediaViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex.clamp(0, _pageCount - 1),
  );
  late int _index = widget.initialIndex.clamp(0, _pageCount - 1);

  /// How far the viewer has been dragged down, in logical pixels. Drives both
  /// the sheet's offset and how far the backdrop has faded: a dismissal the
  /// finger is in charge of, rather than an animation that plays at it.
  double _dragOffset = 0;

  /// Whether a photo is currently zoomed in. While it is, the pager and the
  /// drag-to-dismiss both stand down: a two-finger zoom that fires a page
  /// turn is the single most infuriating thing a photo viewer can do.
  bool _isZoomed = false;

  bool get _hasVideo => (widget.videoUrl?.isNotEmpty ?? false);

  int get _pageCount => widget.photoUrls.length + (_hasVideo ? 1 : 0);

  /// Fully opaque until the drag starts, then thinning towards transparent so
  /// the screen behind shows through as the viewer is pulled away.
  double get _backdropOpacity =>
      (1 - (_dragOffset.abs() / 320)).clamp(0.0, 1.0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    // Either a long pull or a quick flick closes it. Requiring distance alone
    // makes a fast swipe feel ignored; velocity alone closes on a stray
    // scroll.
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_dragOffset.abs() > 140 || velocity.abs() > 700) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final label = _pageCount > 1 ? '${_index + 1} / $_pageCount' : null;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: _backdropOpacity),
      body: GestureDetector(
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: PageView.builder(
                  controller: _controller,
                  // Locked while zoomed, so panning around a photo never
                  // turns the page out from under the finger.
                  physics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  onPageChanged: (index) => setState(() => _index = index),
                  itemCount: _pageCount,
                  itemBuilder: (context, index) {
                    if (_hasVideo && index == _pageCount - 1) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: OasisVideoPlayer(url: widget.videoUrl!),
                        ),
                      );
                    }
                    return _ZoomablePhoto(
                      url: widget.photoUrls[index],
                      onZoomChanged: (zoomed) {
                        if (zoomed != _isZoomed) {
                          setState(() => _isZoomed = zoomed);
                        }
                      },
                    );
                  },
                ),
              ),
            ),

            // Chrome: a close button, the count, and the place's name. It
            // fades out with the backdrop so a dismissal takes the whole
            // screen with it rather than leaving buttons floating over the
            // page underneath.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: _backdropOpacity,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        _ViewerButton(
                          icon: Icons.close_rounded,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        if (label != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppTheme.textSm,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            if (widget.title != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Opacity(
                  opacity: _backdropOpacity,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      child: Text(
                        widget.title!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: AppTheme.textSm,
                          fontWeight: FontWeight.w500,
                        ),
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

/// One photo, pinch-zoomable, reporting when it is zoomed so the pager can
/// get out of the way.
class _ZoomablePhoto extends StatefulWidget {
  final String url;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePhoto({required this.url, required this.onZoomChanged});

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final _controller = TransformationController();

  /// Animates the snap back to fit after a double tap, so the photo settles
  /// instead of jumping.
  late final AnimationController _reset = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(_applyResetFrame);

  Animation<Matrix4>? _resetAnimation;

  void _applyResetFrame() {
    final animation = _resetAnimation;
    if (animation != null) _controller.value = animation.value;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reportZoom);
  }

  void _reportZoom() {
    // A hair over 1 rather than exactly 1: the matrix carries floating-point
    // dust after a gesture, and comparing to 1.0 leaves the pager locked on a
    // photo the viewer has already released.
    widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.02);
  }

  /// How far a double tap zooms in. Enough to read a plug socket or a crack
  /// in a wall, which is what somebody zooming into a room photo is doing.
  static const double _doubleTapScale = 2.5;

  /// Double tap toggles between fit and [_doubleTapScale], centred on the
  /// tap. The gesture everybody already has in their hands from every other
  /// photo app.
  void _handleDoubleTap(TapDownDetails details) {
    final zoomedIn = _controller.value.getMaxScaleOnAxis() > 1.02;
    _resetAnimation = Matrix4Tween(
      begin: _controller.value,
      end: zoomedIn ? Matrix4.identity() : _zoomedTo(details.localPosition),
    ).animate(CurvedAnimation(parent: _reset, curve: Curves.easeOutCubic));
    _reset.forward(from: 0);
  }

  /// The transform that scales up while keeping [focal] under the finger.
  ///
  /// Built column-major by hand rather than with `Matrix4`'s translate/scale
  /// helpers: those have churned across vector_math versions, and the whole
  /// matrix is four numbers.
  static Matrix4 _zoomedTo(Offset focal) {
    const scale = _doubleTapScale;
    return Matrix4(
      scale,
      0,
      0,
      0, //
      0,
      scale,
      0,
      0, //
      0,
      0,
      1,
      0, //
      -focal.dx * (scale - 1),
      -focal.dy * (scale - 1),
      0,
      1,
    );
  }

  @override
  void dispose() {
    _reset.removeListener(_applyResetFrame);
    _reset.dispose();
    _controller.removeListener(_reportZoom);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onDoubleTapDown: _handleDoubleTap,
    // Swallowed so the double tap has something to land on across the whole
    // page, not only on the pixels of the photo.
    onDoubleTap: () {},
    child: InteractiveViewer(
      transformationController: _controller,
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: OasisNetworkImage(
          url: widget.url,
          fit: BoxFit.contain,
          placeholderIcon: Icons.image_outlined,
        ),
      ),
    ),
  );
}

/// A frosted circular control over the photo. Dark enough to stay legible on
/// a white wall, translucent enough not to sit on top of the picture.
class _ViewerButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ViewerButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.45),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    ),
  );
}
