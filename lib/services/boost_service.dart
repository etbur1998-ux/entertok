import 'api_client.dart';

class BoostService {
  static final BoostService _instance = BoostService._internal();
  factory BoostService() => _instance;
  BoostService._internal();

  final ApiClient _api = ApiClient();

  static const double pricePerFollower = 2.00;
  static const double earnPerFollower = 1.70;
  static const double feePerFollower = 0.30;

  /// Create a new boost campaign — pays [targetFollowers] × 2 Birr
  Future<dynamic> createBoost(int targetFollowers) =>
      _api.post('/boost', body: {'target_followers': targetFollowers});

  /// List current user's campaigns
  Future<List<dynamic>> getMyBoosts() async {
    final r = await _api.get('/boost/my');
    return (r['campaigns'] ?? []) as List<dynamic>;
  }

  /// Stats: earnings from following boosted users + own campaigns
  Future<dynamic> getBoostStats() => _api.get('/boost/stats');

  /// Pause a campaign
  Future<void> pauseBoost(int id) => _api.post('/boost/$id/pause');

  /// Cancel a campaign (gets refund for unused followers)
  Future<dynamic> cancelBoost(int id) => _api.post('/boost/$id/cancel');

  /// List of active boosted users (discover who to follow for rewards)
  Future<List<dynamic>> getActiveBoostedUsers() async {
    final r = await _api.get('/boost/active');
    return (r['boosted_users'] ?? []) as List<dynamic>;
  }
}
