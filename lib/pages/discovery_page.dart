import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/post_service.dart';
import '../services/comment_service.dart';
import '../services/user_service.dart';
import '../services/upload_service.dart';
import '../services/auth_service.dart';
import 'user_profile_page.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});
  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PostService _postService = PostService();
  final UserService _userService = UserService();

  List<dynamic> _forYouPosts = [];
  List<dynamic> _trendingPosts = [];
  List<dynamic> _trendingHashtags = [];
  List<dynamic> _suggestedUsers = [];
  bool _isLoading = true;

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchTimer;
  List<dynamic> _searchResults = [];
  bool _isSearching = false;

  // Liked posts (local optimistic)
  final Set<int> _likedPosts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  // ─── Load ────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _postService.getFeed(),
        _postService.getTrending(),
        _postService.getTrendingHashtags(),
        _userService.getSuggestions(),
      ]);
      if (mounted) {
        setState(() {
          _forYouPosts = results[0];
          _trendingPosts = results[1];
          _trendingHashtags = results[2];
          _suggestedUsers = results[3];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Search ──────────────────────────────────────────────────────────────

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
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await Future.wait([
          _userService.searchUsers(q),
          _postService.getFeed(),
        ]);
        final users = results[0];
        final posts = results[1].where((p) {
          final content = p['content']?.toString().toLowerCase() ?? '';
          final tags = p['hash_tags']?.toString().toLowerCase() ?? '';
          return content.contains(q.toLowerCase()) ||
              tags.contains(q.toLowerCase());
        }).toList();
        if (mounted) {
          setState(() {
            _searchResults = [
              ...users.map(
                (u) => {...(u as Map<String, dynamic>), '_type': 'user'},
              ),
              ...posts.map(
                (p) => {...(p as Map<String, dynamic>), '_type': 'post'},
              ),
            ];
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  // ─── Like ────────────────────────────────────────────────────────────────

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final id = post['id'] as int;
    final liked = _likedPosts.contains(id);
    setState(() {
      liked ? _likedPosts.remove(id) : _likedPosts.add(id);
    });
    try {
      if (liked)
        await _postService.unlikePost(id);
      else
        await _postService.likePost(id);
    } catch (_) {
      setState(() {
        liked ? _likedPosts.add(id) : _likedPosts.remove(id);
      });
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: _searchBar(),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          isScrollable: true,
          tabs: const [
            Tab(text: 'For You'),
            Tab(text: 'Trending'),
            Tab(text: '#Hashtags'),
            Tab(text: 'People'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _searchCtrl.text.isNotEmpty
          ? _searchView()
          : TabBarView(
              controller: _tabController,
              children: [
                _postFeed(_forYouPosts),
                _postFeed(_trendingPosts),
                _hashtagsTab(),
                _peopleTab(),
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

  Widget _searchBar() => TextField(
    controller: _searchCtrl,
    decoration: InputDecoration(
      hintText: 'Search posts, people, #hashtags...',
      prefixIcon: _isSearching
          ? const SizedBox(
              width: 20,
              height: 20,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : const Icon(Icons.search),
      suffixIcon: _searchCtrl.text.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchCtrl.clear();
                setState(() {
                  _searchResults = [];
                });
              },
            )
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      filled: true,
      fillColor: Colors.grey[100],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    onChanged: _onSearch,
  );

  // ─── Search View ─────────────────────────────────────────────────────────

  Widget _searchView() {
    if (_isSearching) return const Center(child: CircularProgressIndicator());
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No results for "${_searchCtrl.text}"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    final users = _searchResults.where((r) => r['_type'] == 'user').toList();
    final posts = _searchResults.where((r) => r['_type'] == 'post').toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (users.isNotEmpty) ...[
          _sectionHeader('People', Icons.person),
          const SizedBox(height: 8),
          ...users.map((u) => _userTile(u)),
          const SizedBox(height: 16),
        ],
        if (posts.isNotEmpty) ...[
          _sectionHeader('Posts', Icons.grid_on),
          const SizedBox(height: 8),
          ...posts.map((p) => _postCard(p as Map<String, dynamic>)),
        ],
      ],
    );
  }

  // ─── Post Feed ────────────────────────────────────────────────────────────

  Widget _postFeed(List<dynamic> posts) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'Nothing here yet',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: posts.length,
        itemBuilder: (_, i) => _postCard(posts[i] as Map<String, dynamic>),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> post) {
    final user = (post['user'] as Map?) ?? {};
    final pic = user['profile_image']?.toString() ?? '';
    final username = user['username']?.toString() ?? 'user';
    final fullName = user['full_name']?.toString() ?? '';
    final content = post['content']?.toString() ?? '';
    final mediaUrl = post['media_url']?.toString() ?? '';
    final mediaType = post['media_type']?.toString() ?? '';
    final hashTags = post['hash_tags']?.toString() ?? '';
    final isLiked =
        _likedPosts.contains(post['id'] as int? ?? 0) ||
        post['is_liked'] == true;
    final likeCount = (post['like_count'] ?? 0) as int;
    final commentCount = (post['comment_count'] ?? 0) as int;
    final shareCount = (post['share_count'] ?? 0) as int;
    final viewCount = (post['view_count'] ?? 0) as int;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            leading: CircleAvatar(
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
            title: Text(
              fullName.isNotEmpty ? fullName : username,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Row(
              children: [
                Text(
                  '@$username',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                if (viewCount > 0) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.visibility, size: 12, color: Colors.grey[400]),
                  Text(
                    ' ${_fmt(viewCount)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'report')
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report submitted')),
                  );
                if (v == 'share')
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Link copied!')));
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, size: 18),
                      SizedBox(width: 8),
                      Text('Share'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Report', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Media ─────────────────────────────────────────────────────────
          if (mediaUrl.isNotEmpty) _mediaWidget(mediaUrl, mediaType, post),
          // ── Content ─────────────────────────────────────────────────────
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: _ExpandableText(content),
            ),
          // ── Hashtags ─────────────────────────────────────────────────────
          if (hashTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Wrap(
                spacing: 6,
                children: hashTags.split(',').map((t) {
                  final tag = t.trim();
                  return GestureDetector(
                    onTap: () => _searchByHashtag(tag),
                    child: Text(
                      tag.startsWith('#') ? tag : '#$tag',
                      style: const TextStyle(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          // ── Actions ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                _actionBtn(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  isLiked ? Colors.red : Colors.grey[600]!,
                  _fmt(likeCount),
                  () => _toggleLike(post),
                ),
                _actionBtn(
                  Icons.comment_outlined,
                  Colors.grey[600]!,
                  _fmt(commentCount),
                  () => _showComments(post),
                ),
                _actionBtn(
                  Icons.share_outlined,
                  Colors.grey[600]!,
                  _fmt(shareCount),
                  () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copied!'),
                      duration: Duration(seconds: 1),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.bookmark_border, size: 20),
                  color: Colors.grey[600],
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Saved!'),
                      duration: Duration(seconds: 1),
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

  Widget _mediaWidget(String url, String type, Map<String, dynamic> post) {
    final isVideo =
        type == 'video' ||
        url.toLowerCase().endsWith('.mp4') ||
        url.toLowerCase().endsWith('.mov');
    final isImage =
        type == 'image' ||
        url.toLowerCase().endsWith('.jpg') ||
        url.toLowerCase().endsWith('.jpeg') ||
        url.toLowerCase().endsWith('.png') ||
        url.toLowerCase().endsWith('.gif') ||
        url.toLowerCase().endsWith('.webp');

    if (isVideo) {
      return GestureDetector(
        onTap: () => _openFullPost(post),
        child: Container(
          height: 220,
          width: double.infinity,
          color: Colors.grey[900],
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (post['thumbnail']?.toString().isNotEmpty == true)
                Image.network(
                  post['thumbnail'].toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              Container(color: Colors.black.withValues(alpha: 0.35)),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.videocam, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Video',
                        style: TextStyle(color: Colors.white, fontSize: 11),
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

    if (isImage) {
      return GestureDetector(
        onTap: () => _openFullPost(post),
        child: ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Image.network(
            url,
            height: 240,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 120,
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
              ),
            ),
          ),
        ),
      );
    }

    // Generic file attachment
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.attach_file, color: Colors.deepPurple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  url.split('/').last,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  type.isNotEmpty ? type.toUpperCase() : 'FILE',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.deepPurple),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    Color color,
    String label,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    ),
  );

  void _searchByHashtag(String tag) {
    final clean = tag.replaceAll('#', '').trim();
    _searchCtrl.text = '#$clean';
    _onSearch('#$clean');
    setState(() {});
  }

  void _openFullPost(Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.97,
        minChildSize: 0.5,
        expand: false,
        builder: (_, sc) => _FullPostView(
          post: post,
          postService: _postService,
          commentService: CommentService(),
          scrollController: sc,
        ),
      ),
    );
  }

  void _showComments(Map<String, dynamic> post) => _openFullPost(post);

  // ─── Hashtags Tab ────────────────────────────────────────────────────────

  Widget _hashtagsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionHeader('Trending Hashtags', Icons.trending_up),
          const SizedBox(height: 12),
          if (_trendingHashtags.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No trending hashtags yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _trendingHashtags.take(20).map((h) {
                final tag = h['tag']?.toString() ?? '';
                final count = (h['count'] ?? 0) as int;
                return GestureDetector(
                  onTap: () => _searchByHashtag(tag),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.deepPurple, Colors.purple],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tag.startsWith('#') ? tag : '#$tag',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (count > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _fmt(count),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 24),
          _sectionHeader('Latest Posts', Icons.grid_on),
          const SizedBox(height: 8),
          ..._forYouPosts
              .take(5)
              .map((p) => _postCard(p as Map<String, dynamic>)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ─── People Tab ──────────────────────────────────────────────────────────

  Widget _peopleTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionHeader('Suggested for You', Icons.person_add),
          const SizedBox(height: 8),
          if (_suggestedUsers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No suggestions yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            ..._suggestedUsers.map((u) => _userTile(u)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _userTile(dynamic user) {
    final pic = user['profile_image']?.toString() ?? '';
    final isFollowing = user['is_following'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfilePage(
              userId: user['id'] as int,
              username: user['username']?.toString(),
            ),
          ),
        ),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.deepPurple,
          backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
          child: pic.isEmpty
              ? Text(
                  (user['username'] ?? 'U')[0].toString().toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                )
              : null,
        ),
        title: Text(
          user['username']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((user['full_name']?.toString() ?? '').isNotEmpty)
              Text(
                user['full_name'].toString(),
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            Text(
              '${_fmt((user['follower_count'] ?? 0) as int)} followers',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
        trailing: SizedBox(
          width: 90,
          child: isFollowing
              ? OutlinedButton(
                  onPressed: () async {
                    try {
                      await _userService.unfollowUser(user['id']);
                      if (mounted) setState(() => user['is_following'] = false);
                    } catch (_) {}
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Unfollow', style: TextStyle(fontSize: 12)),
                )
              : ElevatedButton(
                  onPressed: () async {
                    try {
                      await _userService.followUser(user['id']);
                      if (mounted) setState(() => user['is_following'] = true);
                    } catch (_) {}
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Follow', style: TextStyle(fontSize: 12)),
                ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) => Row(
    children: [
      Icon(icon, color: Colors.deepPurple, size: 20),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ],
  );

  // ─── Create Post (multi-media) ──────────────────────────────────────────

  void _showCreatePost() {
    final contentCtrl = TextEditingController();
    final hashtagCtrl = TextEditingController();
    // Each attachment: {file, url, type, name}
    final List<Map<String, dynamic>> attachments = [];
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          initialChildSize: 0.92,
          maxChildSize: 0.97,
          minChildSize: 0.5,
          expand: false,
          builder: (_, sc) => SingleChildScrollView(
            controller: sc,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Text(
                      'Create Post',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),

                // Content
                TextField(
                  controller: contentCtrl,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText:
                        "What's on your mind? Share a story, update, or thought...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    counterStyle: TextStyle(color: Colors.grey[400]),
                  ),
                ),
                const SizedBox(height: 10),

                // Hashtags
                TextField(
                  controller: hashtagCtrl,
                  decoration: InputDecoration(
                    hintText: '#dance #music #trending',
                    prefixIcon: const Icon(
                      Icons.tag,
                      color: Colors.deepPurple,
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    labelText: 'Add Hashtags',
                  ),
                ),
                const SizedBox(height: 16),

                // Media buttons row
                Row(
                  children: [
                    const Text(
                      'Add Media',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${attachments.length} added',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _mediaPickBtn(
                      Icons.photo_library,
                      'Photos',
                      Colors.green,
                      () async {
                        final picked = await _pickMultipleImages();
                        if (picked.isNotEmpty) {
                          setLocal(() => attachments.addAll(picked));
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _mediaPickBtn(
                      Icons.videocam,
                      'Video',
                      Colors.red,
                      () async {
                        final result = await _pickMedia(
                          ImageSource.gallery,
                          isVideo: true,
                        );
                        if (result != null) {
                          setLocal(
                            () => attachments.add({
                              'file': result.$1,
                              'url': result.$2,
                              'type': 'video',
                              'name': result.$2.split('/').last,
                            }),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _mediaPickBtn(
                      Icons.attach_file,
                      'File',
                      Colors.orange,
                      () async {
                        final result = await _pickAnyFile();
                        if (result != null) {
                          setLocal(
                            () => attachments.add({
                              'file': result.$1,
                              'url': result.$2,
                              'type': result.$3,
                              'name': result.$4,
                            }),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _mediaPickBtn(
                      Icons.link,
                      'URL',
                      Colors.deepPurple,
                      () async {
                        final url = await _promptUrl(ctx);
                        if (url != null && url.isNotEmpty) {
                          setLocal(
                            () => attachments.add({
                              'file': null,
                              'url': url,
                              'type': _guessType(url),
                              'name': url.split('/').last,
                            }),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Attachments preview grid
                if (attachments.isNotEmpty) ...[
                  const Text(
                    'Attachments',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                    itemCount: attachments.length,
                    itemBuilder: (_, i) {
                      final a = attachments[i];
                      final type = a['type']?.toString() ?? '';
                      final file = a['file'] as File?;
                      final url = a['url']?.toString() ?? '';
                      return Stack(
                        children: [
                          // Preview
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              color: Colors.grey[200],
                              child: _attachmentThumb(type, file, url),
                            ),
                          ),
                          // Type badge
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _typeColor(type).withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                type.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          // Remove button
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () =>
                                  setLocal(() => attachments.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                ],

                // Publish button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isUploading
                        ? null
                        : () async {
                            final text = contentCtrl.text.trim();
                            if (text.isEmpty && attachments.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Add content or media to post'),
                                ),
                              );
                              return;
                            }
                            setLocal(() => isUploading = true);
                            try {
                              // Upload all local files concurrently
                              final uploadedUrls = <String>[];
                              for (final a in attachments) {
                                final file = a['file'] as File?;
                                final url = a['url']?.toString() ?? '';
                                final type = a['type']?.toString() ?? '';
                                if (file != null && !kIsWeb) {
                                  String? uploaded;
                                  if (type == 'video') {
                                    uploaded = await UploadService()
                                        .uploadVideo(file);
                                  } else if (type == 'image') {
                                    uploaded = await UploadService()
                                        .uploadImage(file);
                                  } else {
                                    final res = await UploadService()
                                        .uploadFile(file.path);
                                    uploaded = res['url']?.toString();
                                  }
                                  if (uploaded != null && uploaded.isNotEmpty) {
                                    uploadedUrls.add(uploaded);
                                  }
                                } else if (url.isNotEmpty) {
                                  uploadedUrls.add(url);
                                }
                              }

                              // Use first attachment as primary media
                              String primaryUrl = uploadedUrls.isNotEmpty
                                  ? uploadedUrls.first
                                  : '';
                              String primaryType = attachments.isNotEmpty
                                  ? attachments.first['type']?.toString() ??
                                        'video'
                                  : 'video';

                              if (primaryUrl.isEmpty) {
                                primaryUrl =
                                    'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
                                primaryType = 'video';
                              }

                              final tags = hashtagCtrl.text.trim();
                              await _postService.createPost(
                                content: text,
                                mediaUrl: primaryUrl,
                                mediaType: primaryType,
                                hashTags: tags.isNotEmpty ? tags : null,
                              );

                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Posted successfully! 🎉'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                            } catch (e) {
                              setLocal(() => isUploading = false);
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isUploading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Uploading...',
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          )
                        : const Text(
                            'Publish Post',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pick multiple images at once
  Future<List<Map<String, dynamic>>> _pickMultipleImages() async {
    final list = <Map<String, dynamic>>[];
    try {
      if (Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS ||
          kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: kIsWeb,
        );
        if (result != null) {
          for (final f in result.files) {
            if (f.path != null) {
              list.add({
                'file': File(f.path!),
                'url': f.path!,
                'type': 'image',
                'name': f.name,
              });
            } else if (kIsWeb && f.bytes != null) {
              list.add({
                'file': null,
                'url':
                    'data:image/${f.extension};base64,${_bytesToBase64(f.bytes!)}',
                'type': 'image',
                'name': f.name,
              });
            }
          }
        }
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 1200,
        );
        for (final x in picked) {
          list.add({
            'file': File(x.path),
            'url': x.path,
            'type': 'image',
            'name': x.path.split('/').last,
          });
        }
      }
    } catch (_) {}
    return list;
  }

  /// Thumbnail for attachment preview grid
  Widget _attachmentThumb(String type, File? file, String url) {
    if (type == 'image') {
      if (file != null && !kIsWeb) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
      if (url.startsWith('http') || url.startsWith('data:')) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image, color: Colors.grey, size: 32),
        );
      }
    }
    if (type == 'video') {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40),
        ),
      );
    }
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconForType(type), color: Colors.deepPurple, size: 28),
            const SizedBox(height: 4),
            Text(
              type.toUpperCase(),
              style: TextStyle(color: Colors.grey[600], fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'image':
        return Colors.green;
      case 'video':
        return Colors.red;
      case 'pdf':
        return Colors.deepOrange;
      default:
        return Colors.orange;
    }
  }

  String _bytesToBase64(List<int> bytes) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buf = StringBuffer();
    for (int i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      buf.write(chars[(b0 >> 2) & 0x3F]);
      buf.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
      buf.write(
        i + 1 < bytes.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=',
      );
      buf.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
    }
    return buf.toString();
  }

  Widget _mediaPickBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<(File, String)?> _pickMedia(
    ImageSource source, {
    required bool isVideo,
  }) async {
    try {
      if (Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS ||
          kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: isVideo ? FileType.video : FileType.image,
          allowMultiple: false,
        );
        if (result != null &&
            result.files.isNotEmpty &&
            result.files.first.path != null) {
          final f = File(result.files.first.path!);
          return (f, result.files.first.path!);
        }
      } else {
        final picker = ImagePicker();
        final picked = isVideo
            ? await picker.pickVideo(
                source: source,
                maxDuration: const Duration(minutes: 5),
              )
            : await picker.pickImage(
                source: source,
                imageQuality: 85,
                maxWidth: 1200,
              );
        if (picked != null) return (File(picked.path), picked.path);
      }
    } catch (_) {}
    return null;
  }

  Future<(File, String, String, String)?> _pickAnyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      if (result != null &&
          result.files.isNotEmpty &&
          result.files.first.path != null) {
        final f = result.files.first;
        final ext = f.extension?.toLowerCase() ?? '';
        String type = 'file';
        if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext))
          type = 'image';
        else if (['mp4', 'mov', 'avi', 'webm'].contains(ext))
          type = 'video';
        else if (['pdf', 'doc', 'docx', 'txt'].contains(ext))
          type = ext;
        return (File(f.path!), f.path!, type, f.name);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _promptUrl(BuildContext ctx) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        title: const Text('Media URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/video.mp4',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dlg, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Use URL'),
          ),
        ],
      ),
    );
  }

  String _guessType(String url) {
    final l = url.toLowerCase();
    if (l.endsWith('.mp4') ||
        l.endsWith('.mov') ||
        l.endsWith('.webm') ||
        l.contains('video'))
      return 'video';
    if (l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.png') ||
        l.endsWith('.gif'))
      return 'image';
    return 'file';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'video':
        return Icons.videocam;
      case 'image':
        return Icons.image;
      case 'pdf':
        return Icons.picture_as_pdf;
      default:
        return Icons.insert_drive_file;
    }
  }
}

// ─── Expandable Text ────────────────────────────────────────────────────────

class _ExpandableText extends StatefulWidget {
  final String text;
  const _ExpandableText(this.text);
  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final short = widget.text.length > 150 && !_expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          short ? '${widget.text.substring(0, 150)}...' : widget.text,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        if (widget.text.length > 150)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Show less' : 'Show more',
              style: const TextStyle(
                color: Colors.deepPurple,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Full Post View (with comments) ─────────────────────────────────────────

class _FullPostView extends StatefulWidget {
  final Map<String, dynamic> post;
  final PostService postService;
  final CommentService commentService;
  final ScrollController scrollController;
  const _FullPostView({
    required this.post,
    required this.postService,
    required this.commentService,
    required this.scrollController,
  });
  @override
  State<_FullPostView> createState() => _FullPostViewState();
}

class _FullPostViewState extends State<_FullPostView> {
  final TextEditingController _commentCtrl = TextEditingController();
  List<dynamic> _comments = [];
  bool _loading = true;
  bool _isLiked = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post['is_liked'] == true;
    _likeCount = (widget.post['like_count'] ?? 0) as int;
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final list = await widget.commentService.getComments(widget.post['id']);
      if (mounted)
        setState(() {
          _comments = list;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike() async {
    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });
    try {
      if (_isLiked)
        await widget.postService.likePost(widget.post['id']);
      else
        await widget.postService.unlikePost(widget.post['id']);
    } catch (_) {
      setState(() {
        _isLiked = !_isLiked;
        _likeCount += _isLiked ? 1 : -1;
      });
    }
  }

  Future<void> _postComment() async {
    final t = _commentCtrl.text.trim();
    if (t.isEmpty) return;
    try {
      await widget.commentService.createComment(
        postId: widget.post['id'],
        content: t,
      );
      _commentCtrl.clear();
      await _loadComments();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = (widget.post['user'] as Map?) ?? {};
    final pic = user['profile_image']?.toString() ?? '';
    final username = user['username']?.toString() ?? 'user';
    final mediaUrl = widget.post['media_url']?.toString() ?? '';
    final mediaType = widget.post['media_type']?.toString() ?? '';
    final content = widget.post['content']?.toString() ?? '';
    final hashTags = widget.post['hash_tags']?.toString() ?? '';

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            children: [
              // Post header
              ListTile(
                leading: CircleAvatar(
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
                title: Text(
                  username,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(user['full_name']?.toString() ?? ''),
              ),
              // Media
              if (mediaUrl.isNotEmpty) _mediaPreview(mediaUrl, mediaType),
              // Content
              if (content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    content,
                    style: const TextStyle(fontSize: 15, height: 1.6),
                  ),
                ),
              // Hashtags
              if (hashTags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Text(
                    hashTags,
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              // Actions bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleLike,
                      child: Row(
                        children: [
                          Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? Colors.red : Colors.grey,
                            size: 22,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _fmt(_likeCount),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.comment_outlined,
                          color: Colors.grey,
                          size: 22,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_comments.length}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.share_outlined, size: 20),
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Link copied!'),
                              duration: Duration(seconds: 1),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Comments header
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Comments',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_comments.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No comments yet. Be the first!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ..._comments.map((c) {
                  final cu = (c['user'] as Map?) ?? {};
                  final cpic = cu['profile_image']?.toString() ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.deepPurple,
                      backgroundImage: cpic.isNotEmpty
                          ? NetworkImage(cpic)
                          : null,
                      child: cpic.isEmpty
                          ? Text(
                              (cu['username'] ?? 'U')[0]
                                  .toString()
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      cu['username']?.toString() ?? 'User',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(c['content']?.toString() ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite_border,
                          size: 14,
                          color: Colors.grey,
                        ),
                        Text(
                          ' ${c['like_count'] ?? 0}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 80),
            ],
          ),
        ),
        // Comment input
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 8,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.deepPurple,
                child: Text(
                  (AuthService().currentUser?['username'] ?? 'U')[0]
                      .toString()
                      .toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
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
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _postComment,
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
      ],
    );
  }

  Widget _mediaPreview(String url, String type) {
    final isVideo = type == 'video' || url.toLowerCase().endsWith('.mp4');
    final isImage =
        type == 'image' ||
        url.toLowerCase().endsWith('.jpg') ||
        url.toLowerCase().endsWith('.png') ||
        url.toLowerCase().endsWith('.jpeg');
    if (isVideo) {
      return Container(
        height: 220,
        color: Colors.grey[900],
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white, size: 64),
        ),
      );
    }
    if (isImage) {
      return Image.network(
        url,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Container(height: 100, color: Colors.grey[200]),
      );
    }
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.attach_file, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(url.split('/').last, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
