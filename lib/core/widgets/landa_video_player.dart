import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';

/// Inline network video player with Landa's terracotta controls.
///
/// Wraps `video_player` + `chewie` so callers get buffering, scrubbing,
/// fullscreen, and error handling without re-implementing them, and so
/// controller disposal happens in exactly one place.
class LandaVideoPlayer extends StatefulWidget {
  final String url;

  /// Shown behind the play button before the first frame decodes. Using the
  /// listing cover here avoids a black rectangle while the video loads.
  final String? thumbnailUrl;

  /// Start muted with no autoplay by default: a tour video that starts
  /// blasting audio while someone is browsing is hostile.
  final bool autoPlay;
  final double aspectRatio;

  const LandaVideoPlayer({
    super.key,
    required this.url,
    this.thumbnailUrl,
    this.autoPlay = false,
    this.aspectRatio = 16 / 9,
  });

  @override
  State<LandaVideoPlayer> createState() => _LandaVideoPlayerState();
}

class _LandaVideoPlayerState extends State<LandaVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  @override
  void didUpdateWidget(LandaVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Replacing the video (landlord "Replace" action) must tear down the old
    // controllers rather than leaking them.
    if (oldWidget.url != widget.url) {
      _disposeControllers();
      setState(() {
        _isInitializing = true;
        _error = null;
      });
      _initialise();
    }
  }

  Future<void> _initialise() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _isInitializing = false;
        _error = 'This video link is not valid.';
      });
      return;
    }

    try {
      final videoController = VideoPlayerController.networkUrl(uri);
      await videoController.initialize();
      if (!mounted) {
        await videoController.dispose();
        return;
      }

      setState(() {
        _videoController = videoController;
        _chewieController = ChewieController(
          videoPlayerController: videoController,
          autoPlay: widget.autoPlay,
          looping: false,
          aspectRatio: videoController.value.aspectRatio,
          materialProgressColors: ChewieProgressColors(
            playedColor: AppTheme.actionColor,
            handleColor: AppTheme.actionColor,
            bufferedColor: Colors.white54,
            backgroundColor: Colors.white24,
          ),
          placeholder: _thumbnail(),
          errorBuilder: (_, message) => _ErrorPanel(message: message),
        );
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = 'This video could not be played.';
      });
    }
  }

  Widget _thumbnail() {
    final url = widget.thumbnailUrl;
    if (url == null || url.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
  }

  void _disposeControllers() {
    // Chewie must go first — it holds a reference to the video controller.
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: _chewieController?.aspectRatio ?? widget.aspectRatio,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isInitializing) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _thumbnail(),
          Container(color: Colors.black26),
          const Center(
            child: SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    if (_error != null || _chewieController == null) {
      return _ErrorPanel(message: _error ?? 'This video could not be played.');
    }

    return Chewie(controller: _chewieController!);
  }
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
