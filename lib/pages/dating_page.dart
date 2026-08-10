import 'dart:async';
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/websocket_service.dart';
import 'message_page.dart';
import 'random_video_page.dart';

class DatingPage extends StatefulWidget {
  const DatingPage({super.key});
  @override
  State<DatingPage> createState() => _DatingPageState();
}

class _DatingPageState extends State<DatingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final UserService _userService = UserService();
  final WebSocketService _ws = WebSocketService();

  // Data from DB
  List<dynamic> _profiles = [];
  List<dynamic> _likes = [];
  List<dynamic> _matches = [];
  // live stream user IDs  {userId: streamId}
  Map<int, int> _liveMap = {};
  bool _isLoading = true;

  // Swipe state (kept for future swipe card mode)
  int _currentIndex = 0;

  // Filter prefs
  double _minAge = 18;
  double _maxAge = 40;
  double _maxDistance = 50;
  String _genderPref = 'Opposite';

  // Online tracking
  final Map<int, bool> _onlineMap = {};
  StreamSubscription? _onlineSub;
  StreamSubscription? _followSub;
  StreamSubscription? _liveSub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _loadData();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _onlineSub = _ws.onOnlineStatus.listen((data) {
      if (!mounted) return;
      final uid = data['user_id'] as int?;
      if (uid != null)
        setState(() => _onlineMap[uid] = data['is_online'] == true);
    });
    _followSub = _ws.onFollow.listen((_) {
      if (mounted) _loadMatches();
    });
    _liveSub = _ws.onLiveStart.listen((data) {
      if (!mounted) return;
      final uid = (data['user_id'] as num?)?.toInt();
      final sid = (data['stream_id'] as num?)?.toInt();
      if (uid != null && sid != null) setState(() => _liveMap[uid] = sid);
    });
    _ws.onLiveEnd.listen((data) {
      if (!mounted) return;
      final uid = (data['user_id'] as num?)?.toInt();
      if (uid != null) setState(() => _liveMap.remove(uid));
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiClient();
      final suggestionsResp = await api.get(
        '/dating/suggestions',
        queryParams: {'limit': '60'},
      );
      final likesResp = await api.get('/dating/likes');
      // Load active live streams
      _loadLiveStreams();
      if (mounted) {
        setState(() {
          _profiles = suggestionsResp['users'] ?? [];
          _likes = likesResp['likes'] ?? [];
          _currentIndex = 0;
          _isLoading = false;
        });
      }
      await _loadMatches();
    } catch (_) {
      try {
        final profiles = await _userService.getSuggestions(limit: 60);
        if (mounted) {
          setState(() {
            _profiles = profiles;
            _likes = profiles.take(8).toList();
            _currentIndex = 0;
            _isLoading = false;
          });
        }
      } catch (__) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadLiveStreams() async {
    try {
      final resp = await ApiClient().get('/live');
      final streams = resp['streams'] ?? resp['lives'] ?? [];
      final map = <int, int>{};
      for (final s in streams) {
        final uid = (s['user_id'] as num?)?.toInt();
        final sid = (s['id'] as num?)?.toInt();
        if (uid != null && sid != null) map[uid] = sid;
      }
      if (mounted) setState(() => _liveMap = map);
    } catch (_) {}
  }

  Future<void> _loadMatches() async {
    try {
      final resp = await ApiClient().get('/dating/matches');
      if (mounted) setState(() => _matches = resp['matches'] ?? []);
    } catch (_) {
      try {
        final user = AuthService().currentUser;
        if (user != null) {
          final following = await _userService.getFollowing(user['id']);
          final followers = await _userService.getFollowers(user['id']);
          final followerIds = followers.map((f) => f['id']).toSet();
          if (mounted) {
            setState(
              () => _matches = following
                  .where((f) => followerIds.contains(f['id']))
                  .toList(),
            );
          }
        }
      } catch (__) {}
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _onlineSub?.cancel();
    _followSub?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  // ─── Swipe Actions ────────────────────────────────────────────────────────

  Future<void> _swipeRight() async {
    if (_currentIndex >= _profiles.length) return;
    final user = _profiles[_currentIndex];
    setState(() => _currentIndex++);
    try {
      final result = await ApiClient().post('/dating/like/${user['id']}');
      if (result['is_match'] == true) {
        _showMatchAnimation(user);
        await _loadMatches();
      }
    } catch (_) {
      try {
        await _userService.followUser(user['id']);
      } catch (_) {}
    }
  }

  Future<void> _swipeLeft() async {
    if (_currentIndex >= _profiles.length) return;
    final user = _profiles[_currentIndex];
    setState(() => _currentIndex++);
    try {
      await ApiClient().post('/dating/dislike/${user['id']}');
    } catch (_) {}
  }

  Future<void> _superLike() async {
    if (_currentIndex >= _profiles.length) return;
    final user = _profiles[_currentIndex];
    setState(() => _currentIndex++);
    try {
      final result = await ApiClient().post('/dating/like/${user['id']}');
      if (result['is_match'] == true) {
        _showMatchAnimation(user);
        await _loadMatches();
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Super liked ${user['full_name'] ?? user['username']} ⭐',
          ),
          backgroundColor: Colors.amber[700],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showMatchAnimation(dynamic user) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _MatchDialog(
        user: user,
        onMessage: () {
          Navigator.pop(ctx);
          _openChat(user);
        },
        onContinue: () => Navigator.pop(ctx),
      ),
    );
  }

  void _openChat(dynamic user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          name:
              user['full_name']?.toString() ??
              user['username']?.toString() ??
              'User',
          avatar: Colors.pink,
          isOnline: _onlineMap[user['id'] as int?] ?? false,
          receiverId: user['id'] as int?,
          profileImage: user['profile_image']?.toString(),
        ),
      ),
    );
  }

  void _openLive(dynamic user) {
    final uid = (user['id'] as num?)?.toInt();
    if (uid == null || !_liveMap.containsKey(uid)) return;
    // Navigate to live viewer page
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${user['full_name'] ?? user['username']} is live!'),
      ),
    );
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';

  // ─── Gender helper ────────────────────────────────────────────────────────

  /// Returns gender icon/color for a profile card badge
  Color _genderColor(dynamic user) {
    final g = (user['gender'] ?? '').toString().toLowerCase();
    if (g == 'female') return Colors.pinkAccent;
    if (g == 'male') return Colors.blue;
    return Colors.deepPurple;
  }

  IconData _genderIcon(dynamic user) {
    final g = (user['gender'] ?? '').toString().toLowerCase();
    if (g == 'female') return Icons.female;
    if (g == 'male') return Icons.male;
    return Icons.person;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, color: Colors.pinkAccent, size: 22),
            SizedBox(width: 8),
            Text(
              'Dating',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.black),
            onPressed: _showPreferences,
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.favorite_outline, color: Colors.black),
                onPressed: () => _tabCtrl.animateTo(1),
              ),
              if (_likes.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${_likes.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 9),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.pinkAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.pinkAccent,
          tabs: [
            const Tab(icon: Icon(Icons.grid_view, size: 18), text: 'Discover'),
            Tab(
              icon: Badge(
                label: Text('${_likes.length}'),
                child: const Icon(Icons.favorite, size: 18),
              ),
              text: 'Likes',
            ),
            Tab(
              icon: Badge(
                label: Text('${_matches.length}'),
                child: const Icon(Icons.chat_bubble, size: 18),
              ),
              text: 'Matches',
            ),
            const Tab(
              icon: Icon(Icons.shuffle_rounded, size: 18),
              text: 'Random',
            ),
            const Tab(icon: Icon(Icons.person, size: 18), text: 'Profile'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.pinkAccent),
            )
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _discoverTab(),
                _likesTab(),
                _matchesTab(),
                const _RandomConnectTab(),
                _profileTab(),
              ],
            ),
    );
  }

  // ─── Discover Tab — photo grid ────────────────────────────────────────────

  Widget _discoverTab() {
    if (_profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No profiles found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Come back later for new matches',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${_profiles.length} people near you',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.pinkAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.filter_list,
                      color: Colors.pinkAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _genderPref,
                      style: const TextStyle(
                        color: Colors.pinkAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Grid of profiles
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _profiles.length,
            itemBuilder: (_, i) => _profileGridCard(_profiles[i]),
          ),
        ),
      ],
    );
  }

  Widget _profileGridCard(dynamic user) {
    final pic = user['profile_image']?.toString() ?? '';
    final fullName =
        user['full_name']?.toString() ?? user['username']?.toString() ?? 'User';
    final uid = (user['id'] as num?)?.toInt() ?? 0;
    final isOnline = _onlineMap[uid] ?? (user['is_online'] == true);
    final isLive = _liveMap.containsKey(uid);
    final gColor = _genderColor(user);
    final gIcon = _genderIcon(user);

    return GestureDetector(
      onTap: () => _openProfile(user),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo background
              pic.isNotEmpty
                  ? Image.network(
                      pic,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _colorBg(user),
                    )
                  : _colorBg(user),
              // Bottom gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
              // LIVE badge top-left
              if (isLive)
                Positioned(
                  top: 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: () => _openLive(user),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam, color: Colors.white, size: 12),
                          SizedBox(width: 3),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Online dot top-right
              if (isOnline && !isLive)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              // Gender badge top-right (when not online indicator)
              if (!isOnline)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: gColor.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(gIcon, color: Colors.white, size: 14),
                  ),
                ),
              // Name + action buttons at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          // Message button
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openChat(user),
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.message,
                                      color: Colors.white,
                                      size: 13,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'Message',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Call / Live button
                          GestureDetector(
                            onTap: isLive
                                ? () => _openLive(user)
                                : () => ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'User is not live right now',
                                          ),
                                        ),
                                      ),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isLive ? Colors.red : Colors.white24,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                isLive ? Icons.videocam : Icons.call,
                                color: Colors.white,
                                size: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorBg(dynamic user) {
    final colors = [
      Colors.pink,
      Colors.purple,
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.indigo,
      Colors.red,
      Colors.cyan,
    ];
    final idx = ((user['id'] ?? 0) as int) % colors.length;
    return Container(
      color: colors[idx],
      child: Center(
        child: Text(
          (user['username'] ?? 'U')[0].toString().toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 80,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _openProfile(dynamic user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProfileDetailSheet(
        user: user,
        isOnline: _onlineMap[(user['id'] as num?)?.toInt()] ?? false,
        isLive: _liveMap.containsKey((user['id'] as num?)?.toInt()),
        onLike: () {
          Navigator.pop(context);
          _swipeRight();
        },
        onMessage: () {
          Navigator.pop(context);
          _openChat(user);
        },
        onCall: () {
          Navigator.pop(context);
          _openLive(user);
        },
      ),
    );
  }

  // ─── Likes Tab ────────────────────────────────────────────────────────────

  Widget _likesTab() {
    if (_likes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite_border, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No likes yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Keep swiping to get matches!',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '${_likes.length} people liked you',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                'Like back to match',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.72,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _likes.length,
            itemBuilder: (_, i) => _likeCard(_likes[i]),
          ),
        ),
      ],
    );
  }

  Widget _likeCard(dynamic user) {
    final pic = user['profile_image']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final fullName = user['full_name']?.toString() ?? username;
    final uid = (user['id'] as num?)?.toInt() ?? 0;
    final isOnline = _onlineMap[uid] ?? (user['is_online'] == true);
    final isLive = _liveMap.containsKey(uid);

    return GestureDetector(
      onTap: () => _openProfile(user),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              pic.isNotEmpty
                  ? Image.network(
                      pic,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _colorBg(user),
                    )
                  : _colorBg(user),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
              if (isLive)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else if (isOnline)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _userService.followUser(user['id']);
                              _showMatchAnimation(user);
                            },
                            child: Container(
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.pinkAccent,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Center(
                                child: Text(
                                  'Like Back',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        GestureDetector(
                          onTap: () => _openChat(user),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.deepPurple,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.message,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                        if (isLive) ...[
                          const SizedBox(width: 5),
                          GestureDetector(
                            onTap: () => _openLive(user),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Icon(
                                Icons.videocam,
                                color: Colors.white,
                                size: 15,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Matches Tab ──────────────────────────────────────────────────────────

  Widget _matchesTab() {
    if (_matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💝', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 16),
            const Text(
              'No matches yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Swipe right to find your match!',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _tabCtrl.animateTo(0),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Start Discovering'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${_matches.length} Matches 💝',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _matches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _matchTile(_matches[i]),
          ),
        ),
      ],
    );
  }

  Widget _matchTile(dynamic user) {
    final pic = user['profile_image']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final fullName = user['full_name']?.toString() ?? username;
    final uid = (user['id'] as num?)?.toInt() ?? 0;
    final isOnline = _onlineMap[uid] ?? (user['is_online'] == true);
    final isLive = _liveMap.containsKey(uid);
    final gColor = _genderColor(user);
    final gIcon = _genderIcon(user);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.pinkAccent.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: gColor,
                backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                child: pic.isEmpty
                    ? Text(
                        username.isNotEmpty ? username[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                        ),
                      )
                    : null,
              ),
              if (isLive)
                Positioned(
                  bottom: 0,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else if (isOnline)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Icon(gIcon, color: gColor, size: 16),
                  ],
                ),
                Text(
                  '@$username',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                if (isLive)
                  const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.red, size: 8),
                      SizedBox(width: 4),
                      Text(
                        'Live now',
                        style: TextStyle(color: Colors.red, fontSize: 11),
                      ),
                    ],
                  )
                else if (isOnline)
                  const Text(
                    '• Online now',
                    style: TextStyle(color: Colors.green, fontSize: 11),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              _matchActionBtn(
                Icons.favorite_outline,
                Colors.pinkAccent,
                () => _openProfile(user),
              ),
              const SizedBox(width: 6),
              _matchActionBtn(
                Icons.message_outlined,
                Colors.deepPurple,
                () => _openChat(user),
              ),
              const SizedBox(width: 6),
              _matchActionBtn(
                isLive ? Icons.videocam : Icons.call,
                isLive ? Colors.red : Colors.blue,
                () => isLive
                    ? _openLive(user)
                    : ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Call feature coming soon'),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _matchActionBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      );

  // ─── Profile Tab ──────────────────────────────────────────────────────────

  Widget _profileTab() {
    final user = AuthService().currentUser;
    final pic = user?['profile_image']?.toString() ?? '';
    final username = user?['username']?.toString() ?? 'You';
    final fullName = user?['full_name']?.toString() ?? 'Your Name';
    final gender = user?['gender']?.toString() ?? '';
    final gColor = gender.toLowerCase() == 'female'
        ? Colors.pinkAccent
        : gender.toLowerCase() == 'male'
        ? Colors.blue
        : Colors.deepPurple;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.pinkAccent.withValues(alpha: 0.2),
                  Colors.purple.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: gColor,
                      backgroundImage: pic.isNotEmpty
                          ? NetworkImage(pic)
                          : null,
                      child: pic.isEmpty
                          ? Text(
                              username.isNotEmpty ? username[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.pinkAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  fullName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '@$username',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                if (gender.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: gColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          gender.toLowerCase() == 'female'
                              ? Icons.female
                              : Icons.male,
                          color: gColor,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          gender,
                          style: TextStyle(
                            color: gColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _statChip(
                      '${_matches.length}',
                      'Matches',
                      Colors.pinkAccent,
                    ),
                    _statChip('${_likes.length}', 'Likes', Colors.purple),
                    _statChip('${_profiles.length}', 'Profiles', Colors.blue),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _settingTile(
            Icons.tune,
            'Dating Preferences',
            Colors.deepPurple,
            _showPreferences,
          ),
          _settingTile(Icons.photo_camera, 'Edit Photos', Colors.blue, () {}),
          _settingTile(
            Icons.notifications,
            'Notifications',
            Colors.orange,
            () {},
          ),
          _settingTile(Icons.security, 'Privacy & Safety', Colors.green, () {}),
          _settingTile(
            Icons.help_outline,
            'Help & Support',
            Colors.grey,
            () {},
          ),
        ],
      ),
    );
  }

  Widget _statChip(String val, String label, Color color) => Column(
    children: [
      Text(
        val,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 22,
          color: color,
        ),
      ),
      Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
    ],
  );

  Widget _settingTile(
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  void _showPreferences() {
    double minAge = _minAge, maxAge = _maxAge, dist = _maxDistance;
    String gPref = _genderPref;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (_, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Preferences',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                'Age Range: ${minAge.toInt()} – ${maxAge.toInt()}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              RangeSlider(
                values: RangeValues(minAge, maxAge),
                min: 18,
                max: 60,
                divisions: 42,
                activeColor: Colors.pinkAccent,
                onChanged: (v) => setLocal(() {
                  minAge = v.start;
                  maxAge = v.end;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'Max Distance: ${dist.toInt()} km',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: dist,
                min: 1,
                max: 200,
                divisions: 199,
                activeColor: Colors.pinkAccent,
                onChanged: (v) => setLocal(() => dist = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'Show me',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Opposite', 'Men', 'Women', 'Everyone']
                    .map(
                      (g) => ChoiceChip(
                        label: Text(g),
                        selected: gPref == g,
                        onSelected: (_) => setLocal(() => gPref = g),
                        selectedColor: Colors.pinkAccent,
                        labelStyle: TextStyle(
                          color: gPref == g ? Colors.white : null,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _minAge = minAge;
                      _maxAge = maxAge;
                      _maxDistance = dist;
                      _genderPref = gPref;
                    });
                    _loadData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pinkAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Apply', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Profile Detail Sheet ─────────────────────────────────────────────────────

class _ProfileDetailSheet extends StatelessWidget {
  final dynamic user;
  final bool isOnline;
  final bool isLive;
  final VoidCallback onLike;
  final VoidCallback onMessage;
  final VoidCallback onCall;

  const _ProfileDetailSheet({
    required this.user,
    required this.isOnline,
    required this.isLive,
    required this.onLike,
    required this.onMessage,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final pic = user['profile_image']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final fullName = user['full_name']?.toString() ?? username;
    final bio = user['bio']?.toString() ?? '';
    final loc = user['location']?.toString() ?? '';
    final gender = (user['gender'] ?? '').toString();
    final followers = (user['follower_count'] ?? 0) as int;

    final gColor = gender.toLowerCase() == 'female'
        ? Colors.pinkAccent
        : gender.toLowerCase() == 'male'
        ? Colors.blue
        : Colors.deepPurple;
    final gIcon = gender.toLowerCase() == 'female'
        ? Icons.female
        : gender.toLowerCase() == 'male'
        ? Icons.male
        : Icons.person;

    String fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => SingleChildScrollView(
        controller: sc,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Photo with gradient + live/online badge
            SizedBox(
              height: 380,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  pic.isNotEmpty
                      ? Image.network(
                          pic,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: gColor.withValues(alpha: 0.3),
                            child: Center(
                              child: Text(
                                username.isNotEmpty
                                    ? username[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 80,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          color: gColor.withValues(alpha: 0.3),
                          child: Center(
                            child: Text(
                              username.isNotEmpty
                                  ? username[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 80,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                  // Bottom gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.5),
                        ],
                        stops: const [0.6, 1.0],
                      ),
                    ),
                  ),
                  // LIVE badge
                  if (isLive)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (isOnline)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, color: Colors.white, size: 8),
                            SizedBox(width: 4),
                            Text(
                              'Online',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Gender badge top-right
                  if (gender.isNotEmpty)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: gColor.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(gIcon, color: Colors.white, size: 20),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '@$username',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      if (gender.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: gColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(gIcon, color: gColor, size: 13),
                              const SizedBox(width: 3),
                              Text(
                                gender,
                                style: TextStyle(
                                  color: gColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.people, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        '${fmt(followers)} followers',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                      if (loc.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          loc,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'About',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bio,
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Action buttons row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onLike,
                          icon: const Icon(
                            Icons.favorite,
                            color: Colors.pinkAccent,
                          ),
                          label: const Text('Like'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.pinkAccent),
                            foregroundColor: Colors.pinkAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onMessage,
                          icon: const Icon(Icons.message),
                          label: const Text('Message'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Call / Live button
                      Container(
                        width: 52,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: onCall,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLive ? Colors.red : Colors.blue,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Icon(
                            isLive ? Icons.videocam : Icons.call,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Random Connect (Omegle-style) Tab ────────────────────────────────────────

enum _RandomState { idle, searching, connected, disconnected }

class _RandomConnectTab extends StatefulWidget {
  const _RandomConnectTab();
  @override
  State<_RandomConnectTab> createState() => _RandomConnectTabState();
}

class _RandomConnectTabState extends State<_RandomConnectTab> {
  _RandomState _state = _RandomState.idle;
  dynamic _partner;
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _searchTimer;
  Timer? _typingTimer;
  bool _partnerTyping = false;
  int _onlineCount = 567;
  Timer? _onlineCountTimer;

  final List<String> _interests = [
    'Music',
    'Travel',
    'Gaming',
    'Art',
    'Food',
    'Fitness',
  ];
  final Set<String> _myInterests = {};

  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _msgSub;
  StreamSubscription? _typingSub;

  final List<Map<String, dynamic>> _samplePartners = [
    {
      'username': 'stranger_7482',
      'full_name': 'Stranger',
      'bio': 'Just browsing 👋',
      'profile_image': '',
    },
    {
      'username': 'music_lover',
      'full_name': 'Music Fan',
      'bio': 'Love indie music 🎵',
      'profile_image': '',
    },
    {
      'username': 'traveler_92',
      'full_name': 'World Traveler',
      'bio': 'Been to 30 countries ✈️',
      'profile_image': '',
    },
    {
      'username': 'coder_x',
      'full_name': 'Dev',
      'bio': 'Flutter developer 💻',
      'profile_image': '',
    },
    {
      'username': 'artist_24',
      'full_name': 'Artist',
      'bio': 'Digital art ✏️',
      'profile_image': '',
    },
    {
      'username': 'gamer_pro',
      'full_name': 'Gamer',
      'bio': 'FPS pro player 🎮',
      'profile_image': '',
    },
  ];

  final List<String> _autoReplies = [
    'Hey! How are you? 😊',
    'What are your interests?',
    'Where are you from?',
    'Nice to meet you!',
    'What brings you here?',
    'Do you like music?',
    'lol that\'s cool 😄',
    'Same here!',
    'Tell me more about yourself',
    'That\'s interesting! 🤔',
    'Wow really?',
    'haha 😂',
    'Yeah I agree',
    'What do you do for fun?',
  ];

  @override
  void initState() {
    super.initState();
    _startOnlineCountFlicker();
    _subscribeMsgs();
  }

  void _subscribeMsgs() {
    _msgSub = _ws.onChatMessage.listen((msg) {
      if (!mounted || _state != _RandomState.connected) return;
      setState(
        () => _messages.add({
          'text': msg['content']?.toString() ?? '',
          'isMe': false,
          'time': _nowTime(),
        }),
      );
      _scrollBottom();
    });
    _typingSub = _ws.onTyping.listen((t) {
      if (!mounted || _state != _RandomState.connected) return;
      setState(() => _partnerTyping = t['is_typing'] == true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _partnerTyping = false);
      });
    });
  }

  void _startOnlineCountFlicker() {
    _onlineCountTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() => _onlineCount += (DateTime.now().second % 2 == 0) ? 3 : -2);
    });
  }

  void _startSearch() {
    setState(() {
      _state = _RandomState.searching;
      _messages.clear();
      _partner = null;
    });
    final delay = Duration(
      milliseconds: 2000 + (DateTime.now().millisecond % 3000),
    );
    _searchTimer = Timer(delay, () {
      if (!mounted) return;
      final idx = DateTime.now().millisecond % _samplePartners.length;
      setState(() {
        _partner = Map<String, dynamic>.from(_samplePartners[idx]);
        _state = _RandomState.connected;
      });
      Timer(const Duration(milliseconds: 1500), () {
        if (!mounted || _state != _RandomState.connected) return;
        _receiveAutoMessage('Hey there! 👋');
      });
    });
  }

  void _disconnect() {
    _searchTimer?.cancel();
    if (_state == _RandomState.connected) {
      setState(() {
        _messages.add({
          'text': '-- Stranger has disconnected --',
          'isMe': null,
          'time': _nowTime(),
        });
        _state = _RandomState.disconnected;
      });
    } else {
      setState(() => _state = _RandomState.disconnected);
    }
  }

  void _next() {
    _searchTimer?.cancel();
    _messages.clear();
    _startSearch();
  }

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _state != _RandomState.connected) return;
    setState(
      () => _messages.add({'text': text, 'isMe': true, 'time': _nowTime()}),
    );
    _msgCtrl.clear();
    _scrollBottom();
    final delay = Duration(
      milliseconds: 800 + (DateTime.now().millisecond % 2200),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _state == _RandomState.connected)
        setState(() => _partnerTyping = true);
    });
    Timer(delay, () {
      if (!mounted || _state != _RandomState.connected) return;
      setState(() => _partnerTyping = false);
      _receiveAutoMessage(
        _autoReplies[DateTime.now().millisecond % _autoReplies.length],
      );
    });
  }

  void _receiveAutoMessage(String text) {
    if (!mounted) return;
    setState(() {
      _partnerTyping = false;
      _messages.add({'text': text, 'isMe': false, 'time': _nowTime()});
    });
    _scrollBottom();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients)
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
    });
  }

  String _nowTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _typingTimer?.cancel();
    _onlineCountTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _msgSub?.cancel();
    _typingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _RandomState.idle:
        return _idleView();
      case _RandomState.searching:
        return _searchingView();
      case _RandomState.connected:
        return _chatView();
      case _RandomState.disconnected:
        return _disconnectedView();
    }
  }

  Widget _idleView() => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.deepPurple, Colors.pinkAccent],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.shuffle_rounded,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Random Connect',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chat anonymously with strangers',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_onlineCount people online now',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Select Interests (optional)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _interests.map((tag) {
              final selected = _myInterests.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: selected,
                onSelected: (_) => setState(
                  () => selected
                      ? _myInterests.remove(tag)
                      : _myInterests.add(tag),
                ),
                selectedColor: Colors.deepPurple.withValues(alpha: 0.2),
                checkmarkColor: Colors.deepPurple,
                labelStyle: TextStyle(
                  color: selected ? Colors.deepPurple : Colors.black87,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RandomVideoPage()),
              ),
              icon: const Icon(Icons.videocam, size: 24),
              label: const Text(
                'Video Chat (Omegle-style)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _startSearch,
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              label: const Text(
                'Text Chat Only',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                side: const BorderSide(color: Colors.deepPurple, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _searchingView() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            strokeWidth: 6,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Finding someone...',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Searching $_onlineCount people online',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: () => setState(() => _state = _RandomState.idle),
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
          ),
        ),
      ],
    ),
  );

  Widget _chatView() {
    final name = _partner?['username']?.toString() ?? 'Stranger';
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stranger',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            _partnerTyping
                ? const Text(
                    'typing...',
                    style: TextStyle(color: Colors.deepPurple, fontSize: 11),
                  )
                : const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 8),
                      SizedBox(width: 4),
                      Text(
                        'Online',
                        style: TextStyle(color: Colors.green, fontSize: 11),
                      ),
                    ],
                  ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _next,
            icon: const Icon(Icons.skip_next, color: Colors.deepPurple),
            label: const Text(
              'Next',
              style: TextStyle(
                color: Colors.deepPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            label: const Text(
              'Stop',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.deepPurple.withValues(alpha: 0.07),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shuffle_rounded, size: 14, color: Colors.deepPurple),
                SizedBox(width: 6),
                Text(
                  'Connected • Tap "Next" for someone new',
                  style: TextStyle(color: Colors.deepPurple, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Say hello! 👋',
                      style: TextStyle(color: Colors.grey[500], fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isMe = msg['isMe'];
                      if (isMe == null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                msg['text'] ?? '',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return _msgBubble(
                        msg['text'] ?? '',
                        isMe as bool,
                        msg['time'] ?? '',
                      );
                    },
                  ),
          ),
          if (_partnerTyping)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.deepPurple,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _dot(0),
                        const SizedBox(width: 4),
                        _dot(1),
                        const SizedBox(width: 4),
                        _dot(2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Say something...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.deepPurple,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _msgBubble(String text, bool isMe, String time) => Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: EdgeInsets.only(
        bottom: 6,
        left: isMe ? 60 : 0,
        right: isMe ? 0 : 60,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? Colors.deepPurple : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: isMe ? Colors.white : Colors.black87,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            time,
            style: TextStyle(
              color: isMe ? Colors.white54 : Colors.grey[400],
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _dot(int index) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: Duration(milliseconds: 600 + index * 150),
    curve: Curves.easeInOut,
    builder: (_, v, __) => Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.grey[400]!.withValues(alpha: 0.4 + v * 0.6),
        shape: BoxShape.circle,
      ),
    ),
  );

  Widget _disconnectedView() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_off, size: 56, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        const Text(
          'Conversation ended',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'The stranger has left the chat',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _state = _RandomState.idle;
                _messages.clear();
              }),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Home'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _next,
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text(
                'New Chat',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ─── Match Animation Dialog ────────────────────────────────────────────────────

class _MatchDialog extends StatelessWidget {
  final dynamic user;
  final VoidCallback onMessage;
  final VoidCallback onContinue;

  const _MatchDialog({
    required this.user,
    required this.onMessage,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final pic = user['profile_image']?.toString() ?? '';
    final name =
        user['full_name']?.toString() ??
        user['username']?.toString() ??
        'Someone';
    final me = AuthService().currentUser;
    final myPic = me?['profile_image']?.toString() ?? '';
    final myName = me?['username']?.toString() ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '💝 It\'s a Match!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You and $name like each other',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.deepPurple,
                backgroundImage: myPic.isNotEmpty ? NetworkImage(myPic) : null,
                child: myPic.isEmpty
                    ? Text(
                        myName.isNotEmpty ? myName[0].toUpperCase() : 'M',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                        ),
                      )
                    : null,
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: -8),
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Colors.pinkAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.pinkAccent,
                backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                child: pic.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onContinue,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white70),
                  foregroundColor: Colors.white70,
                ),
                child: const Text('Keep Swiping'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onMessage,
                icon: const Icon(Icons.message),
                label: const Text('Send Message'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
