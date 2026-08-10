import 'dart:async';
import 'package:flutter/material.dart';
import '../services/live_service.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import 'my_live_page.dart';
import 'viewer_live_page.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});
  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage>
    with SingleTickerProviderStateMixin {
  final LiveService _liveService = LiveService();
  final WebSocketService _ws = WebSocketService();
  late TabController _tabCtrl;

  List<dynamic> _activeLives = [];
  List<dynamic> _filteredLives = [];
  bool _isLoading = true;
  String _selectedCat = 'All';
  int _totalViewers = 0;

  StreamSubscription? _liveStartSub;
  StreamSubscription? _liveEndSub;
  StreamSubscription? _viewerSub;

  final List<Map<String, dynamic>> _categories = [
    {'name': 'All', 'icon': Icons.all_inclusive},
    {'name': 'Music', 'icon': Icons.music_note},
    {'name': 'Gaming', 'icon': Icons.sports_esports},
    {'name': 'Talk', 'icon': Icons.record_voice_over},
    {'name': 'Education', 'icon': Icons.school},
    {'name': 'Fitness', 'icon': Icons.fitness_center},
    {'name': 'Art', 'icon': Icons.palette},
    {'name': 'Cooking', 'icon': Icons.restaurant},
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadLives();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _liveStartSub = _ws.onLiveStart.listen((data) {
      if (!mounted) return;
      setState(() {
        _activeLives.insert(0, data);
        _applyFilter();
      });
    });
    _liveEndSub = _ws.onLiveEnd.listen((data) {
      if (!mounted) return;
      final id = data['stream_id'];
      setState(() {
        _activeLives.removeWhere((l) => l['id'] == id);
        _applyFilter();
      });
    });
    _viewerSub = _ws.onLiveViewer.listen((data) {
      if (!mounted) return;
      final id = data['stream_id'];
      setState(() {
        for (final live in _activeLives) {
          if (live['id'] == id) {
            live['viewer_count'] = (live['viewer_count'] ?? 0) + 1;
            break;
          }
        }
        _totalViewers = _activeLives.fold(
          0,
          (s, l) => s + ((l['viewer_count'] ?? 0) as int),
        );
      });
    });
  }

  Future<void> _loadLives() async {
    setState(() => _isLoading = true);
    try {
      final lives = await _liveService.getActiveLives();
      if (mounted) {
        setState(() {
          _activeLives = lives;
          _totalViewers = lives.fold(
            0,
            (s, l) => s + ((l['viewer_count'] ?? 0) as int),
          );
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    if (_selectedCat == 'All') {
      _filteredLives = List.from(_activeLives);
    } else {
      _filteredLives = _activeLives
          .where(
            (l) =>
                (l['title']?.toString().toLowerCase() ?? '').contains(
                  _selectedCat.toLowerCase(),
                ) ||
                (l['category']?.toString() ?? '') == _selectedCat,
          )
          .toList();
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _liveStartSub?.cancel();
    _liveEndSub?.cancel();
    _viewerSub?.cancel();
    super.dispose();
  }

  void _goLive() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyLivePage()),
    ).then((_) => _loadLives());
  }

  void _watchLive(Map<String, dynamic> stream) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ViewerLivePage(
          streamId: stream['id'],
          hostName:
              stream['user']?['full_name'] ??
              stream['user']?['username'] ??
              'Host',
          hostAvatar: stream['user']?['profile_image'] ?? '',
          title: stream['title'] ?? 'Live Stream',
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.live_tv, color: Colors.red, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Live',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            const SizedBox(width: 8),
            if (_totalViewers > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_fmt(_totalViewers)} watching',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadLives,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.red,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Live Now'),
            Tab(text: 'My Streams'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_liveNowTab(), _myStreamsTab()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goLive,
        backgroundColor: Colors.red,
        icon: const Icon(Icons.videocam, color: Colors.white),
        label: const Text(
          'Go Live',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _liveNowTab() {
    return Column(
      children: [
        // Category filter
        Container(
          height: 50,
          color: Colors.black,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final sel = _selectedCat == cat['name'];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCat = cat['name'] as String;
                    _applyFilter();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: sel ? Colors.red : Colors.grey[850],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? Colors.red : Colors.grey[700]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat['icon'] as IconData,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        cat['name'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.red),
                )
              : _filteredLives.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  color: Colors.red,
                  backgroundColor: Colors.grey[900],
                  onRefresh: _loadLives,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.7,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: _filteredLives.length,
                    itemBuilder: (_, i) => _liveCard(_filteredLives[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _myStreamsTab() {
    final user = AuthService().currentUser;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.red, Colors.redAccent],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(Icons.live_tv, color: Colors.white, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Hello, ${user?['full_name'] ?? user?['username'] ?? 'Creator'}!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Start streaming to your audience',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _goLive,
                      icon: const Icon(Icons.videocam),
                      label: const Text(
                        'Go Live Now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Tips
            _tipCard(
              Icons.people,
              'Engage your audience',
              'Respond to comments and gifts in real-time',
            ),
            const SizedBox(height: 10),
            _tipCard(
              Icons.schedule,
              'Schedule streams',
              'Let followers know when you\'ll be live',
            ),
            const SizedBox(height: 10),
            _tipCard(
              Icons.card_giftcard,
              'Receive gifts',
              'Viewers can send you virtual gifts',
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipCard(IconData icon, String title, String desc) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.red, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.live_tv, size: 80, color: Colors.grey),
        const SizedBox(height: 16),
        Text(
          'No $_selectedCat live streams right now',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          'Be the first to go live!',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _goLive,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          icon: const Icon(Icons.videocam, color: Colors.white),
          label: const Text(
            'Go Live',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  Widget _liveCard(Map<String, dynamic> stream) {
    final user = stream['user'] ?? {};
    final viewers = (stream['viewer_count'] ?? 0) as int;
    final pic = user['profile_image']?.toString() ?? '';
    final thumb = stream['thumbnail_url']?.toString() ?? '';

    return GestureDetector(
      onTap: () => _watchLive(stream),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.grey[900],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: thumb.isNotEmpty
                  ? Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultThumb(),
                    )
                  : _defaultThumb(),
            ),
            // Gradient
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            // LIVE badge
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.white, size: 8),
                    SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Viewer count
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.remove_red_eye,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(viewers),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom info
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.deepPurple,
                    backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                    child: pic.isEmpty
                        ? Text(
                            (user['username'] ?? 'U')[0]
                                .toString()
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user['username']?.toString() ?? 'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          stream['title']?.toString() ?? 'Live Stream',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultThumb() => Container(
    color: Colors.grey[850],
    child: const Center(
      child: Icon(Icons.live_tv, color: Colors.grey, size: 48),
    ),
  );
}
