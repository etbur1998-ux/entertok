import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/video_preload_manager.dart';

/// Full-screen TikTok-style video player using MediaKit.
///
/// Performance design:
/// - Player + VideoController created together in initState (correct MediaKit order)
/// - 64 MB buffer for smooth HD playback
/// - Hardware acceleration enabled
/// - AutomaticKeepAlive keeps the widget alive — swipe back = instant resume
/// - RepaintBoundary wraps the Video widget so overlays don't cause video repaints
/// - Looping: auto-replay on complete instead of calling onVideoCompleted
class TikTokVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final int index;
  final bool isActive;
  final VoidCallback? onVideoCompleted;

  const TikTokVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.index,
    required this.isActive,
    this.onVideoCompleted,
  });

  @override
  State<TikTokVideoPlayer> createState() => _TikTokVideoPlayerState();
}

class _TikTokVideoPlayerState extends State<TikTokVideoPlayer>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;

  bool _ready = false;
  bool _hasError = false;
  bool _showIcon = false;
  bool _buffering = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Step 1: Player
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024, // 64 MB buffer
        logLevel: MPVLogLevel.error, // suppress noisy logs
      ),
    );

    // Step 2: VideoController (must come before open())
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    // Step 3: open()
    _open();
  }

  Future<void> _open() async {
    final url = VideoPreloadManager().resolveUrl(widget.videoUrl);
    if (url.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }
    try {
      // Listen to buffering state BEFORE opening
      _player.stream.buffering.listen((b) {
        if (mounted && _buffering != b) {
          setState(() => _buffering = b);
        }
      });

      await _player.open(Media(url), play: false);
      _player.setPlaylistMode(PlaylistMode.single);

      _player.stream.completed.listen((done) {
        if (!done || !mounted) return;
        widget.onVideoCompleted?.call();
        // Loop: seek to start and keep playing
        _player.seek(Duration.zero).then((_) {
          if (widget.isActive && mounted) _player.play();
        });
      });

      if (mounted) {
        setState(() => _ready = true);
        if (widget.isActive) _play();
      }
    } catch (e) {
      debugPrint('VideoPlayer open error [$url]: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _play() {
    _player.setVolume(100);
    _player.play();
  }

  void _pause() => _player.pause();

  void _togglePlay() async {
    _player.state.playing ? _pause() : _play();
    setState(() => _showIcon = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _showIcon = false);
  }

  @override
  void didUpdateWidget(TikTokVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive) {
      widget.isActive ? _play() : _pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pause();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pause();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_hasError) return _errorWidget();
    if (!_ready) return _loadingWidget();

    return GestureDetector(
      onTap: _togglePlay,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // RepaintBoundary so overlay changes don't repaint the video
          RepaintBoundary(
            child: Video(
              controller: _controller,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
          ),

          // Buffering spinner (shown only while buffering)
          if (_buffering)
            const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2.5,
                ),
              ),
            ),

          // Tap play/pause icon
          if (_showIcon)
            Center(
              child: AnimatedOpacity(
                opacity: _showIcon ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _player.state.playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _loadingWidget() => Container(
    color: Colors.black,
    child: const Center(
      child: SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2),
      ),
    ),
  );

  Widget _errorWidget() => Container(
    color: const Color(0xFF0A0A0A),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white24,
            size: 56,
          ),
          const SizedBox(height: 14),
          const Text(
            'Video unavailable',
            style: TextStyle(color: Colors.white30, fontSize: 14),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () {
              setState(() {
                _hasError = false;
                _ready = false;
              });
              _open();
            },
            child: const Text(
              'Tap to retry',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        ],
      ),
    ),
  );
}
