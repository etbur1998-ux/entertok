import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import 'message_page.dart';

/// Full user profile page — works for any user (own or others)
/// Shows: cover, avatar, bio, stats, posts grid with views/likes
class UserProfilePage extends StatefulWidget {
  final int userId;
  final String? username; // optional — shown while loading

  const UserProfilePage({super.key, required this.userId, this.username});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final UserService _userService = UserService();
  final PostService _postService = PostService();

  Map<String, dynamic>? _user;
  List<dynamic> _posts = [];
  List<dynamic> _followers = [];
  List<dynamic> _following = [];
  bool _isLoading = true;
  bool _isFollowing = false;

  bool get _isMyProfile => AuthService().currentUser?['id'] == widget.userId;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _userService.getUser(widget.userId),
        _postService.getUserPosts(widget.userId),
        _userService.getFollowers(widget.userId),
        _userService.getFollowing(widget.userId),
      ]);

      final user = results[0] as Map<String, dynamic>;
      final posts = results[1] as List;
      final followers = results[2] as List;
      final following = results[3] as List;

      // Check if current user is following this profile
      final myId = AuthService().currentUser?['id'];
      final isFollowing = followers.any((f) => f['id'] == myId);

      if (mounted) {
        setState(() {
          _user = user;
          _posts = posts;
          _followers = followers;
          _following = following;
          _isFollowing = isFollowing;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final was = _isFollowing;
    setState(() => _isFollowing = !was);
    try {
      if (was) {
        await _userService.unfollowUser(widget.userId);
        setState(() {
          if (_user != null) {
            _user!['follower_count'] =
                ((_user!['follower_count'] ?? 1) as int) - 1;
          }
        });
      } else {
        await _userService.followUser(widget.userId);
        setState(() {
          if (_user != null) {
            _user!['follower_count'] =
                ((_user!['follower_count'] ?? 0) as int) + 1;
          }
        });
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => _isFollowing = was);
    }
  }

  void _openMessage() {
    final user = _user;
    if (user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          name:
              user['full_name']?.toString() ??
              user['username']?.toString() ??
              'User',
          avatar: Colors.deepPurple,
          isOnline: user['is_online'] == true,
          receiverId: widget.userId,
          profileImage: user['profile_image']?.toString(),
        ),
      ),
    );
  }

  void _showFollowersList(List<dynamic> users, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: users.isEmpty
                  ? Center(
                      child: Text(
                        'No $title yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.separated(
                      controller: sc,
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final u = users[i];
                        final pic = u['profile_image']?.toString() ?? '';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple,
                            backgroundImage: pic.isNotEmpty
                                ? NetworkImage(pic)
                                : null,
                            child: pic.isEmpty
                                ? Text(
                                    (u['username'] ?? 'U')[0]
                                        .toString()
                                        .toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          title: Text(
                            u['full_name']?.toString() ??
                                u['username']?.toString() ??
                                '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '@${u['username'] ?? ''}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfilePage(
                                  userId: u['id'] as int,
                                  username: u['username']?.toString(),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? _buildLoadingState()
          : NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(child: _buildHeader()),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabDelegate(
                    TabBar(
                      controller: _tabCtrl,
                      labelColor: Colors.deepPurple,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.deepPurple,
                      tabs: const [
                        Tab(icon: Icon(Icons.grid_on), text: 'Posts'),
                        Tab(icon: Icon(Icons.videocam), text: 'Videos'),
                        Tab(icon: Icon(Icons.favorite_border), text: 'Liked'),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildGrid(_posts),
                  _buildGrid(
                    _posts.where((p) => p['media_type'] == 'video').toList(),
                  ),
                  _buildGrid(_posts), // liked — same posts for now
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingState() => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.white,
      title: Text(
        '@${widget.username ?? '...'}',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.black),
    ),
    body: const Center(child: CircularProgressIndicator()),
  );

  Widget _buildHeader() {
    final u = _user;
    if (u == null) return const SizedBox();

    final pic = u['profile_image']?.toString() ?? '';
    final cover = u['cover_image']?.toString() ?? '';
    final username = u['username']?.toString() ?? '';
    final fullName = u['full_name']?.toString() ?? '';
    final bio = u['bio']?.toString() ?? '';
    final location = u['location']?.toString() ?? '';
    final website = u['website']?.toString() ?? '';
    final postCount = (u['post_count'] ?? _posts.length) as int;
    final followerCount = (u['follower_count'] ?? _followers.length) as int;
    final followingCount = (u['following_count'] ?? _following.length) as int;
    final isVerified = u['is_verified'] == true;
    final isOnline = u['is_online'] == true;

    // Total stats from posts
    final totalViews = _posts.fold<int>(
      0,
      (s, p) => s + ((p['view_count'] ?? 0) as int),
    );
    final totalLikes = _posts.fold<int>(
      0,
      (s, p) => s + ((p['like_count'] ?? 0) as int),
    );

    return Column(
      children: [
        // Cover image
        Stack(
          children: [
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B2D8E), Color(0xFFEC4899)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: cover.isNotEmpty
                  ? Image.network(
                      ApiClient.resolveUrl(cover),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    )
                  : null,
            ),
            // Back button
            Positioned(
              top: 12,
              left: 8,
              child: SafeArea(
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            // Share
            Positioned(
              top: 12,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.share_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copied!'),
                      duration: Duration(seconds: 1),
                    ),
                  ),
                ),
              ),
            ),
            // Avatar
            Positioned(
              bottom: -36,
              left: 20,
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.deepPurple,
                      backgroundImage: pic.isNotEmpty
                          ? NetworkImage(ApiClient.resolveUrl(pic))
                          : null,
                      child: pic.isEmpty
                          ? Text(
                              username.isNotEmpty
                                  ? username[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (isOnline)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        width: 14,
                        height: 14,
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
          ],
        ),
        const SizedBox(height: 44),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + verified
              Row(
                children: [
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
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isVerified) ...[
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
                        if (isOnline)
                          const Row(
                            children: [
                              Icon(Icons.circle, color: Colors.green, size: 10),
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
                Text(bio, style: const TextStyle(fontSize: 14, height: 1.6)),
              ],
              if (location.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      location,
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
              ],
              if (website.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.link, size: 14, color: Colors.deepPurple),
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
              const SizedBox(height: 16),
              // Stats row — tappable
              Row(
                children: [
                  _statTile(_fmt(postCount), 'Posts', null),
                  _statDivider(),
                  _statTile(
                    _fmt(followerCount),
                    'Followers',
                    () => _showFollowersList(_followers, 'Followers'),
                  ),
                  _statDivider(),
                  _statTile(
                    _fmt(followingCount),
                    'Following',
                    () => _showFollowersList(_following, 'Following'),
                  ),
                  _statDivider(),
                  _statTile(_fmt(totalViews), 'Views', null),
                  _statDivider(),
                  _statTile(_fmt(totalLikes), 'Likes', null),
                ],
              ),
              const SizedBox(height: 16),
              // Action buttons
              if (_isMyProfile)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit Profile'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.deepPurple),
                          foregroundColor: Colors.deepPurple,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Link copied!'),
                              duration: Duration(seconds: 1),
                            ),
                          ),
                      icon: const Icon(Icons.share_outlined, size: 16),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _isFollowing
                          ? OutlinedButton.icon(
                              onPressed: _toggleFollow,
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
                              onPressed: _toggleFollow,
                              icon: const Icon(Icons.person_add, size: 16),
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openMessage,
                        icon: const Icon(Icons.message_outlined, size: 16),
                        label: const Text('Message'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepPurple,
                          side: const BorderSide(color: Colors.deepPurple),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statTile(String val, String label, VoidCallback? onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            val,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _statDivider() => Container(
    width: 1,
    height: 32,
    color: Colors.grey[300],
    margin: const EdgeInsets.symmetric(horizontal: 2),
  );

  // ─── Posts Grid ───────────────────────────────────────────────────────────

  Widget _buildGrid(List<dynamic> posts) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text('No content yet', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(1),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 0.7,
      ),
      itemCount: posts.length,
      itemBuilder: (_, i) => _postTile(posts[i]),
    );
  }

  Widget _postTile(dynamic post) {
    final mediaUrl = post['media_url']?.toString() ?? '';
    final thumb = post['thumbnail']?.toString() ?? '';
    final isVideo = post['media_type'] == 'video' || mediaUrl.endsWith('.mp4');
    final views = (post['view_count'] ?? 0) as int;
    final likes = (post['like_count'] ?? 0) as int;
    final comments = (post['comment_count'] ?? 0) as int;
    final imgUrl = thumb.isNotEmpty
        ? ApiClient.resolveUrl(thumb)
        : ApiClient.resolveUrl(mediaUrl);

    return GestureDetector(
      onTap: () => _showPostDetail(post),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail
          imgUrl.isNotEmpty && !isVideo
              ? Image.network(
                  imgUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _videoPlaceholder(),
                )
              : _videoPlaceholder(),
          // Video play icon
          if (isVideo)
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white70,
                size: 28,
              ),
            ),
          // Bottom stats
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility, color: Colors.white, size: 11),
                  const SizedBox(width: 2),
                  Text(
                    _fmt(views),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.favorite, color: Colors.white, size: 11),
                  const SizedBox(width: 2),
                  Text(
                    _fmt(likes),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.comment, color: Colors.white, size: 11),
                  const SizedBox(width: 2),
                  Text(
                    _fmt(comments),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoPlaceholder() => Container(
    color: Colors.grey[850],
    child: const Center(
      child: Icon(Icons.play_circle_fill, color: Colors.grey, size: 32),
    ),
  );

  void _showPostDetail(dynamic post) {
    final mediaUrl = post['media_url']?.toString() ?? '';
    final isVideo = post['media_type'] == 'video' || mediaUrl.endsWith('.mp4');
    final content = post['content']?.toString() ?? '';
    final views = (post['view_count'] ?? 0) as int;
    final likes = (post['like_count'] ?? 0) as int;
    final comments = (post['comment_count'] ?? 0) as int;
    final shares = (post['share_count'] ?? 0) as int;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
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
              // Media
              AspectRatio(
                aspectRatio: 9 / 16,
                child: isVideo
                    ? Container(
                        color: Colors.grey[900],
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 80,
                          ),
                        ),
                      )
                    : (ApiClient.resolveUrl(mediaUrl).isNotEmpty
                          ? Image.network(
                              ApiClient.resolveUrl(mediaUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _videoPlaceholder(),
                            )
                          : _videoPlaceholder()),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (content.isNotEmpty) ...[
                      Text(
                        content,
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Stats grid
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _postStat(
                            Icons.visibility,
                            Colors.blue,
                            _fmt(views),
                            'Views',
                          ),
                          _vLine(),
                          _postStat(
                            Icons.favorite,
                            Colors.red,
                            _fmt(likes),
                            'Likes',
                          ),
                          _vLine(),
                          _postStat(
                            Icons.comment,
                            Colors.deepPurple,
                            _fmt(comments),
                            'Comments',
                          ),
                          _vLine(),
                          _postStat(
                            Icons.share,
                            Colors.green,
                            _fmt(shares),
                            'Shares',
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
      ),
    );
  }

  Widget _postStat(IconData icon, Color color, String val, String label) =>
      Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            val,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        ],
      );

  Widget _vLine() => Container(width: 1, height: 40, color: Colors.grey[300]);
}

class _TabDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabDelegate(this.tabBar);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(color: Colors.white, child: tabBar);

  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  bool shouldRebuild(covariant _TabDelegate old) => false;
}
