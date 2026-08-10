import 'api_client.dart';
export 'api_client.dart';

class MessageService {
  // Use singleton ApiClient - no need for setToken as it shares the same instance
  final ApiClient _apiClient = ApiClient();

  // Singleton pattern
  static final MessageService _instance = MessageService._internal();
  factory MessageService() => _instance;
  MessageService._internal();

  // Get all conversations
  Future<List<dynamic>> getConversations({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _apiClient.get(
      '/messages/conversations',
      queryParams: {'page': page.toString(), 'page_size': pageSize.toString()},
    );
    return response['conversations'];
  }

  // Get messages in a conversation
  Future<List<dynamic>> getMessages(
    int conversationId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _apiClient.get(
      '/messages/conversations/$conversationId/messages',
      queryParams: {'page': page.toString(), 'page_size': pageSize.toString()},
    );
    return response['messages'];
  }

  // Send a message
  Future<Map<String, dynamic>> sendMessage({
    required int receiverId,
    required String content,
    String? mediaUrl,
    String? mediaType,
  }) async {
    final body = <String, dynamic>{
      'receiver_id': receiverId,
      'content': content,
    };

    if (mediaUrl != null) body['media_url'] = mediaUrl;
    if (mediaType != null) body['media_type'] = mediaType;

    return await _apiClient.post('/messages', body: body);
  }

  // Get unread message count
  Future<int> getUnreadCount() async {
    final response = await _apiClient.get('/messages/unread');
    return response['unread_count'];
  }

  // Delete a message
  Future<void> deleteMessage(int messageId) async {
    await _apiClient.delete('/messages/$messageId');
  }

  // Update a message
  Future<void> updateMessage(int messageId, String content) async {
    await _apiClient.put('/messages/$messageId', body: {'content': content});
  }

  // ==================== Group Methods ====================

  // Get all groups current user belongs to
  Future<List<dynamic>> getUserGroups() async {
    final response = await _apiClient.get('/groups');
    return (response['groups'] ?? []) as List<dynamic>;
  }

  // Create a new group
  Future<Map<String, dynamic>> createGroup({
    required String groupName,
    required List<int> members,
    String? groupAvatar,
    String? groupDesc,
  }) async {
    final body = <String, dynamic>{'group_name': groupName, 'members': members};
    if (groupAvatar != null) body['group_avatar'] = groupAvatar;
    if (groupDesc != null) body['group_desc'] = groupDesc;
    return await _apiClient.post('/groups/create', body: body);
  }

  // Get group info
  Future<Map<String, dynamic>> getGroup(int groupId) async {
    return await _apiClient.get('/groups/$groupId');
  }

  // Update group info
  Future<Map<String, dynamic>> updateGroup(
    int groupId, {
    String? groupName,
    String? groupAvatar,
  }) async {
    final body = <String, dynamic>{};
    if (groupName != null) body['group_name'] = groupName;
    if (groupAvatar != null) body['group_avatar'] = groupAvatar;

    return await _apiClient.put('/groups/$groupId', body: body);
  }

  // Add members to a group
  Future<Map<String, dynamic>> addGroupMembers(
    int groupId,
    List<int> members,
  ) async {
    return await _apiClient.post(
      '/groups/$groupId/members',
      body: {'members': members},
    );
  }

  // Remove member from group
  Future<void> removeGroupMember(int groupId, int memberId) async {
    await _apiClient.delete('/groups/$groupId/members/$memberId');
  }

  // Leave a group
  Future<void> leaveGroup(int groupId) async {
    await _apiClient.delete('/groups/$groupId');
  }

  // Get group members
  Future<List<dynamic>> getGroupMembers(int groupId) async {
    final response = await _apiClient.get('/groups/$groupId/members');
    return response is List ? response : [];
  }

  // Get group messages
  Future<List<dynamic>> getGroupMessages(
    int groupId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _apiClient.get(
      '/groups/$groupId/messages',
      queryParams: {'page': page.toString(), 'page_size': pageSize.toString()},
    );
    return response['messages'];
  }

  // Send a group message
  Future<Map<String, dynamic>> sendGroupMessage({
    required int groupId,
    required String content,
    String? mediaUrl,
    String? mediaType,
  }) async {
    final body = <String, dynamic>{'content': content};

    if (mediaUrl != null) body['media_url'] = mediaUrl;
    if (mediaType != null) body['media_type'] = mediaType;

    return await _apiClient.post('/groups/$groupId/messages', body: body);
  }
}
