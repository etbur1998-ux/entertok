import 'api_client.dart';
export 'api_client.dart';

class UserService {
  final ApiClient _apiClient = ApiClient();

  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  Future<Map<String, dynamic>> getUser(int userId) async {
    return await _apiClient.get('/users/$userId');
  }

  Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? bio,
    String? phone,
    String? website,
    String? location,
    String? profileImage,
    String? coverImage,
    String? gender,
    bool? isPrivate,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (bio != null) body['bio'] = bio;
    if (phone != null) body['phone'] = phone;
    if (website != null) body['website'] = website;
    if (location != null) body['location'] = location;
    if (profileImage != null) body['profile_image'] = profileImage;
    if (coverImage != null) body['cover_image'] = coverImage;
    if (gender != null) body['gender'] = gender;
    if (isPrivate != null) body['is_private'] = isPrivate;

    return await _apiClient.put('/users/profile', body: body);
  }

  Future<void> followUser(int userId) async {
    await _apiClient.post('/users/$userId/follow');
  }

  Future<void> unfollowUser(int userId) async {
    await _apiClient.delete('/users/$userId/follow');
  }

  Future<List<dynamic>> getFollowers(int userId, {int page = 1, int pageSize = 20}) async {
    final response = await _apiClient.get('/users/$userId/followers', queryParams: {
      'page': page.toString(),
      'page_size': pageSize.toString(),
    });
    return response['followers'] ?? [];
  }

  Future<List<dynamic>> getFollowing(int userId, {int page = 1, int pageSize = 20}) async {
    final response = await _apiClient.get('/users/$userId/following', queryParams: {
      'page': page.toString(),
      'page_size': pageSize.toString(),
    });
    return response['following'] ?? [];
  }

  Future<List<dynamic>> searchUsers(String query, {int page = 1, int pageSize = 20}) async {
    final response = await _apiClient.get('/users/search', queryParams: {
      'q': query,
      'page': page.toString(),
      'page_size': pageSize.toString(),
    });
    return response['users'] ?? [];
  }

  Future<List<dynamic>> getSuggestions({int limit = 10}) async {
    final response = await _apiClient.get('/users/suggestions', queryParams: {
      'limit': limit.toString(),
    });
    return response['users'] ?? [];
  }
}