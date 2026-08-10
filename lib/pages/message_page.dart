import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../services/upload_service.dart';
import '../services/user_service.dart';
import '../services/websocket_service.dart';
import 'call_page.dart';
import 'group_call_page.dart';
import 'groups_page.dart';

class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // Services for backend API
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();

  // State for conversations
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;

  // Available users for new message
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoadingUsers = false;
  bool _isLoadingSuggestions = false;

  List<Map<String, dynamic>> _filteredConversations = [];

  // Debounce timer for user search
  Timer? _debounceTimer;
  String _currentSearchQuery = '';

  // WebSocket subscriptions
  StreamSubscription<Map<String, dynamic>>? _chatSub;
  StreamSubscription<Map<String, dynamic>>? _groupSub;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _setupWebSocket();
  }

  void _setupWebSocket() {
    final ws = WebSocketService();
    _chatSub = ws.onChatMessage.listen((message) {
      if (!mounted) return;
      _handleIncomingMessage(message, isGroup: false);
    });
    _groupSub = ws.onGroupMessage.listen((message) {
      if (!mounted) return;
      _handleIncomingMessage(message, isGroup: true);
    });
  }

  void _handleIncomingMessage(
    Map<String, dynamic> message, {
    required bool isGroup,
  }) {
    // Reload conversations list in real-time
    _loadConversations();
  }

  // Show conversation options (long press on conversation tile)
  void _showConversationOptions(
    BuildContext context,
    Map<String, dynamic> chat,
  ) {
    final int? conversationId = chat['id'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // View profile
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('View Profile'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to profile
              },
            ),
            // Delete conversation
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Conversation',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteConversation(conversationId);
              },
            ),
            // Mute notifications
            ListTile(
              leading: const Icon(Icons.notifications_off),
              title: const Text('Mute Notifications'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications muted')),
                );
              },
            ),
            // Search in conversation
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search in Conversation'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Open search in chat
              },
            ),
          ],
        ),
      ),
    );
  }

  // Delete a conversation
  Future<void> _deleteConversation(int? conversationId) async {
    if (conversationId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text(
          'Are you sure you want to delete this conversation? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                // TODO: Call backend to delete conversation
                setState(() {
                  _conversations.removeWhere((c) => c['id'] == conversationId);
                  _filteredConversations.removeWhere(
                    (c) => c['id'] == conversationId,
                  );
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Conversation deleted')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadConversations() async {
    try {
      setState(() => _isLoading = true);
      final conversations = await _messageService.getConversations();
      setState(() {
        _conversations = List<Map<String, dynamic>>.from(conversations);
        _filteredConversations = List.from(_conversations);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _conversations = [];
        _filteredConversations = [];
      });
    }
  }

  void _searchUsers(String query) {
    _currentSearchQuery = query;

    // Cancel previous timer
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      // Load suggested users when search is cleared
      _loadSuggestedUsers();
      return;
    }

    setState(() {
      _isLoadingUsers = true;
    });

    // Live search with minimal debounce (150ms for faster response)
    _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
      try {
        // Check if this query is still current
        if (_currentSearchQuery != query) return;

        print('Searching users with query: $query');
        final users = await _userService.searchUsers(query);

        // Check if this result is still for the current query
        if (_currentSearchQuery != query) return;

        print('Found users: $users');
        setState(() {
          _availableUsers = List<Map<String, dynamic>>.from(
            users.map(
              (u) => {
                'name': u['full_name'] ?? u['username'] ?? 'User',
                'username': u['username'],
                'bio': u['bio'] ?? '',
                'avatar': Colors.pink,
                'online': false,
                'id': u['id'],
              },
            ),
          );
          _isLoadingUsers = false;
        });
      } catch (e) {
        print('Search error: $e');
        if (_currentSearchQuery == query) {
          setState(() {
            _isLoadingUsers = false;
          });
        }
      }
    });
  }

  Future<void> _loadSuggestedUsers() async {
    setState(() {
      _isLoadingSuggestions = true;
    });

    try {
      print('Loading suggested users...');
      final users = await _userService.getSuggestions();
      print('Suggested users: $users');
      setState(() {
        _availableUsers = List<Map<String, dynamic>>.from(
          users.map(
            (u) => {
              'name': u['full_name'] ?? u['username'] ?? 'User',
              'username': u['username'],
              'bio': u['bio'] ?? '',
              'avatar': Colors.pink,
              'online': false,
              'id': u['id'],
            },
          ),
        );
        _isLoadingSuggestions = false;
        _isLoadingUsers = false;
      });
    } catch (e) {
      print('Load suggestions error: $e');
      setState(() {
        _isLoadingSuggestions = false;
        _isLoadingUsers = false;
        _availableUsers = [];
      });
    }
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _groupSub?.cancel();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filteredConversations = List.from(_conversations);
        _availableUsers = [];
        _isLoadingUsers = false;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset search state when returning to this page
    if (!_isSearching && _filteredConversations.isEmpty) {
      _filteredConversations = List.from(_conversations);
    }
  }

  void _showCreateChatSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'New Message',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            // New Message option
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_add, color: Colors.deepPurple),
              ),
              title: const Text('New Message'),
              subtitle: const Text('Send a message to someone'),
              onTap: () {
                Navigator.pop(context);
                _showNewMessageDialog();
              },
            ),
            // Create Group option
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group_add, color: Colors.green),
              ),
              title: const Text('Create Group'),
              subtitle: const Text('Start a group conversation'),
              onTap: () {
                Navigator.pop(context);
                _showCreateGroupDialog();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showNewMessageDialog() {
    final TextEditingController searchController = TextEditingController();
    // Load suggested users when opening dialog
    _loadSuggestedUsers();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Message'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search users...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    // Live search on every keystroke
                    _searchUsers(value);
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: (_isLoadingUsers || _isLoadingSuggestions)
                      ? const Center(child: CircularProgressIndicator())
                      : (_availableUsers.isEmpty
                            ? Center(
                                child: Text(
                                  searchController.text.isEmpty
                                      ? 'No suggested users'
                                      : 'No users found',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (searchController.text.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 8,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        'Suggested Users',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  if (searchController.text.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 8,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        'Search Results',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: _availableUsers.length,
                                      itemBuilder: (context, index) {
                                        final user = _availableUsers[index];
                                        return ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor:
                                                user['avatar'] ?? Colors.pink,
                                            child: Text(
                                              (user['name'] ?? 'U')[0]
                                                  .toString()
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          title: Text(user['name'] ?? 'User'),
                                          subtitle: Text(
                                            user['username'] ??
                                                user['bio'] ??
                                                '',
                                          ),
                                          onTap: () {
                                            Navigator.pop(context);
                                            // Navigate to chat with this user
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (ctx) =>
                                                    ChatDetailPage(
                                                      name:
                                                          user['name'] ??
                                                          'User',
                                                      avatar:
                                                          user['avatar'] ??
                                                          Colors.pink,
                                                      isOnline:
                                                          user['online'] ??
                                                          false,
                                                      receiverId: user['id'],
                                                      profileImage:
                                                          user['profile_image'],
                                                    ),
                                              ),
                                            ).then((_) => _loadConversations());
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              )),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateGroupDialog() {
    // Use the new GroupsPage sheet for consistency
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateGroupSheet(
        onCreated: (g) async {
          await _loadConversations();
          if (g['id'] != null && mounted) {
            final gid = g['id'] as int;
            final name = g['group_name']?.toString() ?? 'Group';
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatDetailPage(
                  conversationId: gid,
                  name: name,
                  avatar: Colors.deepPurple,
                  isOnline: true,
                  isGroup: true,
                ),
              ),
            ).then((_) => _loadConversations());
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search users to message...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                style: const TextStyle(color: Colors.black),
                onChanged: (value) {
                  // Search for users to message
                  _searchUsers(value);
                  setState(() {});
                },
              )
            : const Text(
                'Messages',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          // Groups button
          IconButton(
            icon: const Icon(Icons.group, color: Colors.deepPurple),
            tooltip: 'Groups',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GroupsPage()),
            ),
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          // Show user search results when searching
          if (_isSearching && _searchController.text.isNotEmpty)
            Expanded(
              child: _isLoadingUsers
                  ? const Center(child: CircularProgressIndicator())
                  : _availableUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No users found',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _availableUsers.length,
                      itemBuilder: (context, index) {
                        final user = _availableUsers[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: user['avatar'] ?? Colors.pink,
                            child: Text(
                              (user['name'] ?? 'U')[0].toString().toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(user['name'] ?? 'User'),
                          subtitle: Text(user['username'] ?? ''),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => ChatDetailPage(
                                  name: user['name'] ?? 'User',
                                  avatar: user['avatar'] ?? Colors.pink,
                                  isOnline: user['online'] ?? false,
                                  receiverId: user['id'],
                                ),
                              ),
                            ).then((_) => _loadConversations());
                            _toggleSearch();
                          },
                        );
                      },
                    ),
            )
          else
            // Show conversations list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredConversations.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      itemCount: _filteredConversations.length,
                      itemBuilder: (context, index) {
                        final chat = _filteredConversations[index];
                        return _buildConversationTile(context, chat);
                      },
                    ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurple,
        onPressed: _showCreateChatSheet,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No conversations found',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for a different name or message',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(
    BuildContext context,
    Map<String, dynamic> chat,
  ) {
    // Handle both API data and mock data
    final bool hasUnread = (chat['unread_count'] ?? chat['unread'] ?? 0) > 0;

    // Get user info from either 'user' (API) or direct fields (mock)
    final user = chat['user'] ?? {};
    final String name =
        user['full_name'] ?? user['username'] ?? chat['name'] ?? 'User';
    final String? profileImage = user['profile_image'];
    final int? conversationId = chat['id'];
    final int? otherUserId = user['id'];

    // Get message preview
    final String messagePreview = chat['last_message'] ?? chat['message'] ?? '';

    // Format time
    String timeStr = '';
    if (chat['last_message_at'] != null) {
      final dateTime = DateTime.tryParse(chat['last_message_at'].toString());
      if (dateTime != null) {
        final now = DateTime.now();
        if (dateTime.day == now.day &&
            dateTime.month == now.month &&
            dateTime.year == now.year) {
          timeStr =
              '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
        } else {
          timeStr = '${dateTime.month}/${dateTime.day}';
        }
      }
    } else {
      timeStr = chat['time'] ?? '';
    }

    return InkWell(
      onTap: () {
        final bool isGroupChat =
            chat['is_group'] == true ||
            (chat['group_name'] != null &&
                chat['group_name'].toString().isNotEmpty);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(
              name: name,
              avatar: chat['avatar'] ?? Colors.deepPurple,
              isOnline: chat['online'] ?? false,
              conversationId: conversationId,
              receiverId: isGroupChat ? null : otherUserId,
              profileImage: isGroupChat ? null : profileImage,
              isGroup: isGroupChat,
            ),
          ),
        ).then((_) => _loadConversations());
      },
      onLongPress: () {
        _showConversationOptions(context, chat);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: hasUnread
              ? Colors.deepPurple.withValues(alpha: 0.05)
              : Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            // Avatar with online indicator
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor:
                      chat['avatar'] ??
                      (chat['is_group'] == true || chat['group_name'] != null
                          ? Colors.deepPurple
                          : Colors.pink),
                  backgroundImage:
                      (profileImage != null &&
                          profileImage.isNotEmpty &&
                          chat['is_group'] != true)
                      ? NetworkImage(profileImage)
                      : null,
                  child:
                      (profileImage == null ||
                          profileImage.isEmpty ||
                          chat['is_group'] == true ||
                          chat['group_name'] != null)
                      ? (chat['is_group'] == true || chat['group_name'] != null
                            ? const Icon(
                                Icons.group,
                                color: Colors.white,
                                size: 22,
                              )
                            : Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ))
                      : null,
                ),
                if (chat['online'] == true)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Message content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name at top
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Last message and time at bottom
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          messagePreview,
                          style: TextStyle(
                            color: hasUnread
                                ? Colors.black87
                                : Colors.grey[600],
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Time at bottom right
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: hasUnread
                              ? Colors.deepPurple
                              : Colors.grey[500],
                          fontSize: 12,
                          fontWeight: hasUnread
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Unread badge
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.deepPurple,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${chat['unread_count'] ?? chat['unread'] ?? 0}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Chat Detail Page
class ChatDetailPage extends StatefulWidget {
  final String name;
  final Color avatar;
  final bool isOnline;
  final int? conversationId;
  final int? receiverId;
  final String? profileImage;
  final bool isGroup;

  const ChatDetailPage({
    super.key,
    required this.name,
    required this.avatar,
    required this.isOnline,
    this.conversationId,
    this.receiverId,
    this.profileImage,
    this.isGroup = false,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSearchingInChat = false;
  final TextEditingController _chatSearchController = TextEditingController();

  // Services
  final MessageService _messageService = MessageService();
  final WebSocketService _wsService = WebSocketService();

  // Loaded from AuthService in initState
  int _currentUserId = 1;
  String _currentUserName = 'You';

  bool get _isGroup => widget.isGroup || widget.name.contains('members');

  // State
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _filteredMessages = [];
  bool _isLoading = true;
  bool _isTyping = false;
  bool _isPartnerOnline = false;
  bool _showEmojiPicker = false;

  // Reply / edit
  Map<String, dynamic>? _replyToMessage;
  int? _editingMessageId;
  // editing text is held in _messageController

  late ScrollController _scrollController;
  Timer? _typingDebounce;
  Timer? _pollTimer; // fallback polling when WS delivery uncertain

  // WebSocket subscriptions — stored so we can cancel on dispose
  StreamSubscription<Map<String, dynamic>>? _chatMsgSub;
  StreamSubscription<Map<String, dynamic>>? _groupMsgSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<Map<String, dynamic>>? _onlineSub;
  StreamSubscription<Map<String, dynamic>>? _readSub;
  StreamSubscription<Map<String, dynamic>>? _groupCallInviteSub;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Load real current user ID from AuthService
    final authUser = AuthService().currentUser;
    if (authUser != null) {
      _currentUserId = (authUser['id'] as num?)?.toInt() ?? 1;
      _currentUserName =
          authUser['full_name']?.toString() ??
          authUser['username']?.toString() ??
          'You';
    }
    _isPartnerOnline = widget.isOnline;
    _loadMessages();
    _setupWebSocket();
    // Poll every 3s as fallback for when WS delivery is uncertain
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && widget.conversationId != null) {
        _silentRefresh();
      }
    });
  }

  // Refresh messages without showing loading spinner
  Future<void> _silentRefresh() async {
    if (widget.conversationId == null) return;
    try {
      final msgs = _isGroup
          ? await _messageService.getGroupMessages(widget.conversationId!)
          : await _messageService.getMessages(widget.conversationId!);
      if (!mounted) return;

      // All real DB IDs currently in our list (temp IDs are > 1_000_000_000_000)
      final shownIds = _messages
          .where((m) => ((m['id'] as num?)?.toInt() ?? 0) < 1000000000000)
          .map((m) => (m['id'] as num).toInt())
          .toSet();

      // Only process messages the server has that we don't yet show
      final newOnes = msgs.where((m) {
        final id = (m['id'] as num?)?.toInt() ?? 0;
        return id > 0 && !shownIds.contains(id);
      }).toList();

      if (newOnes.isEmpty) return;

      setState(() {
        for (final m in newOnes) {
          final cnt = m['content']?.toString() ?? '';
          // Remove matching optimistic (tempId > 1e12, same content)
          _messages.removeWhere(
            (e) =>
                ((e['id'] as num?)?.toInt() ?? 0) > 1000000000000 &&
                e['content'] == cnt,
          );
          _messages.add({
            'id': m['id'],
            'content': cnt,
            'sender': m['sender'],
            'isMe':
                m['sender'] != null &&
                (m['sender']['id'] as num?)?.toInt() == _currentUserId,
            'time': _formatTime(m['created_at']),
            'created_at': m['created_at'],
            'media_url': m['media_url'],
            'media_type': m['media_type'],
            'is_read': m['is_read'] ?? false,
            'is_group': m['is_group'] ?? false,
            'edited': m['edited'] ?? false,
          });
        }
        // Keep chronological order
        _messages.sort((a, b) {
          final ta = DateTime.tryParse(a['created_at']?.toString() ?? '');
          final tb = DateTime.tryParse(b['created_at']?.toString() ?? '');
          if (ta == null || tb == null) return 0;
          return ta.compareTo(tb);
        });
        _filteredMessages = List.from(_messages);
      });
      _scrollToBottom();
    } catch (_) {}
  }

  void _setupWebSocket() {
    // ── Direct messages ──────────────────────────────────────────────────
    // ── Direct messages ──────────────────────────────────────────────────
    _chatMsgSub = _wsService.onChatMessage.listen((message) {
      final senderId = (message['sender_id'] as num?)?.toInt();
      final receiverId = (message['receiver_id'] as num?)?.toInt();

      // Accept if this message is between current user and the chat partner
      final isRelevant =
          (senderId == _currentUserId && receiverId == widget.receiverId) ||
          (senderId == widget.receiverId && receiverId == _currentUserId);

      if (!isRelevant) return;

      final msgId = message['id'] ?? DateTime.now().millisecondsSinceEpoch;

      if (!mounted) return;
      setState(() {
        // Try to match with an optimistic bubble first
        final existingMeMsgIdx = _messages.indexWhere(
          (m) =>
              m['isMe'] == true &&
              (m['is_delivered'] == false || m['_uploading'] == true) &&
              m['content'] == (message['content'] ?? ''),
        );

        if (existingMeMsgIdx != -1) {
          _messages[existingMeMsgIdx]['id'] = msgId;
          _messages[existingMeMsgIdx]['is_delivered'] = true;
          _messages[existingMeMsgIdx]['_uploading'] = false;
          if (message['media_url'] != null) {
            _messages[existingMeMsgIdx]['media_url'] = message['media_url'];
          }
          _messages[existingMeMsgIdx]['time'] = _formatTime(
            message['created_at'] ?? DateTime.now().toIso8601String(),
          );
          _filteredMessages = List.from(_messages);
          return;
        }

        // Deduplicate — compare both as integers
        final msgIdInt = (msgId is num)
            ? msgId.toInt()
            : (int.tryParse(msgId.toString()) ?? 0);
        if (_messages.any((m) {
          final eid =
              (m['id'] as num?)?.toInt() ??
              (int.tryParse(m['id']?.toString() ?? '') ?? -1);
          return eid == msgIdInt && msgIdInt > 0;
        }))
          return;
        final newMsg = {
          'id': msgId,
          'content': message['content'] ?? '',
          'isMe': senderId == _currentUserId,
          'time': _formatTime(
            message['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          ),
          'created_at':
              message['created_at'] ?? DateTime.now().toIso8601String(),
          'is_delivered': true,
          'is_read': false,
          'media_url': message['media_url'],
          'media_type': message['media_type'],
          'sender': {
            'id': senderId,
            'full_name': message['sender_name'] ?? '',
            'username': message['sender_name'] ?? '',
            'profile_image': message['sender_avatar'] ?? '',
          },
        };
        _messages.add(newMsg);
        _filteredMessages.add(newMsg);
      });
      _scrollToBottom();

      // Mark as read if message was sent to us
      if (senderId == widget.receiverId && message['id'] != null) {
        _wsService.sendMessageRead(
          messageId: message['id'] as int,
          conversationId: widget.conversationId ?? 0,
        );
      }
    });

    // ── Group messages ────────────────────────────────────────────────────
    _groupMsgSub = _wsService.onGroupMessage.listen((message) {
      final groupId = (message['group_id'] as num?)?.toInt();
      if (!_isGroup || groupId != widget.conversationId) return;
      final senderId = (message['sender_id'] as num?)?.toInt();
      final msgId = message['id'] ?? DateTime.now().millisecondsSinceEpoch;

      if (!mounted) return;
      setState(() {
        // Try to match with an optimistic bubble first
        final existingMeMsgIdx = _messages.indexWhere(
          (m) =>
              m['isMe'] == true &&
              (m['is_delivered'] == false || m['_uploading'] == true) &&
              m['content'] == (message['content'] ?? ''),
        );

        if (existingMeMsgIdx != -1) {
          _messages[existingMeMsgIdx]['id'] = msgId;
          _messages[existingMeMsgIdx]['is_delivered'] = true;
          _messages[existingMeMsgIdx]['_uploading'] = false;
          if (message['media_url'] != null) {
            _messages[existingMeMsgIdx]['media_url'] = message['media_url'];
          }
          _messages[existingMeMsgIdx]['time'] = _formatTime(
            message['created_at'] ?? DateTime.now().toIso8601String(),
          );
          _filteredMessages = List.from(_messages);
          return;
        }

        if (_messages.any((m) => m['id'] == msgId)) return;
        _messages.add({
          'id': msgId,
          'content': message['content'] ?? '',
          'isMe': senderId == _currentUserId,
          'time': _formatTime(
            message['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          ),
          'created_at':
              message['created_at'] ?? DateTime.now().toIso8601String(),
          'is_delivered': true,
          'is_group': true,
          'sender': {
            'id': senderId,
            'full_name': message['sender_name'] ?? 'Unknown',
            'profile_image': message['sender_avatar'] ?? '',
          },
        });
        _filteredMessages = List.from(_messages);
      });
      _scrollToBottom();
    });

    // ── Typing indicator ──────────────────────────────────────────────────
    _typingSub = _wsService.onTyping.listen((typing) {
      final fromId = (typing['from_user_id'] as num?)?.toInt();
      if (fromId != widget.receiverId) return;
      if (!mounted) return;
      setState(() {
        _isTyping = typing['is_typing'] as bool? ?? false;
      });
      // Auto-clear after 3 seconds even if no "stop typing" arrives
      if (_isTyping) {
        _typingDebounce?.cancel();
        _typingDebounce = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _isTyping = false);
        });
      }
    });

    // ── Online status ─────────────────────────────────────────────────────
    _onlineSub = _wsService.onOnlineStatus.listen((status) {
      final uid = (status['user_id'] as num?)?.toInt();
      if (uid != widget.receiverId) return;
      if (!mounted) return;
      setState(() {
        _isPartnerOnline = status['is_online'] as bool? ?? false;
      });
    });

    // ── Read receipts ─────────────────────────────────────────────────────
    _readSub = _wsService.onMessageRead.listen((data) {
      final msgId = data['message_id'];
      if (!mounted) return;
      setState(() {
        for (final msg in _messages) {
          if (msg['id'] == msgId) msg['is_read'] = true;
        }
      });
    });

    // ── Incoming call (WebRTC offer while in this chat) ───────────────────
    _wsService.onWebRTCOffer.listen((data) {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId != widget.receiverId || !mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.deepPurple,
                backgroundImage: (widget.profileImage?.isNotEmpty == true)
                    ? NetworkImage(widget.profileImage!)
                    : null,
                child:
                    (widget.profileImage == null ||
                        widget.profileImage!.isEmpty)
                    ? Text(
                        widget.name.isNotEmpty
                            ? widget.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 14),
              Text(
                widget.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '📞 Incoming call',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _wsService.webrtcHangup(fromId!);
              },
              icon: const Icon(Icons.call_end, color: Colors.red),
              label: const Text('Decline', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _handleIncomingCallOffer(data, CallType.audio);
              },
              icon: const Icon(Icons.call),
              label: const Text('Accept'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    });

    // ── Incoming group call invite ─────────────────────────────────────────
    _groupCallInviteSub = _wsService.onGroupCallInvite.listen((data) {
      if (!mounted) return;
      final groupId = (data['group_id'] as num?)?.toInt();
      if (groupId == null) return;
      // If already in the call page, ignore
      final groupName = data['group_name']?.toString() ?? 'Group Call';
      final callType = data['call_type']?.toString() ?? 'video';
      final callerUserId = (data['caller_id'] as num?)?.toInt();
      final callerName = data['caller_name']?.toString() ?? 'Someone';
      final callerAvatar = data['caller_avatar']?.toString() ?? '';
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupCallPage(
            groupId: groupId,
            groupName: groupName,
            callType: callType == 'video'
                ? GroupCallType.video
                : GroupCallType.audio,
            isCaller: false,
            callerUserId: callerUserId,
            callerName: callerName,
            callerAvatar: callerAvatar,
          ),
        ),
      );
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Calls ─────────────────────────────────────────────────────────────────

  void _startCall(CallType type) {
    // Group call
    if (_isGroup && widget.conversationId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallPage(
            groupId: widget.conversationId!,
            groupName: widget.name,
            callType: type == CallType.video
                ? GroupCallType.video
                : GroupCallType.audio,
            isCaller: true,
          ),
        ),
      );
      return;
    }
    // 1-to-1 call
    if (widget.receiverId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallPage(
          peerId: widget.receiverId!,
          peerName: widget.name,
          peerAvatar: widget.profileImage,
          callType: type,
          isIncoming: false,
          shouldOffer: true,
        ),
      ),
    );
  }

  /// Called when we receive a WebRTC offer from the peer while in chat
  void _handleIncomingCallOffer(Map<String, dynamic> data, CallType type) {
    final fromId = (data['from_user_id'] as num?)?.toInt();
    if (fromId != widget.receiverId) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallPage(
          peerId: fromId!,
          peerName: widget.name,
          peerAvatar: widget.profileImage,
          callType: type,
          isIncoming: true,
          shouldOffer: false,
        ),
      ),
    );
  }

  // Find conversation by receiver and load messages
  Future<void> _findOrLoadByReceiver() async {
    if (widget.receiverId == null) return;
    try {
      setState(() => _isLoading = true);
      // Get conversations and find the one with this receiver
      final convos = await _messageService.getConversations();
      for (final conv in convos) {
        final user = conv['user'] ?? {};
        if ((user['id'] as num?)?.toInt() == widget.receiverId) {
          final convId = (conv['id'] as num?)?.toInt();
          if (convId != null) {
            final msgs = await _messageService.getMessages(convId);
            if (mounted) {
              setState(() {
                _messages = List<Map<String, dynamic>>.from(
                  msgs.map(
                    (m) => {
                      'id': m['id'],
                      'content': m['content'],
                      'sender': m['sender'],
                      'isMe':
                          (m['sender'] != null &&
                          (m['sender']['id'] as num?)?.toInt() ==
                              _currentUserId),
                      'time': _formatTime(m['created_at']),
                      'created_at': m['created_at'],
                      'media_url': m['media_url'],
                      'media_type': m['media_type'],
                      'is_read': m['is_read'] ?? false,
                    },
                  ),
                );
                _filteredMessages = List.from(_messages);
                _isLoading = false;
              });
              _scrollToBottom();
            }
            return;
          }
        }
      }
      // No existing conversation — show empty (messages will appear via WS)
      if (mounted)
        setState(() {
          _isLoading = false;
          _messages = [];
          _filteredMessages = [];
        });
    } catch (e) {
      debugPrint('_findOrLoadByReceiver error: $e');
      if (mounted)
        setState(() {
          _isLoading = false;
          _messages = [];
          _filteredMessages = [];
        });
    }
  }

  Future<void> _loadMessages() async {
    // If we have a conversation ID, load from backend
    if (widget.conversationId != null) {
      try {
        setState(() => _isLoading = true);

        List<dynamic> messages;

        if (_isGroup) {
          messages = await _messageService.getGroupMessages(
            widget.conversationId!,
          );
          // Load group members (stored locally for display)
          try {
            await _messageService.getGroupMembers(widget.conversationId!);
          } catch (_) {}
        } else {
          messages = await _messageService.getMessages(widget.conversationId!);
        }

        setState(() {
          _messages = List<Map<String, dynamic>>.from(
            messages.map(
              (m) => {
                'id': m['id'],
                'content': m['content'],
                'sender': m['sender'],
                // isMe = message was sent BY the current logged-in user
                'isMe':
                    (m['sender'] != null &&
                    (m['sender']['id'] as num?)?.toInt() == _currentUserId),
                'time': _formatTime(m['created_at']),
                'created_at': m['created_at'],
                'media_url': m['media_url'],
                'media_type': m['media_type'],
                'is_read': m['is_read'] ?? false,
                'is_group': m['is_group'] ?? false,
              },
            ),
          );
          _filteredMessages = List.from(_messages);
          _isLoading = false;
        });
        // Scroll to bottom after load
        _scrollToBottom();
      } catch (e) {
        debugPrint('_loadMessages error: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _messages = [];
            _filteredMessages = [];
          });
          // If conversation load failed but we have receiver, try to find conversation
          if (widget.receiverId != null) {
            _findOrLoadByReceiver();
          }
        }
      }
    } else if (widget.receiverId != null) {
      // No conversation ID yet — load by finding the conversation for this receiver
      _findOrLoadByReceiver();
    } else {
      setState(() {
        _messages = [];
        _filteredMessages = [];
        _isLoading = false;
      });
    }
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '';
    final dateTime = DateTime.tryParse(createdAt.toString());
    if (dateTime == null) return '';
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text.trim();
    _messageController.clear();

    // Capture reply before clearing state
    final replyMsg = _replyToMessage;
    // replyToId will be used when WS send is re-enabled
    // ignore: unused_local_variable
    final replyToId = (replyMsg?['id'] as num?)?.toInt();

    // Stop typing immediately
    _typingDebounce?.cancel();
    if (widget.receiverId != null) {
      _wsService.sendTyping(toUserId: widget.receiverId!, isTyping: false);
    }

    // Clear reply/edit state
    setState(() {
      _replyToMessage = null;
      _editingMessageId = null;
    });

    // ── Group message ────────────────────────────────────────────────────
    if (_isGroup && widget.conversationId != null) {
      try {
        _wsService.sendGroupMessage(
          groupId: widget.conversationId!,
          content: content,
          conversationId: widget.conversationId,
        );

        await _messageService.sendGroupMessage(
          groupId: widget.conversationId!,
          content: content,
        );

        setState(() {
          _messages.add({
            'id': DateTime.now().millisecondsSinceEpoch,
            'content': content,
            'isMe': true,
            'sender': {'id': _currentUserId, 'full_name': _currentUserName},
            'time': 'Now',
            'created_at': DateTime.now().toIso8601String(),
            'is_delivered': false,
            'is_group': true,
            if (replyMsg != null) 'reply_to': replyMsg,
          });
          _filteredMessages = List.from(_messages);
        });
        _scrollToBottom();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
      return;
    }

    // ── Direct message ───────────────────────────────────────────────────
    if (widget.receiverId != null) {
      final tempId = DateTime.now().millisecondsSinceEpoch;

      // Add optimistic bubble immediately
      setState(() {
        _messages.add({
          'id': tempId,
          'content': content,
          'isMe': true,
          'time': _formatTime(DateTime.now().toIso8601String()),
          'created_at': DateTime.now().toIso8601String(),
          'is_delivered': false,
          'is_read': false,
          if (replyMsg != null) 'reply_to': replyMsg,
        });
        _filteredMessages = List.from(_messages);
      });
      _scrollToBottom();

      try {
        // Persist via REST (backend hub delivers to receiver via WS)
        final result = await _messageService.sendMessage(
          receiverId: widget.receiverId!,
          content: content,
        );

        // Replace temp ID with real DB ID
        final realId = result['data']?['id'] ?? result['id'];
        if (realId != null && mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['id'] == tempId);
            if (idx != -1) {
              _messages[idx]['id'] = realId;
              _messages[idx]['is_delivered'] = true;
              _filteredMessages = List.from(_messages);
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
        }
      }
      return;
    }

    // ── No conversation yet ───────────────────────────────────────────────
    setState(() {
      _messages.add({
        'content': content,
        'isMe': true,
        'time': 'Now',
        'created_at': DateTime.now().toIso8601String(),
        if (replyMsg != null) 'reply_to': replyMsg,
      });
      _filteredMessages = List.from(_messages);
    });
    _scrollToBottom();
  }

  // Show message options bottom sheet
  void _showMessageOptions(Map<String, dynamic> message) {
    final bool isMe = message['isMe'] ?? false;
    final String messageText = message['content'] ?? message['message'] ?? '';
    final bool hasMedia = (message['media_url'] as String?)?.isNotEmpty == true;

    // Quick emoji reactions row
    const reactions = ['❤️', '😂', '😮', '😢', '👍', '🙏'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A1A2E)
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Quick emoji reactions ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: reactions
                    .map(
                      (emoji) => GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _wsService.sendMessageReaction(
                            messageId: message['id'] as int? ?? 0,
                            emoji: emoji,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Reacted $emoji'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

            const Divider(height: 1),

            // ── Message preview snippet ───────────────────────────
            if (messageText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    messageText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
              ),

            // ── Action tiles ──────────────────────────────────────
            _optionTile(ctx, Icons.reply, 'Reply', Colors.deepPurple, () {
              setState(() => _replyToMessage = message);
              Future.delayed(const Duration(milliseconds: 100), () {
                FocusScope.of(context).requestFocus(FocusNode());
              });
            }),

            _optionTile(ctx, Icons.copy, 'Copy text', Colors.blue, () {
              Clipboard.setData(ClipboardData(text: messageText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            }),

            _optionTile(ctx, Icons.forward, 'Forward', Colors.orange, () {
              _forwardMessage(message);
            }),

            if (isMe && !hasMedia) ...[
              _optionTile(ctx, Icons.edit_outlined, 'Edit', Colors.amber, () {
                _editMessage(message);
              }),
            ],

            if (isMe)
              _optionTile(
                ctx,
                Icons.delete_outline,
                'Delete',
                Colors.red,
                () => _deleteMessage(message),
                textColor: Colors.red,
              ),

            if (!isMe)
              _optionTile(ctx, Icons.flag_outlined, 'Report', Colors.grey, () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report submitted')),
                );
              }),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Builds a single action tile for the message options sheet
  Widget _optionTile(
    BuildContext ctx,
    IconData icon,
    String label,
    Color color,
    VoidCallback action, {
    Color? textColor,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    title: Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: textColor,
      ),
    ),
    onTap: () {
      Navigator.pop(ctx);
      action();
    },
  );

  // Edit a message
  // Cancel reply
  void _cancelReply() {
    setState(() => _replyToMessage = null);
  }

  void _editMessage(Map<String, dynamic> message) {
    final messageId = message['id'] as int?;
    final messageText =
        (message['content'] ?? message['message'] ?? '') as String;
    setState(() {
      _editingMessageId = messageId;
      _messageController.text = messageText;
    });
  }

  Future<void> _saveEditedMessage() async {
    if (_editingMessageId == null || _messageController.text.trim().isEmpty)
      return;

    final newContent = _messageController.text.trim();

    try {
      await _messageService.updateMessage(_editingMessageId!, newContent);

      setState(() {
        for (final list in [_messages, _filteredMessages]) {
          final idx = list.indexWhere((m) => m['id'] == _editingMessageId);
          if (idx != -1) {
            list[idx]['content'] = newContent;
            list[idx]['edited'] = true;
          }
        }
        _editingMessageId = null;
      });
      _messageController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message edited ✓'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to edit: $e')));
      }
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final int? messageId = message['id'];
    if (messageId == null) return;

    // Show quick confirm snackbar
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Delete this message?'),
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.red[700],
        action: SnackBarAction(
          label: 'DELETE',
          textColor: Colors.white,
          onPressed: () async {
            try {
              await _messageService.deleteMessage(messageId);
              if (mounted) {
                setState(() {
                  _messages.removeWhere((m) => m['id'] == messageId);
                  _filteredMessages.removeWhere((m) => m['id'] == messageId);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message deleted'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
              }
            }
          },
        ),
      ),
    );
  }

  // Forward a message — shows conversation picker
  void _forwardMessage(Map<String, dynamic> message) {
    final String content = message['content'] ?? '';
    final String? mediaUrl = message['media_url'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ForwardMessageSheet(
        content: content,
        mediaUrl: mediaUrl,
        mediaType: message['media_type'] as String?,
        currentConversationId: widget.conversationId,
        onForwarded: (targetUserId, targetName) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Forwarded to $targetName ✓'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickFile() async {
    // Show media picker sheet
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMediaOption(
                    ctx,
                    Icons.photo_library,
                    'Gallery',
                    Colors.purple,
                    () => _pickImage(),
                  ),
                  _buildMediaOption(
                    ctx,
                    Icons.videocam,
                    'Video',
                    Colors.red,
                    () => _pickVideo(),
                  ),
                  _buildMediaOption(
                    ctx,
                    Icons.attach_file,
                    'File',
                    Colors.blue,
                    () => _pickAnyFile(),
                  ),
                  _buildMediaOption(
                    ctx,
                    Icons.audiotrack,
                    'Audio',
                    Colors.green,
                    () => _pickAudio(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaOption(
    BuildContext ctx,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          _showImagePreviewBeforeSend(file.path!, file.name);
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          _showSendFileDialog(file.name, file.path!, file.extension ?? 'mp4');
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickAnyFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          _showSendFileDialog(file.name, file.path!, file.extension ?? 'file');
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          _showSendFileDialog(file.name, file.path!, file.extension ?? 'audio');
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showImagePreviewBeforeSend(String filePath, String fileName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    child: kIsWeb
                        ? const Center(
                            child: Icon(
                              Icons.image,
                              color: Colors.white,
                              size: 80,
                            ),
                          )
                        : Image.file(
                            File(filePath),
                            fit: BoxFit.contain,
                            width: double.infinity,
                          ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Add a caption...',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (caption) {
                        Navigator.pop(ctx);
                        _sendMediaMessage(
                          filePath,
                          fileName,
                          'image',
                          caption: caption,
                        );
                      },
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _sendMediaMessage(filePath, fileName, 'image');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.deepPurple,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMediaMessage(
    String filePath,
    String fileName,
    String mediaType, {
    String caption = '',
  }) async {
    if (widget.receiverId == null) return;

    // Add optimistic bubble immediately
    final tempId = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _messages.add({
        'id': tempId,
        'content': caption.isEmpty ? '📷 Image' : caption,
        'isMe': true,
        'time': 'Now',
        'created_at': DateTime.now().toIso8601String(),
        'media_url': kIsWeb ? '' : 'file://$filePath',
        'media_type': mediaType,
        '_uploading': true,
      });
      _filteredMessages = List.from(_messages);
    });

    try {
      final uploadService = UploadService();
      final uploadResult = await uploadService.uploadFile(filePath);
      final url = uploadResult['url'] as String? ?? '';

      if (url.isEmpty) throw Exception('Upload returned empty URL');

      // Replace temp bubble with real URL
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx != -1) {
          _messages[idx]['media_url'] = url;
          _messages[idx]['_uploading'] = false;
        }
        _filteredMessages = List.from(_messages);
      });

      final content = caption.isEmpty
          ? (mediaType == 'image'
                ? '📷 Image'
                : mediaType == 'video'
                ? '🎬 Video'
                : '📎 $fileName')
          : caption;

      // Send via REST only, as backend REST handler now broadcasts the message via WebSocket
      if (_isGroup && widget.conversationId != null) {
        await _messageService.sendGroupMessage(
          groupId: widget.conversationId!,
          content: content,
          mediaUrl: url,
          mediaType: mediaType,
        );
      } else {
        await _messageService.sendMessage(
          receiverId: widget.receiverId!,
          content: content,
          mediaUrl: url,
          mediaType: mediaType,
        );
      }
    } catch (e) {
      // Remove failed upload bubble
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempId);
        _filteredMessages = List.from(_messages);
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  void _showSendFileDialog(String fileName, String filePath, String extension) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send File'),
        content: Text('Send "$fileName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sendFileMessage(fileName, filePath, extension);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFileMessage(
    String fileName,
    String filePath,
    String extension,
  ) async {
    if (widget.receiverId == null) return;

    // Determine media type category
    final imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
    final videoExts = ['mp4', 'mov', 'avi', 'webm', 'mkv'];
    final audioExts = ['mp3', 'wav', 'aac', 'm4a', 'ogg'];
    String mediaType;
    if (imageExts.contains(extension.toLowerCase())) {
      mediaType = 'image';
    } else if (videoExts.contains(extension.toLowerCase())) {
      mediaType = 'video';
    } else if (audioExts.contains(extension.toLowerCase())) {
      mediaType = 'audio';
    } else {
      mediaType = 'file';
    }

    await _sendMediaMessage(filePath, fileName, mediaType);
  }

  @override
  void dispose() {
    // Cancel all WS subscriptions — critical to prevent memory leaks and duplicate listeners
    _chatMsgSub?.cancel();
    _groupMsgSub?.cancel();
    _typingSub?.cancel();
    _onlineSub?.cancel();
    _readSub?.cancel();
    _groupCallInviteSub?.cancel();
    _pollTimer?.cancel();
    _messageController.dispose();
    _chatSearchController.dispose();
    _scrollController.dispose();
    _typingDebounce?.cancel();
    // Stop typing indicator when leaving
    if (widget.receiverId != null) {
      _wsService.sendTyping(toUserId: widget.receiverId!, isTyping: false);
    }
    super.dispose();
  }

  void _filterMessages(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredMessages = List.from(_messages);
      } else {
        final searchLower = query.toLowerCase();
        _filteredMessages = _messages.where((msg) {
          final content = msg['content'] ?? msg['message'] ?? '';
          return content.toString().toLowerCase().contains(searchLower);
        }).toList();
      }
    });
  }

  void _toggleChatSearch() {
    setState(() {
      _isSearchingInChat = !_isSearchingInChat;
      if (!_isSearchingInChat) {
        _chatSearchController.clear();
        _filteredMessages = List.from(_messages);
      }
    });
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            if (_isGroup) ...[
              ListTile(
                leading: const Icon(Icons.group, color: Colors.blue),
                title: const Text('Group Members'),
                subtitle: Text(widget.name),
                onTap: () {
                  Navigator.pop(ctx);
                  _showGroupMembers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.orange),
                title: const Text('Block'),
                subtitle: const Text('Block all group members'),
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete & Leave'),
                subtitle: const Text('Delete chat and leave group'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.person, color: Colors.blue),
                title: const Text('View Profile'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showProfile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.orange),
                title: const Text('Block User'),
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.clear_all, color: Colors.grey),
                title: const Text('Clear Chat'),
                onTap: () {
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('Leave Chat'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showGroupMembers() {
    // Extract member count from group name
    final RegExp regExp = RegExp(r'\((\d+) members\)');
    final match = regExp.firstMatch(widget.name);
    final int memberCount = match != null ? int.parse(match.group(1)!) : 3;

    // Generate sample members
    final List<Map<String, dynamic>> members = [];
    final List<String> names = [
      'You',
      'Alice',
      'Bob',
      'Charlie',
      'David',
      'Emma',
      'Frank',
      'Grace',
    ];
    final List<Color> colors = [
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];

    for (int i = 0; i < memberCount && i < names.length; i++) {
      members.add({
        'name': names[i],
        'avatar': colors[i % colors.length],
        'isAdmin': i == 0,
        'online': i % 2 == 0,
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: widget.avatar.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.group, color: widget.avatar),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.name.split('(').first.trim(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$memberCount members',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final member = members[index];
                  return ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: member['avatar'],
                          child: Text(
                            member['name'][0],
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        if (member['isAdmin'])
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.star,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Text(member['name']),
                        if (member['isAdmin']) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Admin',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: member['online']
                        ? Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: widget.avatar,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.name.isNotEmpty ? widget.name[0] : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.name.split('(').first.trim(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isOnline
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: widget.isOnline ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: widget.isOnline
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem('Followers', '12.5K'),
                    _buildStatItem('Following', '890'),
                    _buildStatItem('Posts', '245'),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'About',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hey there! I\'m using Entertok. Love to meet new people!',
                      style: TextStyle(color: Colors.grey[700], fontSize: 15),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildInfoRow(
                      Icons.location_on,
                      'Location',
                      'San Francisco, USA',
                    ),
                    _buildInfoRow(Icons.cake, 'Birthday', 'March 15, 1999'),
                    _buildInfoRow(Icons.work, 'Job', 'Software Developer'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600], size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearchingInChat
            ? TextField(
                controller: _chatSearchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search in conversation...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                style: const TextStyle(color: Colors.black),
                onChanged: _filterMessages,
              )
            : Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: widget.avatar,
                        child: Text(
                          widget.name.isNotEmpty ? widget.name[0] : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.isOnline || _isPartnerOnline)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        // Show typing indicator or online status
                        _isTyping
                            ? Text(
                                'typing...',
                                style: TextStyle(
                                  color: Colors.blue[600],
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : Text(
                                _isPartnerOnline || widget.isOnline
                                    ? 'Online'
                                    : 'Offline',
                                style: TextStyle(
                                  color: (_isPartnerOnline || widget.isOnline)
                                      ? Colors.green
                                      : Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearchingInChat ? Icons.close : Icons.search),
            onPressed: _toggleChatSearch,
          ),
          IconButton(
            icon: const Icon(Icons.call, color: Colors.black),
            onPressed: () => _startCall(CallType.audio),
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.black),
            onPressed: () => _startCall(CallType.video),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () => _showOptionsMenu(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No messages yet.\nStart the conversation!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    controller: _scrollController,
                    itemCount: _filteredMessages.length,
                    itemBuilder: (context, index) {
                      final message = _filteredMessages[index];
                      return _buildMessageBubble(message);
                    },
                  ),
          ),
          // Message input (Telegram/WhatsApp style)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply banner
              if (_replyToMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.deepPurple.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      Container(width: 3, height: 40, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _replyToMessage!['isMe'] == true
                                  ? 'Replying to yourself'
                                  : 'Replying to ${_replyToMessage!['sender']?['full_name'] ?? _replyToMessage!['sender']?['username'] ?? widget.name}',
                              style: const TextStyle(
                                color: Colors.deepPurple,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _replyToMessage!['content']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _cancelReply,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              // Edit banner
              if (_editingMessageId != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.amber.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 16, color: Colors.amber),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Editing message',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() {
                            _editingMessageId = null;
                          });
                          _messageController.clear();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      // Attachment button
                      IconButton(
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: Colors.grey[600],
                        ),
                        onPressed: _pickFile,
                      ),
                      // Text input
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  decoration: InputDecoration(
                                    hintText: _editingMessageId != null
                                        ? 'Edit message...'
                                        : 'Message...',
                                    border: InputBorder.none,
                                  ),
                                  maxLines: null,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  onChanged: (value) {
                                    if (widget.receiverId != null) {
                                      // Send typing start
                                      _wsService.sendTyping(
                                        toUserId: widget.receiverId!,
                                        isTyping: value.isNotEmpty,
                                      );
                                      // Auto-stop typing after 2s of no input
                                      _typingDebounce?.cancel();
                                      if (value.isNotEmpty) {
                                        _typingDebounce = Timer(
                                          const Duration(seconds: 2),
                                          () => _wsService.sendTyping(
                                            toUserId: widget.receiverId!,
                                            isTyping: false,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _showEmojiPicker
                                      ? Icons.keyboard
                                      : Icons.emoji_emotions_outlined,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () => setState(
                                  () => _showEmojiPicker = !_showEmojiPicker,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Send / Save button
                      GestureDetector(
                        onTap: _editingMessageId != null
                            ? _saveEditedMessage
                            : _sendMessage,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.deepPurple,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _editingMessageId != null
                                ? Icons.check
                                : Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Emoji picker panel
              if (_showEmojiPicker)
                SizedBox(
                  height: 280,
                  child: EmojiPicker(
                    onEmojiSelected: (category, emoji) {
                      final text = _messageController.text;
                      final selection = _messageController.selection;
                      final newText = text.replaceRange(
                        selection.start < 0 ? text.length : selection.start,
                        selection.end < 0 ? text.length : selection.end,
                        emoji.emoji,
                      );
                      _messageController.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(
                          offset:
                              (selection.start < 0
                                  ? text.length
                                  : selection.start) +
                              emoji.emoji.length,
                        ),
                      );
                    },
                    onBackspacePressed: () {
                      final text = _messageController.text;
                      if (text.isNotEmpty) {
                        _messageController.text = text.characters
                            .skipLast(1)
                            .string;
                      }
                    },
                    config: const Config(
                      columns: 8,
                      emojiSizeMax: 28,
                      recentsLimit: 28,
                      checkPlatformCompatibility: true,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final bool isMe = message['isMe'] ?? false;
    final String messageText = message['content'] ?? message['message'] ?? '';
    final String? mediaUrl = message['media_url'] as String?;
    final String? mediaType = message['media_type'] as String?;
    final bool isUploading = message['_uploading'] == true;

    // Detect emoji-only message for larger font
    final bool isEmojiOnly =
        messageText.isNotEmpty &&
        RegExp(
          r'^[\u{1F000}-\u{1FFFF}\u{2600}-\u{27FF}\u{FE00}-\u{FEFF}\s]+$',
          unicode: true,
        ).hasMatch(messageText);

    final Color bubbleColor = isMe ? Colors.deepPurple : Colors.grey.shade200;
    final Color textColor = isMe ? Colors.white : Colors.black87;

    Widget? mediaWidget;

    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      final imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
      final videoExts = ['mp4', 'mov', 'avi', 'webm', 'mkv'];
      final audioExts = ['mp3', 'wav', 'aac', 'm4a', 'ogg'];

      final ext = mediaUrl.split('.').last.toLowerCase().split('?').first;
      final isImageType = mediaType == 'image' || imageExts.contains(ext);
      final isVideoType = mediaType == 'video' || videoExts.contains(ext);
      final isAudioType = mediaType == 'audio' || audioExts.contains(ext);

      if (isImageType) {
        mediaWidget = GestureDetector(
          onTap: () => _showFullScreenImage(mediaUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: isUploading
                ? Container(
                    width: 200,
                    height: 200,
                    color: Colors.black26,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 8),
                          Text(
                            'Uploading...',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : mediaUrl.startsWith('file://')
                ? Image.file(
                    File(
                      mediaUrl
                          .replaceFirst(RegExp(r'^file:///'), '')
                          .replaceFirst(RegExp(r'^file://'), ''),
                    ),
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _buildMediaPlaceholder(Icons.broken_image, 'Image'),
                  )
                : (mediaUrl.startsWith('http://') ||
                      mediaUrl.startsWith('https://'))
                ? Image.network(
                    mediaUrl,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            width: 200,
                            height: 200,
                            color: Colors.black12,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                    errorBuilder: (_, __, ___) =>
                        _buildMediaPlaceholder(Icons.broken_image, 'Image'),
                  )
                : _buildMediaPlaceholder(Icons.broken_image, 'Image'),
          ),
        );
      } else if (isVideoType) {
        mediaWidget = GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video playback coming soon')),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 200,
                  height: 150,
                  color: Colors.black54,
                  child: const Icon(
                    Icons.videocam,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.deepPurple,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (isAudioType) {
        mediaWidget = Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? Colors.deepPurple.shade700 : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.audiotrack,
                color: isMe ? Colors.white : Colors.deepPurple,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mediaUrl.split('/').last.split('?').first,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Audio',
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey[600],
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      } else {
        // Generic file card
        final filename = mediaUrl.split('/').last.split('?').first;
        mediaWidget = Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? Colors.deepPurple.shade700 : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.white24
                      : Colors.deepPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.insert_drive_file,
                  color: isMe ? Colors.white : Colors.deepPurple,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'File',
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey[600],
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.download,
                color: isMe ? Colors.white70 : Colors.grey[600],
                size: 20,
              ),
            ],
          ),
        );
      }
    }

    return GestureDetector(
      onLongPress: () => _showMessageOptions(message),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            bottom: 8,
            left: isMe ? 4 : 0,
            right: isMe ? 0 : 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              // ⋮ on LEFT for received
              if (!isMe) _bubbleActionBtn(() => _showMessageOptions(message)),

              // ── Bubble content ────────────────────────────────────
              Flexible(
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Image/video shown outside bubble
                    if (mediaWidget != null &&
                        (mediaType == 'image' || mediaType == 'video'))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: mediaWidget,
                      ),

                    // Text bubble or file/audio card
                    if (mediaWidget == null ||
                        (mediaType != 'image' && mediaType != 'video'))
                      Container(
                        padding: mediaWidget != null
                            ? const EdgeInsets.all(4)
                            : const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                        decoration: BoxDecoration(
                          color: mediaWidget != null
                              ? Colors.transparent
                              : bubbleColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Sender name (group)
                            if (!isMe && message['is_group'] == true)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  message['sender']?['full_name'] ??
                                      message['sender']?['username'] ??
                                      '',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                              ),

                            // Reply quote
                            if (message['reply_to'] != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.white.withValues(alpha: 0.15)
                                      : Colors.deepPurple.withValues(
                                          alpha: 0.1,
                                        ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border(
                                    left: BorderSide(
                                      color: isMe
                                          ? Colors.white54
                                          : Colors.deepPurple,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  (message['reply_to']['content'] ?? '')
                                      .toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isMe
                                        ? Colors.white70
                                        : Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),

                            if (mediaWidget != null) mediaWidget,
                            if (messageText.isNotEmpty &&
                                !messageText.startsWith('\u{1F4F7}') &&
                                !messageText.startsWith('\u{1F3AC}') &&
                                !messageText.startsWith('\u{1F4CE}'))
                              Padding(
                                padding: mediaWidget != null
                                    ? const EdgeInsets.all(8)
                                    : EdgeInsets.zero,
                                child: Text(
                                  messageText,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: isEmojiOnly ? 32 : 15,
                                  ),
                                ),
                              )
                            else if (mediaWidget == null)
                              Text(
                                messageText,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: isEmojiOnly ? 32 : 15,
                                ),
                              ),

                            // Edited label
                            if (message['edited'] == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'edited',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: isMe
                                        ? Colors.white54
                                        : Colors.grey[400],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                    // Caption under image/video
                    if (mediaWidget != null &&
                        (mediaType == 'image' || mediaType == 'video') &&
                        messageText.isNotEmpty &&
                        !messageText.startsWith('\u{1F4F7}') &&
                        !messageText.startsWith('\u{1F3AC}'))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                        ),
                        child: Text(
                          messageText,
                          style: TextStyle(color: textColor, fontSize: 14),
                        ),
                      ),

                    // Time + status
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isUploading)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                            ),
                          Text(
                            message['time'] ?? '',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 10,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message['is_read'] == true
                                  ? Icons.done_all
                                  : Icons.done,
                              size: 14,
                              color: message['is_read'] == true
                                  ? Colors.blue
                                  : Colors.grey[400],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ⋮ on RIGHT for sent
              if (isMe) _bubbleActionBtn(() => _showMessageOptions(message)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubbleActionBtn(VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Icon(Icons.more_vert, size: 16, color: Colors.grey[400]),
    ),
  );

  Widget _buildMediaPlaceholder(IconData icon, String label) {
    return Container(
      width: 200,
      height: 200,
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: imageUrl.startsWith('file://')
                  ? Image.file(
                      File(imageUrl.replaceFirst('file://', '')),
                      fit: BoxFit.contain,
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Forward Message Sheet ────────────────────────────────────────────────────

class _ForwardMessageSheet extends StatefulWidget {
  final String content;
  final String? mediaUrl;
  final String? mediaType;
  final int? currentConversationId;
  final void Function(int userId, String name) onForwarded;

  const _ForwardMessageSheet({
    required this.content,
    this.mediaUrl,
    this.mediaType,
    this.currentConversationId,
    required this.onForwarded,
  });

  @override
  State<_ForwardMessageSheet> createState() => _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends State<_ForwardMessageSheet> {
  final MessageService _ms = MessageService();
  final UserService _us = UserService();
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final TextEditingController _search = TextEditingController();
  Set<int> _forwarding = {};

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() {
      final q = _search.text.toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? List.from(_conversations)
            : _conversations.where((c) {
                final u = c['user'] ?? {};
                final name = (u['full_name'] ?? u['username'] ?? '')
                    .toString()
                    .toLowerCase();
                return name.contains(q);
              }).toList();
      });
    });
  }

  Future<void> _load() async {
    try {
      final convs = await _ms.getConversations();
      if (mounted) {
        setState(() {
          _conversations = List<Map<String, dynamic>>.from(convs);
          _filtered = List.from(_conversations);
          _loading = false;
        });
      }
    } catch (_) {
      // Also load suggestions if no conversations
      try {
        final users = await _us.getSuggestions(limit: 20);
        if (mounted) {
          setState(() {
            _conversations = users
                .map<Map<String, dynamic>>((u) => {'user': u, 'id': null})
                .toList();
            _filtered = List.from(_conversations);
            _loading = false;
          });
        }
      } catch (__) {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _forward(Map<String, dynamic> conv) async {
    final user = conv['user'] ?? {};
    final receiverId = (user['id'] as num?)?.toInt();
    final name =
        user['full_name']?.toString() ?? user['username']?.toString() ?? 'User';
    if (receiverId == null) return;

    setState(() => _forwarding.add(receiverId));
    try {
      await _ms.sendMessage(
        receiverId: receiverId,
        content: widget.content.isNotEmpty
            ? '↪ ${widget.content}'
            : '↪ Forwarded media',
        mediaUrl: widget.mediaUrl,
        mediaType: widget.mediaType,
      );
      widget.onForwarded(receiverId, name);
    } catch (_) {}
    if (mounted) setState(() => _forwarding.remove(receiverId));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Text(
                  'Forward to',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Message preview
          if (widget.content.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: const Border(
                  left: BorderSide(color: Colors.deepPurple, width: 3),
                ),
              ),
              child: Text(
                widget.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search people...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? const Center(child: Text('No conversations found'))
                : ListView.builder(
                    controller: sc,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final conv = _filtered[i];
                      final user = conv['user'] ?? {};
                      final uid = (user['id'] as num?)?.toInt() ?? 0;
                      final name =
                          user['full_name']?.toString() ??
                          user['username']?.toString() ??
                          'User';
                      final pic = user['profile_image']?.toString() ?? '';
                      final isSending = _forwarding.contains(uid);

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.deepPurple,
                          backgroundImage: pic.isNotEmpty
                              ? NetworkImage(pic)
                              : null,
                          child: pic.isEmpty
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          user['username'] != null
                              ? '@${user['username']}'
                              : '',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : ElevatedButton(
                                onPressed: () => _forward(conv),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: const Text(
                                  'Send',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                        onTap: () => _forward(conv),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
