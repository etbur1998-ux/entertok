import 'api_client.dart';

class AdService {
  final ApiClient _api = ApiClient();

  /// Get ads for the feed (injected between videos)
  Future<List<dynamic>> getFeedAds() async {
    try {
      final response = await _api.get('/ads/feed');
      if (response is Map && response['ads'] != null) {
        return response['ads'] as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Track an ad impression
  Future<void> trackImpression(int adId) async {
    try {
      await _api.post('/ads/$adId/impression');
    } catch (_) {}
  }

  /// Track an ad click
  Future<void> trackClick(int adId) async {
    try {
      await _api.post('/ads/$adId/click');
    } catch (_) {}
  }

  /// Create a new ad campaign
  Future<Map<String, dynamic>> createAd({
    required String title,
    String description = '',
    String mediaUrl = '',
    String mediaType = 'image',
    String targetUrl = '',
    double budget = 0,
    String targetAge = '',
    String targetGender = '',
    String targetInterests = '',
  }) async {
    final response = await _api.post(
      '/ads',
      body: {
        'title': title,
        'description': description,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'target_url': targetUrl,
        'budget': budget,
        'target_age': targetAge,
        'target_gender': targetGender,
        'target_interests': targetInterests,
        'start_date': DateTime.now().toIso8601String(),
      },
    );
    return response as Map<String, dynamic>;
  }

  /// Get my ads
  Future<List<dynamic>> getMyAds() async {
    final response = await _api.get('/ads/my');
    if (response is Map && response['ads'] != null) {
      return response['ads'] as List<dynamic>;
    }
    return [];
  }

  /// Get ad stats
  Future<Map<String, dynamic>> getAdStats(int adId) async {
    final response = await _api.get('/ads/$adId/stats');
    return response as Map<String, dynamic>;
  }

  /// Update an ad
  Future<void> updateAd(int adId, {String? status, double? budget}) async {
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status;
    if (budget != null) body['budget'] = budget;
    await _api.put('/ads/$adId', body: body);
  }

  /// Delete an ad
  Future<void> deleteAd(int adId) async {
    await _api.delete('/ads/$adId');
  }
}
