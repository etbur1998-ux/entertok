import 'api_client.dart';
export 'api_client.dart';

class PostService {
  final ApiClient _api = ApiClient();

  static final PostService _instance = PostService._internal();
  factory PostService() => _instance;
  PostService._internal();

  /// Resolves all media_url and profile_image fields in a post list
  static List<dynamic> _resolvePosts(dynamic raw) {
    final list = raw is List ? raw : <dynamic>[];
    return list.map((p) {
      if (p is! Map) return p;
      final post = Map<String, dynamic>.from(p);
      post['media_url'] = ApiClient.resolveUrl(post['media_url']?.toString());
      post['thumbnail'] = ApiClient.resolveUrl(post['thumbnail']?.toString());
      if (post['user'] is Map) {
        final u = Map<String, dynamic>.from(post['user'] as Map);
        u['profile_image'] = ApiClient.resolveUrl(
          u['profile_image']?.toString(),
        );
        post['user'] = u;
      }
      return post;
    }).toList();
  }

  Future<List<dynamic>> getFeed({int page = 1, int pageSize = 20}) async {
    final response = await _api.get(
      '/posts/feed',
      queryParams: {'page': page.toString(), 'page_size': pageSize.toString()},
    );
    return _resolvePosts(response['posts']);
  }

  Future<List<dynamic>> getTrending({int page = 1, int pageSize = 20}) async {
    final response = await _api.get(
      '/posts/trending',
      queryParams: {'page': page.toString(), 'page_size': pageSize.toString()},
    );
    return _resolvePosts(response['posts']);
  }

  Future<List<dynamic>> getUserPosts(
    int userId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _api.get(
      '/posts/user/$userId',
      queryParams: {'page': page.toString(), 'page_size': pageSize.toString()},
    );
    return _resolvePosts(response['posts']);
  }

  Future<Map<String, dynamic>> getPost(int postId) async {
    final r = await _api.get('/posts/$postId');
    return Map<String, dynamic>.from(r as Map);
  }

  Future<List<dynamic>> getPostsByHashtag(String hashtag) async {
    final response = await _api.get('/posts/hashtag/$hashtag');
    return _resolvePosts(response['posts']);
  }

  Future<List<dynamic>> getTrendingHashtags() async {
    try {
      final response = await _api.get('/posts/hashtags/trending');
      return response['hashtags'] is List ? response['hashtags'] as List : [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> createPost({
    String? content,
    required String mediaUrl,
    String? mediaType,
    String? thumbnail,
    int? duration,
    String? location,
    String? hashTags,
    String? mentionedUsers,
    bool? isPublic,
  }) async {
    final body = <String, dynamic>{'media_url': mediaUrl};
    if (content != null) body['content'] = content;
    if (mediaType != null) body['media_type'] = mediaType;
    if (thumbnail != null) body['thumbnail'] = thumbnail;
    if (duration != null) body['duration'] = duration;
    if (location != null) body['location'] = location;
    if (hashTags != null) body['hash_tags'] = hashTags;
    if (mentionedUsers != null) body['mentioned_users'] = mentionedUsers;
    if (isPublic != null) body['is_public'] = isPublic;
    return Map<String, dynamic>.from(
      await _api.post('/posts', body: body) as Map,
    );
  }

  Future<void> deletePost(int postId) async {
    await _api.delete('/posts/$postId');
  }

  Future<void> likePost(int postId) async {
    await _api.post('/posts/$postId/like');
  }

  Future<void> unlikePost(int postId) async {
    await _api.delete('/posts/$postId/like');
  }
}
