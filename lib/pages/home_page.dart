import 'dart:async';
import 'package:flutter/material.dart';
import '../services/post_service.dart';
import '../services/comment_service.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/realtime_service.dart';
import '../services/video_preload_manager.dart';
import '../widgets/tiktok_video_player.dart';
import 'upload_page.dart';
import 'live_page.dart';
import 'dating_page.dart';
import 'user_profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PageController _pageController = PageController(
    viewportFraction: 1.0,
    keepPage: true, // keep page position when navigating away and back
  );
  int _currentPage = 0;

  final PostService _postService = PostService();
  final CommentService _commentService = CommentService();
  final RealtimeService _realtimeService = RealtimeService();
  final VideoPreloadManager _preloadMgr = VideoPreloadManager();

  List<dynamic> _posts = [];
  final Set<int> _seenIds = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  static const int _pageSize = 15;
  String? _loadError;

  StreamSubscription? _newPostSub;
  StreamSubscription? _likeSub;
  StreamSubscription? _commentSub;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final auth = AuthService();
    if (!auth.isLoggedIn) await auth.init();
    await _realtimeService.connect();
    _subscribeWS();
    await _loadPosts(reset: true);
  }

  void _subscribeWS() {
    _newPostSub = _realtimeService.onNewPost.listen((post) {
      if (!mounted) return;
      final id = post['id'] as int?;
      if (id == null || _seenIds.contains(id)) return;
      _seenIds.add(id);
      final p = _resolvePost(Map<String, dynamic>.from(post as Map));
      setState(() => _posts.insert(0, p));
      // preload the new top video
      final url = p['media_url']?.toString() ?? '';
      if (url.isNotEmpty) _preloadMgr.preloadVideos([url], 0);
    });

    _likeSub = _realtimeService.onLikeUpdate.listen((u) {
      if (!mounted) return;
      final pid = u['post_id'];
      setState(() {
        for (int i = 0; i < _posts.length; i++) {
          if (_posts[i]['id'] == pid) {
            final p = Map<String, dynamic>.from(_posts[i] as Map);
            p['is_liked'] = u['is_liked'];
            p['like_count'] = u['like_count'] ?? 0;
            _posts[i] = p;
            break;
          }
        }
      });
    });

    _commentSub = _realtimeService.onCommentUpdate.listen((u) {
      if (!mounted) return;
      final pid = u['post_id'];
      setState(() {
        for (int i = 0; i < _posts.length; i++) {
          if (_posts[i]['id'] == pid) {
            final p = Map<String, dynamic>.from(_posts[i] as Map);
            p['comment_count'] = ((p['comment_count'] ?? 0) as int) + 1;
            _posts[i] = p;
            break;
          }
        }
      });
    });
  }

  Map<String, dynamic> _resolvePost(Map<String, dynamic> p) {
    p['media_url'] = _preloadMgr.resolveUrl(p['media_url']?.toString() ?? '');
    p['thumbnail'] = _preloadMgr.resolveUrl(p['thumbnail']?.toString() ?? '');
    if (p['user'] is Map) {
      final u = Map<String, dynamic>.from(p['user'] as Map);
      u['profile_image'] = _preloadMgr.resolveUrl(
        u['profile_image']?.toString() ?? '',
      );
      p['user'] = u;
    }
    return p;
  }

  Future<void> _loadPosts({bool reset = false}) async {
    if (!mounted) return;
    if (reset) {
      setState(() {
        _isLoading = true;
        _loadError = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final raw = await _postService.getFeed(page: _page, pageSize: _pageSize);
      final fresh = <dynamic>[];
      for (final item in raw) {
        final p = _resolvePost(Map<String, dynamic>.from(item as Map));
        final id = p['id'] as int?;
        if (id != null && !_seenIds.contains(id)) {
          _seenIds.add(id);
          fresh.add(p);
        }
      }

      if (mounted) {
        setState(() {
          if (reset) {
            _posts = fresh;
            _currentPage = 0;
          } else {
            _posts.addAll(fresh);
          }
          _hasMore = raw.length == _pageSize;
          _page++;
          _isLoading = false;
          _isLoadingMore = false;
        });
        // Preload first videos immediately
        final urls = _posts
            .map((p) => p['media_url']?.toString() ?? '')
            .where((u) => u.isNotEmpty)
            .toList();
        if (urls.isNotEmpty) _preloadMgr.preloadVideos(urls, 0);
        // Scroll back to top on reset
        if (reset && _pageController.hasClients && _currentPage != 0) {
          _pageController.jumpToPage(0);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    final urls = _posts
        .map((p) => p['media_url']?.toString() ?? '')
        .where((u) => u.isNotEmpty)
        .toList();
    _preloadMgr.preloadVideos(urls, index);
    // Load more when within 3 of end
    if (index >= _posts.length - 3) {
      _loadPosts();
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> post, int index) async {
    final isLiked = post['is_liked'] == true;
    setState(() {
      final p = Map<String, dynamic>.from(post);
      p['is_liked'] = !isLiked;
      p['like_count'] = ((post['like_count'] ?? 0) as int) + (isLiked ? -1 : 1);
      _posts[index] = p;
    });
    try {
      if (isLiked)
        await _postService.unlikePost(post['id']);
      else
        await _postService.likePost(post['id']);
    } catch (_) {
      if (mounted) {
        setState(() {
          final p = Map<String, dynamic>.from(_posts[index] as Map);
          p['is_liked'] = isLiked;
          p['like_count'] = (post['like_count'] ?? 0) as int;
          _posts[index] = p;
        });
      }
    }
  }

  Future<void> _followUser(dynamic post) async {
    final uid = post['user']?['id'];
    if (uid == null) return;
    try {
      await UserService().followUser(uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Following @${post['user']?['username'] ?? 'user'}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {}
  }

  void _openProfile(dynamic post) {
    final uid = post['user']?['id'];
    if (uid == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          userId: uid as int,
          username: post['user']?['username']?.toString(),
        ),
      ),
    );
  }

  void _showComments(dynamic post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => _CommentsSheet(
          postId: post['id'],
          commentService: _commentService,
          scrollController: sc,
        ),
      ),
    );
  }

  bool _isVideo(String? url) {
    if (url == null || url.isEmpty) return false;
    final l = url.toLowerCase();
    return l.endsWith('.mp4') ||
        l.endsWith('.mov') ||
        l.endsWith('.webm') ||
        l.contains('/video') ||
        l.contains('video');
  }

  void _onVideoCompleted() {
    if (_currentPage < _posts.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _newPostSub?.cancel();
    _likeSub?.cancel();
    _commentSub?.cancel();
    _realtimeService.disconnect();
    _preloadMgr.disposeAll();
    _pageController.dispose();
    super.dispose();
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_loadError != null && _posts.isEmpty)
            _buildEmpty()
          else if (_posts.isEmpty)
            _buildEmpty()
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
              onPageChanged: _onPageChanged,
              physics: const _FastPageScrollPhysics(),
              itemBuilder: (ctx, i) {
                if (i >= _posts.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: Colors.white54),
                    ),
                  );
                }
                final post = _posts[i] as Map<String, dynamic>;
                final url = post['media_url']?.toString() ?? '';
                final active = i == _currentPage;
                return _VideoPage(
                  key: ValueKey('post_${post['id']}_$i'),
                  post: post,
                  url: url,
                  isVideo: _isVideo(url),
                  isActive: active,
                  onVideoCompleted: _onVideoCompleted,
                  index: i,
                  onLike: () => _toggleLike(post, i),
                  onComment: () => _showComments(post),
                  onFollow: () => _followUser(post),
                  onProfile: () => _openProfile(post),
                  fmt: _fmt,
                );
              },
            ),
          // Top bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 0,
            right: 0,
            child: _topBar(),
          ),
        ],
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _ico(
          Icons.live_tv_rounded,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LivePage()),
          ).then((_) => _loadPosts(reset: true)),
        ),
        const SizedBox(width: 8),
        _ico(
          Icons.heart_broken_rounded,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DatingPage()),
          ),
        ),
        const SizedBox(width: 8),
        _ico(
          Icons.upload_rounded,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UploadPage()),
          ).then((_) => _loadPosts(reset: true)),
        ),
        const SizedBox(width: 8),
        _ico(Icons.refresh_rounded, () => _loadPosts(reset: true)),
      ],
    ),
  );

  Widget _ico(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.video_library_outlined, size: 72, color: Colors.grey[600]),
        const SizedBox(height: 16),
        Text(
          _loadError != null ? 'Could not load videos' : 'No videos yet',
          style: const TextStyle(color: Colors.white70, fontSize: 18),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _loadPosts(reset: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
}

// ─── Fast scroll physics — snaps immediately, no over-bounce ─────────────────
class _FastPageScrollPhysics extends PageScrollPhysics {
  const _FastPageScrollPhysics() : super(parent: const ClampingScrollPhysics());
  @override
  _FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _FastPageScrollPhysics();
  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 60, stiffness: 120, damping: 1.2);
}

// ─── Single video page widget (keeps itself alive) ────────────────────────────
class _VideoPage extends StatefulWidget {
  final Map<String, dynamic> post;
  final String url;
  final bool isVideo;
  final bool isActive;
  final int index;
  final VoidCallback onVideoCompleted;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onFollow;
  final VoidCallback onProfile;
  final String Function(int) fmt;

  const _VideoPage({
    super.key,
    required this.post,
    required this.url,
    required this.isVideo,
    required this.isActive,
    required this.index,
    required this.onVideoCompleted,
    required this.onLike,
    required this.onComment,
    required this.onFollow,
    required this.onProfile,
    required this.fmt,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final post = widget.post;
    final user = (post['user'] as Map?) ?? {};
    final pic = user['profile_image']?.toString() ?? '';
    final liked = post['is_liked'] == true;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video or image
        if (widget.url.isNotEmpty && widget.isVideo)
          TikTokVideoPlayer(
            videoUrl: widget.url,
            index: widget.index,
            isActive: widget.isActive,
            onVideoCompleted: widget.onVideoCompleted,
          )
        else
          _placeholder(post),

        // Bottom gradient
        const Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 240,
          child: _Gradient(),
        ),

        // Right action bar — RepaintBoundary isolates like/comment count repaints
        Positioned(
          right: 8,
          bottom: 100,
          child: RepaintBoundary(child: _rightBar(post, user, pic, liked)),
        ),

        // Bottom info — RepaintBoundary isolates text repaints
        Positioned(
          left: 14,
          right: 80,
          bottom: 24,
          child: RepaintBoundary(child: _bottomInfo(post, user)),
        ),
      ],
    );
  }

  Widget _placeholder(Map<String, dynamic> post) {
    final thumb = post['thumbnail']?.toString() ?? '';
    final user = (post['user'] as Map?) ?? {};
    return Container(
      color: Colors.grey[900],
      child: thumb.isNotEmpty
          ? Image.network(
              thumb,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(user),
            )
          : _fallback(user),
    );
  }

  Widget _fallback(Map user) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.play_circle_fill, size: 80, color: Colors.deepPurple),
        const SizedBox(height: 12),
        Text(
          user['username']?.toString() ?? '',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    ),
  );

  Widget _rightBar(
    Map<String, dynamic> post,
    Map user,
    String pic,
    bool liked,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar + follow
        Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: widget.onProfile,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.deepPurple,
                backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                child: pic.isEmpty
                    ? Text(
                        (user['username'] ?? 'U')[0].toString().toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            Positioned(
              bottom: -8,
              child: GestureDetector(
                onTap: widget.onFollow,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _ab(
          liked ? Icons.favorite : Icons.favorite_border,
          liked ? Colors.red : Colors.white,
          widget.fmt((post['like_count'] ?? 0) as int),
          widget.onLike,
        ),
        const SizedBox(height: 16),
        _ab(
          Icons.comment_rounded,
          Colors.white,
          widget.fmt((post['comment_count'] ?? 0) as int),
          widget.onComment,
        ),
        const SizedBox(height: 16),
        _ab(
          Icons.share_rounded,
          Colors.white,
          widget.fmt((post['share_count'] ?? 0) as int),
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied!'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _ab(Icons.bookmark_border_rounded, Colors.white, '', () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved!'),
              duration: Duration(seconds: 1),
            ),
          );
        }),
      ],
    );
  }

  Widget _ab(IconData icon, Color color, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Icon(
              icon,
              color: color,
              size: 30,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _bottomInfo(Map<String, dynamic> post, Map user) {
    const sh = [Shadow(color: Colors.black87, blurRadius: 8)];
    return GestureDetector(
      onTap: widget.onProfile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((user['full_name']?.toString() ?? '').isNotEmpty)
            Text(
              user['full_name'].toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                shadows: sh,
              ),
            ),
          Text(
            '@${user['username'] ?? 'user'}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              shadows: sh,
            ),
          ),
          if ((post['content']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              post['content'].toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                shadows: sh,
              ),
            ),
          ],
          if ((post['hash_tags']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              post['hash_tags'].toString(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                shadows: sh,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Bottom gradient ──────────────────────────────────────────────────────────
class _Gradient extends StatelessWidget {
  const _Gradient();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
      ),
    ),
  );
}

// ─── Comments Sheet ───────────────────────────────────────────────────────────
class _CommentsSheet extends StatefulWidget {
  final int postId;
  final CommentService commentService;
  final ScrollController scrollController;
  const _CommentsSheet({
    required this.postId,
    required this.commentService,
    required this.scrollController,
  });
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _ctrl = TextEditingController();
  List<dynamic> _comments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.commentService.getComments(widget.postId);
      if (mounted)
        setState(() {
          _comments = list;
          _isLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      await widget.commentService.createComment(
        postId: widget.postId,
        content: text,
      );
      _ctrl.clear();
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        const Text(
          'Comments',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Divider(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _comments.isEmpty
              ? const Center(
                  child: Text(
                    'No comments yet. Be the first!',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: _comments.length,
                  itemBuilder: (_, i) {
                    final c = _comments[i];
                    final u = (c['user'] as Map?) ?? {};
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        u['username']?.toString() ?? 'User',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(c['content']?.toString() ?? ''),
                    );
                  },
                ),
        ),
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
              Expanded(
                child: TextField(
                  controller: _ctrl,
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
                onTap: _post,
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
}
