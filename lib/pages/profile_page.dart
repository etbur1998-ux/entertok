import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';

// Helper function to get absolute URL from relative path
String _getAbsoluteUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return 'http://127.0.0.1:8080$url';
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Auth and services
  final AuthService _authService = AuthService();
  final PostService _postService = PostService();

  // User data from backend
  Map<String, dynamic>? _userData;
  List<dynamic> _userPosts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Get current user from auth service
      final user = await _authService.getCurrentUser();

      // Get user's posts
      final posts = await _postService.getUserPosts(user['id']);

      setState(() {
        _userData = user;
        _userPosts = posts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      // If error, try to use cached user data from auth service
      if (_authService.currentUser != null) {
        setState(() {
          _userData = _authService.currentUser;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          _userData?['username'] ?? '@username',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorView()
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(child: _buildProfileHeader()),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(
                      TabBar(
                        controller: _tabController,
                        labelColor: Colors.black,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Colors.black,
                        tabs: const [
                          Tab(icon: Icon(Icons.grid_on)),
                          Tab(icon: Icon(Icons.videocam)),
                          Tab(icon: Icon(Icons.favorite)),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildPostsGrid(),
                  _buildVideosGrid(),
                  _buildLikedGrid(),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('Error: $_error'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadUserData, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    final user = _userData;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile picture
          _buildProfileImage(user),
          const SizedBox(height: 12),
          // Username
          Text(
            '@${user?['username'] ?? 'username'}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (user != null &&
              user['full_name'] != null &&
              user['full_name'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              user['full_name'],
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 4),
          // Bio
          Text(
            user != null && user['bio'] != null
                ? user['bio'].toString()
                : 'No bio yet',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (user != null &&
              user['location'] != null &&
              user['location'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                Text(
                  user['location'].toString(),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ],
          if (user != null &&
              user['website'] != null &&
              user['website'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              user['website'].toString(),
              style: const TextStyle(color: Colors.blue, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem('Posts', (user?['post_count'] ?? 0).toString()),
              _buildStatItem(
                'Followers',
                _formatCount(user?['follower_count'] ?? 0),
              ),
              _buildStatItem(
                'Following',
                (user?['following_count'] ?? 0).toString(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Edit profile button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.grey),
                ),
                child: const Text('Edit Profile'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.grey),
                ),
                child: const Text('Share Profile'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  Widget _buildProfileImage(Map<String, dynamic>? user) {
    final profileImage = user?['profile_image'];
    final hasImage = profileImage != null && profileImage.toString().isNotEmpty;

    return CircleAvatar(
      radius: 50,
      backgroundColor: Colors.deepPurple,
      backgroundImage: hasImage ? NetworkImage(profileImage.toString()) : null,
      child: !hasImage
          ? const Icon(Icons.person, size: 50, color: Colors.white)
          : null,
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }

  Widget _buildVideosGrid() {
    if (_userPosts.isEmpty) {
      return _buildEmptyState('No videos yet');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _userPosts.length,
      itemBuilder: (context, index) {
        final post = _userPosts[index];
        return GestureDetector(
          onTap: () {},
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail or media
              if (post['thumbnail'] != null &&
                  post['thumbnail'].toString().isNotEmpty)
                Image.network(
                  post['thumbnail'],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.deepPurple,
                    child: const Icon(
                      Icons.play_circle_filled,
                      color: Colors.white,
                    ),
                  ),
                )
              else if (post['media_url'] != null &&
                  post['media_url'].toString().isNotEmpty)
                Image.network(
                  _getAbsoluteUrl(post['media_url']),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.deepPurple,
                    child: const Icon(
                      Icons.play_circle_filled,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Container(
                  color: Colors.deepPurple,
                  child: const Icon(
                    Icons.play_circle_filled,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              Positioned(
                bottom: 4,
                left: 4,
                child: Row(
                  children: [
                    const Icon(Icons.visibility, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      _formatCount(post['view_count'] ?? 0),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      _formatCount(post['like_count'] ?? 0),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostsGrid() {
    if (_userPosts.isEmpty) {
      return _buildEmptyState('No posts yet');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _userPosts.length,
      itemBuilder: (context, index) {
        final post = _userPosts[index];
        return GestureDetector(
          onTap: () {},
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Post image/media
              if (post['media_url'] != null &&
                  post['media_url'].toString().isNotEmpty)
                Image.network(
                  _getAbsoluteUrl(post['media_url']),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: Colors.blue),
                )
              else if (post['thumbnail'] != null &&
                  post['thumbnail'].toString().isNotEmpty)
                Image.network(
                  _getAbsoluteUrl(post['thumbnail']),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: Colors.blue),
                )
              else
                Container(color: Colors.blue),
              Positioned(
                bottom: 4,
                left: 4,
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      _formatCount(post['like_count'] ?? 0),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLikedGrid() {
    // For now, show the user's posts as liked (you can add a separate endpoint later)
    if (_userPosts.isEmpty) {
      return _buildEmptyState('No liked posts yet');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _userPosts.length,
      itemBuilder: (context, index) {
        final post = _userPosts[index];
        return GestureDetector(
          onTap: () {},
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (post['thumbnail'] != null &&
                  post['thumbnail'].toString().isNotEmpty)
                Image.network(
                  _getAbsoluteUrl(post['thumbnail']),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: Colors.amber),
                )
              else if (post['media_url'] != null &&
                  post['media_url'].toString().isNotEmpty)
                Image.network(
                  _getAbsoluteUrl(post['media_url']),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: Colors.amber),
                )
              else
                Container(color: Colors.amber),
              Positioned(
                bottom: 4,
                right: 4,
                child: Row(
                  children: [
                    const Icon(Icons.visibility, color: Colors.white, size: 10),
                    const SizedBox(width: 2),
                    Text(
                      _formatCount(post['view_count'] ?? 0),
                      style: const TextStyle(color: Colors.white, fontSize: 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate(this.tabBar);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: tabBar);
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}
