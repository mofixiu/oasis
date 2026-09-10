import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';

/// Inline network video with Oasis's terracotta controls.
///
/// Wraps `video_player` + `chewie` so callers get buffering, scrubbing,
/// fullscreen and error handling without re-implementing them, and so
/// controller disposal happens in exactly one place.
///
/// **The poster is the video's own first frame.** It used to be the listing's
/// cover photo, which meant tapping play cut from a photograph of the gate to
/// a completely different scene: the video visibly *replacing* the picture
/// rather than starting. A still of the building is a fine picture of the
/// building and a lie about the video.
///
/// So the controller is prepared on mount and the widget renders frame zero,
/// which is what the guest will actually see when it starts. `initialize()`
/// fetches the header and enough of the stream to decode that frame, not the
/// whole clip. Chewie, and playback, only arrive when somebody taps, which
/// keeps the controls out of the way of a poster nobody asked to watch.
class OasisVideoPlayer extends StatefulWidget {
  final String url;

  /// Starts playing as soon as the first frame is ready, for the rare caller
  /// that knows the video is the reason the screen was opened.
  final bool autoPlay;

  /// Used only until the real first frame is decoded, and only to hold the
  /// right shape. The frame replaces it.
  final double aspectRatio;

  /// Rounds the player. Set to zero where the video is already inside a
  /// clipped container, so two radii do not fight.
  final BorderRadius? borderRadius;

  /// Whether to open the stream on mount so the poster can be the video's own
  /// first frame.
  ///
  /// True for a player that is the point of the space it occupies. **False
  /// where several of these can be on screen at once**: the units list on a
  /// property is built in one pass, so a ten-flat building would open ten
  /// streams the moment it loaded, most of them for units nobody scrolls to.
  /// With it off the poster is the same still block a photo waits behind,
  /// and the frame is fetched on the tap that asks for it.
  final bool preparePoster;

  const OasisVideoPlayer({
    super.key,
    required this.url,
    this.autoPlay = false,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
    this.preparePoster = true,
  });

  @override
  State<OasisVideoPlayer> createState() => _OasisVideoPlayerState();
}

class _OasisVideoPlayerState extends State<OasisVideoPlayer> {
  VideoPlayerController? _videoController;

  /// Built on the first tap, not on mount. Its existence is what separates
  /// "showing the first frame" from "playing".
  ChewieController? _chewieController;

  String? _error;

  /// Whether a stream is being opened right now, so a tap cannot start a
  /// second attempt on top of the first.
  bool _isPreparing = false;

  /// Whether somebody has actually asked to watch this.
  ///
  /// It is what decides whether a failure is worth showing. Preparing the
  /// poster is speculative work the viewer never requested, if it fails,
  /// they get the same quiet block and play button as a video that has not
  /// been fetched yet, and the tap retries. A failure *after* they tapped is
  /// theirs to know about, and gets the error panel.
  bool _wasRequested = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) _wasRequested = true;
    if (widget.preparePoster || widget.autoPlay) _prepare();
  }

  @override
  void didUpdateWidget(OasisVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Replacing the video (the landlord's "Replace" action) must tear down the
    // old controllers rather than leaking them, and drop back to the poster so
    // the new clip is not played at somebody who never asked to watch.
    if (oldWidget.url != widget.url) {
      _disposeControllers();
      setState(() {
        _error = null;
        _isPreparing = false;
        _wasRequested = widget.autoPlay;
      });
      if (widget.preparePoster || widget.autoPlay) _prepare();
    }
  }

  /// Opens the stream far enough to show its first frame.
  Future<void> _prepare() async {
    if (_isPreparing || _videoController != null) return;

    final uri = Uri.tryParse(widget.url);
    if (uri == null || !uri.hasScheme) {
      // The one failure worth showing unasked: a malformed link will not come
      // good on a retry, so offering a play button would be a dead end.
      setState(() => _error = 'This video link is not valid.');
      return;
    }
    setState(() => _isPreparing = true);

    try {
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _isPreparing = false;
      });
      if (_wasRequested) _play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        // Quiet unless they asked. A walkthrough that would not open on a bad
        // connection should leave a listing looking like a listing, with a
        // play button that tries again, not turn it into a black error panel
        // for a video nobody had reached for yet.
        if (_wasRequested) _error = 'This video could not be played.';
      });
    }
  }

  /// Hands the prepared controller to Chewie and starts it.
  ///
  /// On a player whose poster was never prepared, or whose preparation
  /// quietly failed: this is also what opens the stream. [_prepare] plays on
  /// arrival, so one tap still does one thing, and a tap after a silent
  /// failure is the retry.
  void _play() {
    _wasRequested = true;
    final controller = _videoController;
    if (controller == null) {
      _prepare();
      return;
    }
    if (_chewieController != null) return;

    setState(() {
      _chewieController = ChewieController(
        videoPlayerController: controller,
        // Reaching here means somebody asked for the video. Making them tap
        // play a second time once the controls appear is a small insult.
        autoPlay: true,
        looping: false,
        aspectRatio: controller.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppTheme.actionColor,
          handleColor: AppTheme.actionColor,
          bufferedColor: Colors.white54,
          backgroundColor: Colors.white24,
        ),
        // Its own first frame, so the instant before playback starts is the
        // same picture as the instant after.
        placeholder: _VideoFrame(controller: controller),
        errorBuilder: (_, message) => _ErrorPanel(message: message),
      );
    });
  }

  void _disposeControllers() {
    // Chewie must go first: it holds a reference to the video controller.
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    return ClipRRect(
      borderRadius: widget.borderRadius ?? AppTheme.cornerMd,
      child: AspectRatio(
        // The video's own shape once known, so a portrait walkthrough is not
        // letterboxed into a 16:9 box it was never shot for.
        aspectRatio: controller?.value.aspectRatio ?? widget.aspectRatio,
        child: _buildContent(controller),
      ),
    );
  }

  Widget _buildContent(VideoPlayerController? controller) {
    if (_error != null) return _ErrorPanel(message: _error!);
    if (_chewieController != null) {
      return Chewie(controller: _chewieController!);
    }

    // No frame yet: either the stream is still opening, or this player was
    // told not to open one until asked. Both show the same still block: a
    // wheel would be the only moving thing on an otherwise settled screen,
    // and both keep the play control, because a video with no visible way to
    // start it is just a grey rectangle.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (controller == null)
          const _PreparingBlock()
        else
          _VideoFrame(controller: controller),
        // A wash under the play button, so a white circle stays legible over
        // a frame that opens on a bright sky.
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: Color(0x47000000))),
        ),
        Center(
          child: GestureDetector(
            // Dead only while an attempt is actually in flight, so a second
            // tap cannot stack a second one on top of it.
            onTap: _isPreparing ? null : _play,
            behavior: HitTestBehavior.opaque,
            child: const OasisVideoPlayButton(),
          ),
        ),
        const Positioned(left: 12, bottom: 12, child: OasisVideoTourBadge()),
      ],
    );
  }
}

/// The video's current frame: frame zero, for a controller that has been
/// initialised and never played.
///
/// `VideoPlayer` stretches to whatever box it is given, so it is sized to the
/// video's own dimensions inside a `FittedBox` and then covered. Handed
/// straight to a hero it would otherwise squash a portrait clip into a
/// landscape header.
class _VideoFrame extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoFrame({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    return FittedBox(
      // Always cover. Every place this is used (the header, the inline
      // poster, Chewie's own placeholder) is a box the frame has to fill;
      // a contained frame would sit in it with bars, which is the letterboxing
      // the photos were just fixed for.
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width == 0 ? 16 : size.width,
        height: size.height == 0 ? 9 : size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

/// A video's first frame, with no player attached.
///
/// For the places that want to *show* a walkthrough without being able to
/// play it inline: the photo header, where a live player would fight the
/// pager for the swipe and put its controls where the page counter goes.
/// Tapping is the caller's business; this only draws the frame.
class OasisVideoPoster extends StatefulWidget {
  final String url;

  /// Painted over the frame: a play button, a badge. The frame itself is
  /// dimmed under it.
  final Widget? overlay;

  const OasisVideoPoster({super.key, required this.url, this.overlay});

  @override
  State<OasisVideoPoster> createState() => _OasisVideoPosterState();
}

class _OasisVideoPosterState extends State<OasisVideoPoster> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || !uri.hasScheme) return;
    try {
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      // A walkthrough that will not open is not worth an error state on a
      // photo header. The block and the play badge stay; tapping through to
      // the viewer is where the failure gets explained.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (controller == null)
          const _PreparingBlock()
        else
          _VideoFrame(controller: controller),
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: Color(0x4D000000))),
        ),
        if (widget.overlay != null) widget.overlay!,
      ],
    );
  }
}

/// What stands in for a frame that has not decoded yet. Deliberately the same
/// still, tinted block a photo waits behind, so a gallery of photos and one
/// video all settle the same way.
class _PreparingBlock extends StatelessWidget {
  const _PreparingBlock();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTheme.isDarkMode(context)
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFEDE8E2),
  );
}

/// The circle that says "this is a video". Shared so the header, the inline
/// player and the full-screen viewer all invite the same tap.
class OasisVideoPlayButton extends StatelessWidget {
  final double size;

  const OasisVideoPlayButton({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.42),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    // Nudged right: a triangle centred on its bounding box reads as sitting
    // left of centre inside a circle.
    child: Padding(
      padding: EdgeInsets.only(left: size * 0.06),
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: size * 0.53,
      ),
    ),
  );
}

/// "Video tour", bottom-left. A guest scanning a listing should be able to
/// tell at a glance that this block is a walkthrough and not another photo.
class OasisVideoTourBadge extends StatelessWidget {
  const OasisVideoTourBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(30),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_circle_outline_rounded, size: 13, color: Colors.white),
        SizedBox(width: 6),
        Text(
          'Video tour',
          style: TextStyle(
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

class _ErrorPanel extends StatelessWidget {
  final String message;

  const _ErrorPanel({required this.message});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black87,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: Colors.white70,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
