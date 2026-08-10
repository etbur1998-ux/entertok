import 'api_client.dart';
export 'api_client.dart';

class CommentService {
  // Use singleton ApiClient
  final ApiClient _apiClient = ApiClient();

  // Singleton pattern
  static final CommentService _instance = CommentService._internal();
  factory CommentService() => _instance;
  CommentService._internal();

  // Get comments for a post
  Future<List<dynamic>> getComments(
    int postId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _apiClient.get(
        '/posts/$postId/comments',
        queryParams: {
          'page': page.toString(),
          'page_size': pageSize.toString(),
        },
      );
      return response['comments'] ?? [];
    } catch (_) {
      return [];
    }
  }

  // Create a comment
  Future<Map<String, dynamic>> createComment({
    required int postId,
    required String content,
    int? parentId,
  }) async {
    final body = <String, dynamic>{'content': content};

    if (parentId != null) {
      body['parent_id'] = parentId;
    }

    return await _apiClient.post('/posts/$postId/comments', body: body);
  }

  // Delete a comment
  Future<void> deleteComment(int commentId) async {
    await _apiClient.delete('/posts/comments/$commentId');
  }

  // Like a comment
  Future<void> likeComment(int commentId) async {
    await _apiClient.post('/posts/comments/$commentId/like');
  }

  // Unlike a comment
  Future<void> unlikeComment(int commentId) async {
    await _apiClient.delete('/posts/comments/$commentId/like');
  }
}
