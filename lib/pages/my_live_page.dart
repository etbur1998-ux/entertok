import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/live_service.dart';
import '../services/websocket_service.dart';

class MyLivePage extends StatefulWidget {
  const MyLivePage({super.key});

  @override
  State<MyLivePage> createState() => _MyLivePageState();
}

class _MyLivePageState extends State<MyLivePage> {
  final LiveService _liveService = LiveService();
  final WebSocketService _ws = WebSocketService();
  final TextEditingController _titleController = TextEditingController(
    text: 'My Live Stream',
  );
  final TextEditingController _commentController = TextEditingController();

  bool _isLive = false;
  bool _isStarting = false;
  int _streamId = 0;
  int _viewerCount = 0;
  int _likeCount = 0; // updated via WebSocket gift events
  final List<Map<String, dynamic>> _comments = [];
  StreamSubscription? _commentSub;
  StreamSubscription? _viewerSub;
  Timer? _durationTimer;
  int _durationSeconds = 0;

  // Camera
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _rendersReady = false;
  bool _micOn = true;
  bool _camOn = true;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _subscribeToEvents();
  }

  Future<void> _initCamera() async {
    await _localRenderer.initialize();
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      });
      _localRenderer.srcObject = _localStream;
    } catch (_) {}
    if (mounted) setState(() => _rendersReady = true);
  }

  void _subscribeToEvents() {
    _commentSub = _ws.onLiveComment.listen((data) {
      if (data['stream_id'] == _streamId) {
        setState(() => _comments.insert(0, data));
        // Count gifts as likes
        if (data['comment_type'] == 'gift') {
          setState(() => _likeCount++);
        }
      }
    });
    _viewerSub = _ws.onLiveViewer.listen((data) {
      if (data['stream_id'] == _streamId) {
        setState(() => _viewerCount = (_viewerCount + 1).clamp(0, 999999));
      }
    });
  }

  Future<void> _startLive() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a title')));
      return;
    }
    setState(() => _isStarting = true);
    try {
      final result = await _liveService.startLive(
        title: _titleController.text.trim(),
      );
      final stream = result['stream'] as Map<String, dynamic>;
      setState(() {
        _streamId = stream['id'];
        _isLive = true;
        _isStarting = false;
      });
      _startDurationTimer();
    } catch (e) {
      setState(() => _isStarting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start live: $e')));
      }
    }
  }

  Future<void> _endLive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End Live Stream?'),
        content: const Text('Are you sure you want to end your live stream?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'End Live',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _liveService.endLive(_streamId);
      _durationTimer?.cancel();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error ending live: $e')));
      }
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _durationSeconds++);
    });
  }

  String get _durationText {
    final h = _durationSeconds ~/ 3600;
    final m = (_durationSeconds % 3600) ~/ 60;
    final s = _durationSeconds % 60;
    if (h > 0)
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _commentSub?.cancel();
    _viewerSub?.cancel();
    _durationTimer?.cancel();
    _localStream?.dispose();
    _localRenderer.dispose();
    _titleController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLive ? _buildLiveView() : _buildSetupView(),
    );
  }

  Widget _buildSetupView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                const Text(
                  'Go Live',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 32),
            // Real camera preview
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _rendersReady && _localStream != null
                    ? RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, color: Colors.grey, size: 48),
                            SizedBox(height: 8),
                            Text(
                              'Starting camera...',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Stream Title',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'What are you streaming about?',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isStarting ? null : _startLive,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                icon: _isStarting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.videocam, color: Colors.white),
                label: Text(
                  _isStarting ? 'Starting...' : 'Start Live Stream',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveView() {
    return SafeArea(
      child: Stack(
        children: [
          // Real camera background
          _rendersReady && _localStream != null && _camOn
              ? RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : Container(
                  color: Colors.grey[900],
                  child: const Center(
                    child: Icon(
                      Icons.videocam_off,
                      color: Colors.grey,
                      size: 80,
                    ),
                  ),
                ),
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  // LIVE badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _durationText,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  // Viewer count
                  Row(
                    children: [
                      const Icon(
                        Icons.remove_red_eye,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_viewerCount',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // End button
                  GestureDetector(
                    onTap: _endLive,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'End',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Comments overlay
          Positioned(
            bottom: 80,
            left: 0,
            right: 80,
            height: 250,
            child: ListView.builder(
              reverse: true,
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                final comment = _comments[index];
                return _buildCommentBubble(comment);
              },
            ),
          ),
          // Like count + controls
          Positioned(
            bottom: 80,
            right: 16,
            child: Column(
              children: [
                const Icon(Icons.favorite, color: Colors.red, size: 32),
                Text(
                  '$_likeCount',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                // Mic toggle
                GestureDetector(
                  onTap: () {
                    setState(() => _micOn = !_micOn);
                    _localStream?.getAudioTracks().forEach(
                      (t) => t.enabled = _micOn,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _micOn ? Colors.black54 : Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _micOn ? Icons.mic : Icons.mic_off,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Cam toggle
                GestureDetector(
                  onTap: () {
                    setState(() => _camOn = !_camOn);
                    _localStream?.getVideoTracks().forEach(
                      (t) => t.enabled = _camOn,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _camOn ? Colors.black54 : Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _camOn ? Icons.videocam : Icons.videocam_off,
                      color: Colors.white,
                      size: 20,
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

  Widget _buildCommentBubble(Map<String, dynamic> comment) {
    final isGift = comment['comment_type'] == 'gift';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isGift
              ? Colors.amber.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isGift)
              const Icon(Icons.card_giftcard, color: Colors.amber, size: 16),
            if (isGift) const SizedBox(width: 4),
            Text(
              '${comment['username'] ?? 'User'}: ${comment['content'] ?? ''}',
              style: TextStyle(
                color: isGift ? Colors.amber : Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
