import 'dart:async';
import 'package:flutter/material.dart';
import '../services/live_service.dart';
import '../services/websocket_service.dart';

class ViewerLivePage extends StatefulWidget {
  final int streamId;
  final String hostName;
  final String hostAvatar;
  final String title;

  const ViewerLivePage({
    super.key,
    required this.streamId,
    required this.hostName,
    required this.hostAvatar,
    required this.title,
  });

  @override
  State<ViewerLivePage> createState() => _ViewerLivePageState();
}

class _ViewerLivePageState extends State<ViewerLivePage> {
  final LiveService _liveService = LiveService();
  final WebSocketService _ws = WebSocketService();
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _comments = [];
  int _viewerCount = 0;
  bool _isStreamActive = true;
  StreamSubscription? _commentSub;
  StreamSubscription? _viewerSub;
  StreamSubscription? _liveEndSub;

  // Gift options
  final List<Map<String, dynamic>> _gifts = [
    {'name': 'Rose', 'icon': '🌹', 'value': 1.0},
    {'name': 'Star', 'icon': '⭐', 'value': 5.0},
    {'name': 'Crown', 'icon': '👑', 'value': 10.0},
    {'name': 'Diamond', 'icon': '💎', 'value': 50.0},
    {'name': 'Rocket', 'icon': '🚀', 'value': 100.0},
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialComments();
    _joinStream();
    _subscribeToEvents();
  }

  Future<void> _loadInitialComments() async {
    try {
      final comments = await _liveService.getLiveComments(widget.streamId);
      if (mounted) {
        setState(() => _comments.addAll(List<Map<String, dynamic>>.from(comments.reversed)));
      }
    } catch (_) {}
  }

  void _joinStream() {
    _ws.joinLiveStream(widget.streamId);
  }

  void _subscribeToEvents() {
    _commentSub = _ws.onLiveComment.listen((data) {
      if (data['stream_id'] == widget.streamId) {
        setState(() => _comments.add(data));
        _scrollToBottom();
      }
    });
    _viewerSub = _ws.onLiveViewer.listen((data) {
      if (data['stream_id'] == widget.streamId) {
        setState(() => _viewerCount++);
      }
    });
    _liveEndSub = _ws.onLiveEnd.listen((data) {
      if (data['stream_id'] == widget.streamId) {
        setState(() => _isStreamActive = false);
        _showStreamEndedDialog();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    _ws.sendLiveComment(streamId: widget.streamId, content: text);
    _commentController.clear();
  }

  void _showGiftSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Send a Gift', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _gifts.map((gift) => GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _sendGift(gift);
                },
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(gift['icon'], style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(gift['name'], style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    Text('\$${gift['value']}', style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _sendGift(Map<String, dynamic> gift) {
    _ws.sendLiveComment(
      streamId: widget.streamId,
      content: 'sent a ${gift['name']}',
      commentType: 'gift',
      giftValue: gift['value'],
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${gift['icon']} ${gift['name']} sent!'),
        backgroundColor: Colors.amber[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showStreamEndedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Stream Ended'),
        content: const Text('The live stream has ended.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ws.leaveLiveStream(widget.streamId);
    _commentSub?.cancel();
    _viewerSub?.cancel();
    _liveEndSub?.cancel();
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Stream background
            Container(
              color: Colors.grey[900],
              child: const Center(
                child: Icon(Icons.live_tv, color: Colors.grey, size: 80),
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
                    colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    // Host info
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.deepPurple,
                      backgroundImage: widget.hostAvatar.isNotEmpty
                          ? NetworkImage(widget.hostAvatar)
                          : null,
                      child: widget.hostAvatar.isEmpty
                          ? Text(widget.hostName[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white))
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.hostName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(widget.title,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    // LIVE badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isStreamActive ? Colors.red : Colors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _isStreamActive ? 'LIVE' : 'ENDED',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Viewer count
                    Row(
                      children: [
                        const Icon(Icons.remove_red_eye, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text('$_viewerCount', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Close button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            // Comments list
            Positioned(
              bottom: 70,
              left: 0,
              right: 80,
              height: 280,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  final comment = _comments[index];
                  return _buildCommentItem(comment);
                },
              ),
            ),
            // Right side actions
            Positioned(
              bottom: 80,
              right: 12,
              child: Column(
                children: [
                  _buildActionButton(Icons.favorite, Colors.red, () {}),
                  const SizedBox(height: 16),
                  _buildActionButton(Icons.card_giftcard, Colors.amber, _showGiftSheet),
                  const SizedBox(height: 16),
                  _buildActionButton(Icons.share, Colors.white, () {}),
                ],
              ),
            ),
            // Bottom input
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Say something...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.15),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _sendComment(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sendComment,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Colors.deepPurple,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final isGift = comment['comment_type'] == 'gift';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.deepPurple,
            backgroundImage: comment['avatar'] != null && comment['avatar'].toString().isNotEmpty
                ? NetworkImage(comment['avatar'])
                : null,
            child: comment['avatar'] == null || comment['avatar'].toString().isEmpty
                ? Text((comment['username'] ?? 'U')[0].toString().toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10))
                : null,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isGift
                    ? Colors.amber.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${comment['username'] ?? 'User'} ',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    TextSpan(
                      text: comment['content'] ?? '',
                      style: TextStyle(
                        color: isGift ? Colors.amber : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}
