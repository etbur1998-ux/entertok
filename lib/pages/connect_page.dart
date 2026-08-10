import 'dart:async';
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import 'message_page.dart';
import 'user_profile_page.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final WebSocketService _ws = WebSocketService();

  // Data
  List<dynamic> _suggestions = [];
  List<dynamic> _followers = [];
  List<dynamic> _following = [];
  List<dynamic> _trendingPosts = [];
  final Map<int, bool> _followingState = {};
  final Map<int, bool> _onlineUsers = {};

  bool _isLoading = true;

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchTimer;
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  bool _showSearch = false;

  // Job/Freelance filter
  String _selectedSkill = 'All';
  final List<String> _skills = [
    'All',
    'Design',
    'Development',
    'Marketing',
    'Writing',
    'Video',
    'Photography',
    'Finance',
    'Legal',
    'Consulting',
    'Education',
  ];

  // Realtime
  StreamSubscription? _onlineSub;
  StreamSubscription? _followSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchTimer?.cancel();
    _onlineSub?.cancel();
    _followSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    _onlineSub = _ws.onOnlineStatus.listen((data) {
      if (!mounted) return;
      final uid = data['user_id'] as int?;
      if (uid != null)
        setState(() => _onlineUsers[uid] = data['is_online'] == true);
    });
    _followSub = _ws.onFollow.listen((_) {
      if (mounted) _loadData();
    });
  }

  // ─── Data Loading ────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = AuthService().currentUser;
      final userId = user?['id'];
      List<dynamic> results;
      if (userId != null) {
        results = await Future.wait([
          _userService.getSuggestions(limit: 30),
          _userService.getFollowers(userId),
          _userService.getFollowing(userId),
          _postService.getTrending(),
        ]);
      } else {
        results = await Future.wait([
          _userService.getSuggestions(limit: 30),
          _postService.getTrending(),
        ]);
      }
      if (mounted) {
        setState(() {
          _suggestions = results[0];
          if (userId != null && results.length >= 4) {
            _followers = results[1];
            _following = results[2];
            _trendingPosts = results[3];
          } else if (results.length >= 2) {
            _trendingPosts = results[1];
          }
          for (final u in _following) {
            final id = u['id'] as int?;
            if (id != null) _followingState[id] = true;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _toggleFollow(dynamic user) async {
    final uid = user['id'] as int?;
    if (uid == null) return;
    final was = _followingState[uid] ?? false;
    setState(() => _followingState[uid] = !was);
    try {
      if (was)
        await _userService.unfollowUser(uid);
      else
        await _userService.followUser(uid);
      await _loadData();
    } catch (_) {
      if (mounted) setState(() => _followingState[uid] = was);
    }
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
          avatar: Colors.deepPurple,
          isOnline: _onlineUsers[user['id']] ?? false,
          receiverId: user['id'] as int?,
          profileImage: user['profile_image']?.toString(),
        ),
      ),
    );
  }

  void _openProfile(dynamic user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          userId: user['id'] as int,
          username: user['username']?.toString(),
        ),
      ),
    );
  }

  void _onSearch(String q) {
    setState(() {});
    _searchTimer?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _searchTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await _userService.searchUsers(q);
        if (mounted)
          setState(() {
            _searchResults = r;
            _isSearching = false;
          });
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: _showSearch
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search people, jobs, skills...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _showSearch = false;
                        _searchResults = [];
                      });
                    },
                  ),
                ),
                onChanged: _onSearch,
              )
            : const Text(
                'Connect',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
        actions: [
          if (!_showSearch) ...[
            IconButton(
              icon: const Icon(Icons.search, color: Colors.black),
              onPressed: () => setState(() => _showSearch = true),
            ),
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                color: Colors.black,
              ),
              onPressed: () {},
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.business_center, size: 18), text: 'Business'),
            Tab(
              icon: Icon(Icons.manage_accounts, size: 18),
              text: 'My Network',
            ),
            Tab(icon: Icon(Icons.work_outline, size: 18), text: 'Freelance'),
            Tab(icon: Icon(Icons.trending_up, size: 18), text: 'Activity'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showSearch && _searchCtrl.text.isNotEmpty
          ? _searchView()
          : TabBarView(
              controller: _tabController,
              children: [
                _businessTab(),
                _myNetworkTab(),
                _freelanceTab(),
                _activityTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreatePost,
        backgroundColor: Colors.deepPurple,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Post',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ─── Search View ─────────────────────────────────────────────────────────

  Widget _searchView() {
    if (_isSearching) return const Center(child: CircularProgressIndicator());
    if (_searchResults.isEmpty)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No results for "${_searchCtrl.text.trim()}"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _userCard(_searchResults[i]),
    );
  }

  // ─── Business Tab ─────────────────────────────────────────────────────────

  Widget _businessTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Network summary card
          _networkSummaryCard(),
          const SizedBox(height: 16),
          // Suggested connections
          _sectionHeader(
            'Suggested Connections',
            Icons.people_alt,
            trailing: TextButton(
              onPressed: _loadData,
              child: const Text('Refresh'),
            ),
          ),
          const SizedBox(height: 8),
          if (_suggestions.isEmpty)
            _emptyState('No suggestions yet', Icons.people_outline)
          else
            ..._suggestions.take(8).map((u) => _userCard(u)),
          const SizedBox(height: 16),
          // Trending posts from network
          _sectionHeader('Business Trending', Icons.trending_up),
          const SizedBox(height: 8),
          if (_trendingPosts.isEmpty)
            _emptyState('No trending posts', Icons.article_outlined)
          else
            ..._trendingPosts.take(5).map((p) => _postCard(p)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _networkSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B2D8E), Color(0xFF9C27B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Business Network',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _networkStat(Icons.people, _fmt(_followers.length), 'Followers'),
              _vDivider(),
              _networkStat(
                Icons.person_add,
                _fmt(_following.length),
                'Following',
              ),
              _vDivider(),
              _networkStat(
                Icons.public,
                _fmt(_suggestions.length * 5),
                'Reach',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _tabController.animateTo(1),
                  icon: const Icon(Icons.people, size: 15, color: Colors.white),
                  label: const Text(
                    'Network',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _tabController.animateTo(2),
                  icon: const Icon(
                    Icons.work_outline,
                    size: 15,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Freelance',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _networkStat(IconData icon, String val, String label) => Column(
    children: [
      Icon(icon, color: Colors.white, size: 22),
      const SizedBox(height: 4),
      Text(
        val,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ],
  );

  Widget _vDivider() => Container(width: 1, height: 44, color: Colors.white24);

  // ─── My Network Tab ───────────────────────────────────────────────────────

  Widget _myNetworkTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: [
              Tab(text: 'Followers'),
              Tab(text: 'Following'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _networkList(
                  _followers,
                  'No followers yet',
                  'Share your profile to get followers',
                ),
                _networkList(
                  _following,
                  'Not following anyone',
                  'Discover people in the Business tab',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkList(
    List<dynamic> users,
    String emptyTitle,
    String emptySubtitle,
  ) {
    if (users.isEmpty)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              emptyTitle,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              emptySubtitle,
              style: TextStyle(color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _tabController.animateTo(0),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Explore'),
            ),
          ],
        ),
      );
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _userCard(users[i]),
      ),
    );
  }

  // ─── Freelance Tab ────────────────────────────────────────────────────────

  Widget _freelanceTab() {
    final filtered = _selectedSkill == 'All'
        ? _suggestions
        : _suggestions
              .where(
                (u) =>
                    (u['bio']?.toString() ?? '').toLowerCase().contains(
                      _selectedSkill.toLowerCase(),
                    ) ||
                    (u['username']?.toString() ?? '').toLowerCase().contains(
                      _selectedSkill.toLowerCase(),
                    ),
              )
              .toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Skill filter chips
          _sectionHeader('Find Talent', Icons.work_outline),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _skills.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final sel = _selectedSkill == _skills[i];
                return ChoiceChip(
                  label: Text(_skills[i]),
                  selected: sel,
                  onSelected: (_) =>
                      setState(() => _selectedSkill = _skills[i]),
                  selectedColor: Colors.deepPurple,
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : Colors.black87,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Post a job card
          _postJobCard(),
          const SizedBox(height: 16),
          _sectionHeader(
            'Available Talent',
            Icons.star_outline,
            trailing: Text(
              '${filtered.length} people',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            _emptyState(
              'No freelancers for "$_selectedSkill" yet',
              Icons.person_search,
            )
          else
            ...filtered.take(10).map((u) => _freelancerCard(u)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _postJobCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.add_business, color: Colors.blue, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Post a Job or Project',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  'Find the perfect talent for your needs',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _showPostJobDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Post', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _freelancerCard(dynamic user) {
    final pic = user['profile_image']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final fullName = user['full_name']?.toString() ?? '';
    final bio = user['bio']?.toString() ?? '';
    final followers = (user['follower_count'] ?? 0) as int;
    final isFollowing = _followingState[user['id']] ?? false;
    final isOnline = _onlineUsers[user['id']] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _openProfile(user),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.deepPurple,
                        backgroundImage: pic.isNotEmpty
                            ? NetworkImage(pic)
                            : null,
                        child: pic.isEmpty
                            ? Text(
                                username.isNotEmpty
                                    ? username[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                ),
                              )
                            : null,
                      ),
                      if (isOnline)
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              fullName.isNotEmpty ? fullName : username,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user['is_verified'] == true) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              color: Colors.blue,
                              size: 15,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '@$username',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      Row(
                        children: [
                          Icon(Icons.people, size: 13, color: Colors.grey[500]),
                          Text(
                            ' ${_fmt(followers)} followers',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11,
                            ),
                          ),
                          if (isOnline) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.circle,
                              color: Colors.green,
                              size: 8,
                            ),
                            const Text(
                              ' Online',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
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
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                bio,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            // Skill tags (extract from bio)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ..._extractSkills(bio)
                    .take(4)
                    .map(
                      (s) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.deepPurple.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          s,
                          style: const TextStyle(
                            color: Colors.deepPurple,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showHireDialog(user),
                    icon: const Icon(Icons.handshake_outlined, size: 16),
                    label: const Text('Hire'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openChat(user),
                    icon: const Icon(Icons.message_outlined, size: 16),
                    label: const Text('Message'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side: const BorderSide(color: Colors.deepPurple),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _toggleFollow(user),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    foregroundColor: isFollowing
                        ? Colors.grey
                        : Colors.deepPurple,
                    side: BorderSide(
                      color: isFollowing ? Colors.grey : Colors.deepPurple,
                    ),
                  ),
                  child: Icon(
                    isFollowing ? Icons.person_remove : Icons.person_add,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _extractSkills(String bio) {
    final all = [
      'Design',
      'Dev',
      'Code',
      'Marketing',
      'Writing',
      'Video',
      'Photo',
      'Finance',
      'Legal',
      'AI',
      'Flutter',
      'React',
      'UI',
      'UX',
      'SEO',
      'Brand',
      'Social',
      'Content',
      'Sales',
      'Data',
    ];
    return all
        .where((s) => bio.toLowerCase().contains(s.toLowerCase()))
        .toList();
  }

  // ─── Activity Tab ─────────────────────────────────────────────────────────

  Widget _activityTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Online now
          if (_onlineUsers.isNotEmpty) ...[
            _sectionHeader('Online Now', Icons.circle, color: Colors.green),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: [
                  ..._followers,
                  ..._following,
                ].where((u) => _onlineUsers[u['id']] == true).length,
                itemBuilder: (_, i) {
                  final onlineList = [
                    ..._followers,
                    ..._following,
                  ].where((u) => _onlineUsers[u['id']] == true).toList();
                  if (i >= onlineList.length) return const SizedBox();
                  final u = onlineList[i];
                  final pic = u['profile_image']?.toString() ?? '';
                  return GestureDetector(
                    onTap: () => _openProfile(u),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.deepPurple,
                                backgroundImage: pic.isNotEmpty
                                    ? NetworkImage(pic)
                                    : null,
                                child: pic.isEmpty
                                    ? Text(
                                        (u['username'] ?? 'U')[0]
                                            .toString()
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              ),
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            u['username']?.toString() ?? '',
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          _sectionHeader('Trending Activity', Icons.trending_up),
          const SizedBox(height: 8),
          if (_trendingPosts.isEmpty)
            _emptyState('No activity yet', Icons.article_outlined)
          else
            ..._trendingPosts.map((p) => _postCard(p)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ─── Shared Widgets ───────────────────────────────────────────────────────

  Widget _userCard(dynamic user) {
    final pic = user['profile_image']?.toString() ?? '';
    final username = user['username']?.toString() ?? '';
    final fullName = user['full_name']?.toString() ?? '';
    final bio = user['bio']?.toString() ?? '';
    final followers = (user['follower_count'] ?? 0) as int;
    final isFollowing =
        _followingState[user['id']] ?? (user['is_following'] == true);
    final isOnline = _onlineUsers[user['id']] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _openProfile(user),
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.deepPurple,
                    backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                    child: pic.isEmpty
                        ? Text(
                            username.isNotEmpty
                                ? username[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  if (isOnline)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _openProfile(user),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fullName.isNotEmpty ? fullName : username,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user['is_verified'] == true) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            color: Colors.blue,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '@$username • ${_fmt(followers)} followers',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                    if (bio.isNotEmpty)
                      Text(
                        bio,
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 88,
                  child: isFollowing
                      ? OutlinedButton(
                          onPressed: () => _toggleFollow(user),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            side: const BorderSide(color: Colors.deepPurple),
                            foregroundColor: Colors.deepPurple,
                          ),
                          child: const Text(
                            'Following',
                            style: TextStyle(fontSize: 11),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: () => _toggleFollow(user),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text(
                            'Follow',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 88,
                  child: OutlinedButton(
                    onPressed: () => _openChat(user),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: Colors.deepPurple,
                      side: const BorderSide(color: Colors.deepPurple),
                    ),
                    child: const Text(
                      'Message',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _postCard(dynamic post) {
    final user = (post['user'] as Map?) ?? {};
    final pic = user['profile_image']?.toString() ?? '';
    final username = user['username']?.toString() ?? 'user';
    final mediaUrl = post['media_url']?.toString() ?? '';
    final mediaType = post['media_type']?.toString() ?? '';
    final isVideo =
        mediaType == 'video' || mediaUrl.toLowerCase().endsWith('.mp4');
    final isImage = mediaType == 'image';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            leading: GestureDetector(
              onTap: () => _openProfile(user),
              child: CircleAvatar(
                backgroundColor: Colors.deepPurple,
                backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                child: pic.isEmpty
                    ? Text(
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            title: Text(
              user['full_name']?.toString().isNotEmpty == true
                  ? user['full_name'].toString()
                  : username,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              '@$username • ${_fmt((post['view_count'] ?? 0) as int)} views',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            trailing: _followingState[user['id']] == true
                ? null
                : ElevatedButton(
                    onPressed: () => _toggleFollow(user),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(70, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Follow', style: TextStyle(fontSize: 11)),
                  ),
          ),
          if (mediaUrl.isNotEmpty) ...[
            if (isVideo)
              Container(
                height: 160,
                color: Colors.grey[900],
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white70,
                    size: 50,
                  ),
                ),
              )
            else if (isImage)
              Image.network(
                mediaUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
          ],
          if ((post['content']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Text(
                post['content'].toString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Row(
              children: [
                Icon(Icons.favorite_border, size: 15, color: Colors.grey[500]),
                Text(
                  ' ${_fmt((post['like_count'] ?? 0) as int)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(width: 14),
                Icon(Icons.comment_outlined, size: 15, color: Colors.grey[500]),
                Text(
                  ' ${_fmt((post['comment_count'] ?? 0) as int)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    IconData icon, {
    Color? color,
    Widget? trailing,
  }) => Row(
    children: [
      Icon(icon, color: color ?? Colors.deepPurple, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      if (trailing != null) trailing,
    ],
  );

  Widget _emptyState(String msg, IconData icon) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    ),
  );

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  void _showPostJobDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final budgetCtrl = TextEditingController();
    String selSkill = 'Design';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Post a Job / Project',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Job Title *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Budget (USD)',
                  border: OutlineInputBorder(),
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Skill Required',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _skills
                    .where((s) => s != 'All')
                    .map(
                      (s) => ChoiceChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        selected: selSkill == s,
                        onSelected: (_) => setLocal(() => selSkill = s),
                        selectedColor: Colors.deepPurple,
                        labelStyle: TextStyle(
                          color: selSkill == s ? Colors.white : null,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    if (titleCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Job posted! 🎉'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Post Job', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHireDialog(dynamic user) {
    final msgCtrl = TextEditingController(
      text:
          'Hi ${user['full_name'] ?? user['username']}, I\'d like to hire you for a project...',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hire @${user['username'] ?? 'user'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: msgCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Message',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openChat(user);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send & Chat'),
          ),
        ],
      ),
    );
  }

  void _showCreatePost() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create Post',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: "What's on your mind?",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  if (ctrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    await _postService.createPost(
                      content: ctrl.text.trim(),
                      mediaUrl:
                          'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                      mediaType: 'video',
                    );
                    await _loadData();
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Posted!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                  } catch (e) {
                    if (mounted)
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Publish', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── User Profile Sheet ───────────────────────────────────────────────────────

class _UserProfileSheet extends StatefulWidget {
  final dynamic user;
  final bool isFollowing;
  final bool isOnline;
  final VoidCallback onFollow;
  final VoidCallback onMessage;
  final UserService userService;
  final PostService postService;
  const _UserProfileSheet({
    required this.user,
    required this.isFollowing,
    required this.isOnline,
    required this.onFollow,
    required this.onMessage,
    required this.userService,
    required this.postService,
  });
  @override
  State<_UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<_UserProfileSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tc;
  List<dynamic> _posts = [];
  bool _loading = true;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 2, vsync: this);
    _isFollowing = widget.isFollowing;
    _loadPosts();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    try {
      final uid = widget.user['id'];
      if (uid != null) {
        final p = await widget.postService.getUserPosts(uid);
        if (mounted)
          setState(() {
            _posts = p;
            _loading = false;
          });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user as Map;
    final pic = u['profile_image']?.toString() ?? '';
    final username = u['username']?.toString() ?? '';
    final fullName = u['full_name']?.toString() ?? '';
    final bio = u['bio']?.toString() ?? '';
    final website = u['website']?.toString() ?? '';
    final location = u['location']?.toString() ?? '';
    final followers = (u['follower_count'] ?? 0) as int;
    final following = (u['following_count'] ?? 0) as int;
    final posts = (u['post_count'] ?? _posts.length) as int;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => Column(
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
          Expanded(
            child: SingleChildScrollView(
              controller: sc,
              child: Column(
                children: [
                  // Cover
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.deepPurple.shade700,
                          Colors.purple.shade400,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          bottom: -30,
                          left: 20,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.white,
                                child: CircleAvatar(
                                  radius: 37,
                                  backgroundColor: Colors.deepPurple,
                                  backgroundImage: pic.isNotEmpty
                                      ? NetworkImage(pic)
                                      : null,
                                  child: pic.isEmpty
                                      ? Text(
                                          username.isNotEmpty
                                              ? username[0].toUpperCase()
                                              : 'U',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              if (widget.isOnline)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        fullName.isNotEmpty
                                            ? fullName
                                            : username,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (u['is_verified'] == true) ...[
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.verified,
                                          color: Colors.blue,
                                          size: 18,
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '@$username',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (widget.isOnline)
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          color: Colors.green,
                                          size: 10,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Online now',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            bio,
                            style: const TextStyle(fontSize: 14, height: 1.6),
                          ),
                        ],
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                location,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (website.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.link,
                                size: 14,
                                color: Colors.deepPurple,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                website,
                                style: const TextStyle(
                                  color: Colors.deepPurple,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _st('${_fmt(posts)}\nPosts', Colors.deepPurple),
                            Container(
                              width: 1,
                              height: 32,
                              color: Colors.grey[300],
                            ),
                            _st('${_fmt(followers)}\nFollowers', Colors.blue),
                            Container(
                              width: 1,
                              height: 32,
                              color: Colors.grey[300],
                            ),
                            _st('${_fmt(following)}\nFollowing', Colors.green),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _isFollowing
                                  ? OutlinedButton.icon(
                                      onPressed: () {
                                        widget.onFollow();
                                        setState(() => _isFollowing = false);
                                      },
                                      icon: const Icon(Icons.check, size: 16),
                                      label: const Text('Following'),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Colors.deepPurple,
                                        ),
                                        foregroundColor: Colors.deepPurple,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                    )
                                  : ElevatedButton.icon(
                                      onPressed: () {
                                        widget.onFollow();
                                        setState(() => _isFollowing = true);
                                      },
                                      icon: const Icon(
                                        Icons.person_add,
                                        size: 16,
                                      ),
                                      label: const Text('Follow'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.deepPurple,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onMessage();
                                },
                                icon: const Icon(
                                  Icons.message_outlined,
                                  size: 16,
                                ),
                                label: const Text('Message'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.deepPurple,
                                  side: const BorderSide(
                                    color: Colors.deepPurple,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tc,
                    labelColor: Colors.deepPurple,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.deepPurple,
                    tabs: const [
                      Tab(icon: Icon(Icons.grid_on)),
                      Tab(icon: Icon(Icons.videocam)),
                    ],
                  ),
                  SizedBox(
                    height: 320,
                    child: TabBarView(
                      controller: _tc,
                      children: [_grid(false), _grid(true)],
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

  Widget _st(String text, Color color) {
    final p = text.split('\n');
    return Column(
      children: [
        Text(
          p[0],
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(p[1], style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }

  Widget _grid(bool videoOnly) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final items = videoOnly
        ? _posts.where((p) => p['media_type'] == 'video').toList()
        : _posts;
    if (items.isEmpty)
      return Center(
        child: Text(
          videoOnly ? 'No videos' : 'No posts',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final p = items[i];
        final url = p['media_url']?.toString() ?? '';
        final isVid = p['media_type'] == 'video' || url.endsWith('.mp4');
        return Stack(
          fit: StackFit.expand,
          children: [
            if (url.isNotEmpty && !isVid)
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: Colors.grey[200]),
              )
            else
              Container(
                color: Colors.grey[900],
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white54,
                    size: 28,
                  ),
                ),
              ),
            Positioned(
              bottom: 4,
              left: 4,
              child: Row(
                children: [
                  const Icon(Icons.favorite, size: 12, color: Colors.white70),
                  Text(
                    ' ${p['like_count'] ?? 0}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
