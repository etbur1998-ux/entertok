import 'api_client.dart';

class StoryService {
  final ApiClient _api = ApiClient();

  /// Get stories from followed users
  Future<List<dynamic>> getStories() async {
    try {
      final response = await _api.get('/stories');
      if (response is Map && response['story_groups'] != null) {
        return response['story_groups'] as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Get stories for a specific user
  Future<List<dynamic>> getUserStories(int userId) async {
    try {
      final response = await _api.get('/stories/user/$userId');
      if (response is Map && response['stories'] != null) {
        return response['stories'] as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Create a new story
  Future<Map<String, dynamic>> createStory({
    required String mediaUrl,
    String mediaType = 'image',
    String caption = '',
    int duration = 5,
  }) async {
    final response = await _api.post('/stories', body: {
      'media_url': mediaUrl,
      'media_type': mediaType,
      'caption': caption,
      'duration': duration,
    });
    return response as Map<String, dynamic>;
  }

  /// Mark a story as viewed
  Future<void> viewStory(int storyId) async {
    try {
      await _api.post('/stories/$storyId/view');
    } catch (_) {}
  }

  /// Delete a story
  Future<void> deleteStory(int storyId) async {
    await _api.delete('/stories/$storyId');
  }
}
