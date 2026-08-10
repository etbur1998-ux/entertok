import 'api_client.dart';

class LiveService {
  final ApiClient _api = ApiClient();

  /// Start a new live stream
  Future<Map<String, dynamic>> startLive({
    required String title,
    String description = '',
    String thumbnailUrl = '',
  }) async {
    final response = await _api.post('/live/start', body: {
      'title': title,
      'description': description,
      'thumbnail_url': thumbnailUrl,
    });
    return response as Map<String, dynamic>;
  }

  /// End a live stream
  Future<void> endLive(int streamId) async {
    await _api.post('/live/$streamId/end');
  }

  /// Get all active live streams
  Future<List<dynamic>> getActiveLives() async {
    final response = await _api.get('/live');
    if (response is Map && response['streams'] != null) {
      return response['streams'] as List<dynamic>;
    }
    return [];
  }

  /// Get a single live stream
  Future<Map<String, dynamic>> getLiveStream(int streamId) async {
    final response = await _api.get('/live/$streamId');
    return response as Map<String, dynamic>;
  }

  /// Get comments for a live stream
  Future<List<dynamic>> getLiveComments(int streamId) async {
    final response = await _api.get('/live/$streamId/comments');
    if (response is Map && response['comments'] != null) {
      return response['comments'] as List<dynamic>;
    }
    return [];
  }

  /// Send a gift during a live stream
  Future<void> sendGift({
    required int streamId,
    required String giftType,
    required double giftValue,
  }) async {
    await _api.post('/live/$streamId/gift', body: {
      'gift_type': giftType,
      'gift_value': giftValue,
    });
  }
}
