import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';

/// Unified real-time WebSocket service for EnterTok.
/// Handles: chat, group chat, typing, online status, post events,
/// notifications, live stream events, and heartbeat.
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _socket;
  bool _isConnected = false;
  String? _token;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;

  // ─── Stream Controllers ───────────────────────────────────────────────────
  final _chatMessageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _groupMessageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _typingCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _onlineStatusCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageReadCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageReactionCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _newPostCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _postLikeCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _newCommentCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _followCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _notificationCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _liveStartCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _liveEndCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _liveCommentCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _liveViewerCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _liveGiftCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionCtrl = StreamController<bool>.broadcast();
  // WebRTC
  final _webrtcMatchedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _webrtcWaitingCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _webrtcOfferCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _webrtcAnswerCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _webrtcIceCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _webrtcHangupCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _webrtcChatCtrl = StreamController<Map<String, dynamic>>.broadcast();
  // WebRTC call typing indicator
  final _webrtcCallTypingCtrl =
      StreamController<Map<String, dynamic>>.broadcast();

  // ─── Public Streams ───────────────────────────────────────────────────────
  Stream<Map<String, dynamic>> get onChatMessage => _chatMessageCtrl.stream;
  Stream<Map<String, dynamic>> get onGroupMessage => _groupMessageCtrl.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingCtrl.stream;
  Stream<Map<String, dynamic>> get onOnlineStatus => _onlineStatusCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageRead => _messageReadCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageReaction =>
      _messageReactionCtrl.stream;
  Stream<Map<String, dynamic>> get onNewPost => _newPostCtrl.stream;
  Stream<Map<String, dynamic>> get onPostLike => _postLikeCtrl.stream;
  Stream<Map<String, dynamic>> get onNewComment => _newCommentCtrl.stream;
  Stream<Map<String, dynamic>> get onFollow => _followCtrl.stream;
  Stream<Map<String, dynamic>> get onNotification => _notificationCtrl.stream;
  Stream<Map<String, dynamic>> get onLiveStart => _liveStartCtrl.stream;
  Stream<Map<String, dynamic>> get onLiveEnd => _liveEndCtrl.stream;
  Stream<Map<String, dynamic>> get onLiveComment => _liveCommentCtrl.stream;
  Stream<Map<String, dynamic>> get onLiveViewer => _liveViewerCtrl.stream;
  Stream<Map<String, dynamic>> get onLiveGift => _liveGiftCtrl.stream;
  Stream<bool> get onConnectionChange => _connectionCtrl.stream;
  // WebRTC
  Stream<Map<String, dynamic>> get onWebRTCMatched => _webrtcMatchedCtrl.stream;
  Stream<Map<String, dynamic>> get onWebRTCWaiting => _webrtcWaitingCtrl.stream;
  Stream<Map<String, dynamic>> get onWebRTCOffer => _webrtcOfferCtrl.stream;
  Stream<Map<String, dynamic>> get onWebRTCAnswer => _webrtcAnswerCtrl.stream;
  Stream<Map<String, dynamic>> get onWebRTCIce => _webrtcIceCtrl.stream;
  Stream<Map<String, dynamic>> get onWebRTCHangup => _webrtcHangupCtrl.stream;
  Stream<Map<String, dynamic>> get onWebRTCChat => _webrtcChatCtrl.stream;
  Stream<Map<String, dynamic>> get onWebRTCCallTyping =>
      _webrtcCallTypingCtrl.stream;

  bool get isConnected => _isConnected;

  // ─── Connection ───────────────────────────────────────────────────────────

  Future<void> connect(String token) async {
    if (_isConnected && _token == token && _socket != null) return;
    _token = token;
    _disconnect();
    _doConnect();
  }

  void _doConnect() {
    if (_token == null) return;
    try {
      final baseUrl = ApiClient.baseUrl.replaceAll('/api/v1', '');
      final wsUrl = baseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      final uri = Uri.parse('$wsUrl/ws?token=$_token');

      debugPrint('WebSocket: Connecting to $uri');
      _socket = WebSocketChannel.connect(uri);

      _socket!.stream.listen(
        (data) {
          if (!_isConnected) {
            // First message received — connection is confirmed working
            _isConnected = true;
            _reconnectAttempts = 0;
            _connectionCtrl.add(true);
            _startHeartbeat();
            debugPrint('WebSocket: Confirmed connected ✓');
          }
          if (data is String) {
            _handleRawData(data);
          } else if (data is List<int>) {
            _handleRawData(utf8.decode(data));
          } else {
            _handleRawData(data.toString());
          }
        },
        onDone: () {
          _isConnected = false;
          _connectionCtrl.add(false);
          _stopHeartbeat();
          _socket = null;
          debugPrint('WebSocket: Connection closed — scheduling reconnect');
          _scheduleReconnect();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _isConnected = false;
          _connectionCtrl.add(false);
          _stopHeartbeat();
          _socket = null;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      // Send a ping immediately to trigger the onDone/onError path if
      // the connection actually failed, AND to confirm we're connected.
      // Use a short delay so the stream listener is set up first.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_socket != null && !_isConnected) {
          _send({'type': 'ping'});
          // If still not confirmed connected after 3s, try again
          Future.delayed(const Duration(seconds: 3), () {
            if (!_isConnected && _token != null) {
              debugPrint('WebSocket: No response in 3s — retrying...');
              _disconnect();
              _scheduleReconnect();
            }
          });
        }
      });
    } catch (e) {
      debugPrint('WebSocket connection error: $e');
      _isConnected = false;
      _connectionCtrl.add(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_token == null) return;
    // Reset the "connected" flag to allow reconnect
    _isConnected = false;
    _reconnectTimer?.cancel();
    // Cap reconnect attempts but keep trying indefinitely with 30s max delay
    final delaySecs = (_reconnectAttempts < 5)
        ? (2 * (_reconnectAttempts + 1))
        : 30;
    _reconnectAttempts++;
    debugPrint(
      'WebSocket: Reconnect in ${delaySecs}s (attempt $_reconnectAttempts)',
    );
    _reconnectTimer = Timer(Duration(seconds: delaySecs), () {
      if (_token != null) _doConnect();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_socket != null) {
        if (_isConnected) {
          _send({'type': 'ping'});
        } else {
          // Not connected but heartbeat still running — reconnect
          _stopHeartbeat();
          _doConnect();
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _disconnect() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _socket?.sink.close();
    _socket = null;
    _isConnected = false;
  }

  void disconnect() {
    _token = null;
    _reconnectAttempts = _maxReconnectAttempts; // prevent auto-reconnect
    _disconnect();
  }

  // ─── Message Handling ─────────────────────────────────────────────────────

  void _handleRawData(String data) {
    // The backend sends one JSON object per frame, sometimes multiple separated by \n
    // Parse each part independently, robust against embedded newlines in JSON strings
    final parts = data.split('\n');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      try {
        final msg = jsonDecode(trimmed) as Map<String, dynamic>;
        final type = msg['type'] as String? ?? '';
        final payload = msg['payload'];
        if (type.isNotEmpty) _dispatch(type, payload);
      } catch (e) {
        // Try parsing the whole data as one JSON in case it was split mid-string
        try {
          final msg = jsonDecode(data) as Map<String, dynamic>;
          final type = msg['type'] as String? ?? '';
          final payload = msg['payload'];
          if (type.isNotEmpty) _dispatch(type, payload);
          return; // parsed whole thing — don't process parts again
        } catch (_) {
          debugPrint('WebSocket parse error for part: $e');
        }
      }
    }
  }

  void _dispatch(String type, dynamic payload) {
    if (payload == null) return;
    final p = payload is Map<String, dynamic> ? payload : <String, dynamic>{};

    switch (type) {
      case 'chat_message':
        _chatMessageCtrl.add(p);
        break;
      case 'group_message':
        _groupMessageCtrl.add(p);
        break;
      case 'typing':
        _typingCtrl.add(p);
        break;
      case 'online_status':
        _onlineStatusCtrl.add(p);
        break;
      case 'message_read':
        _messageReadCtrl.add(p);
        break;
      case 'message_reaction':
        _messageReactionCtrl.add(p);
        break;
      case 'new_post':
        _newPostCtrl.add(p);
        break;
      case 'post_liked':
      case 'post_unliked':
        _postLikeCtrl.add(p);
        break;
      case 'new_comment':
        _newCommentCtrl.add(p);
        break;
      case 'user_followed':
      case 'user_unfollowed':
        _followCtrl.add(p);
        break;
      case 'notification':
        _notificationCtrl.add(p);
        break;
      case 'live_start':
        _liveStartCtrl.add(p);
        break;
      case 'live_end':
        _liveEndCtrl.add(p);
        break;
      case 'live_comment':
        _liveCommentCtrl.add(p);
        break;
      case 'live_viewer_join':
        _liveViewerCtrl.add(p);
        break;
      case 'live_gift':
        _liveGiftCtrl.add(p);
        break;
      // WebRTC signaling
      case 'webrtc_matched':
        _webrtcMatchedCtrl.add(p);
        break;
      case 'webrtc_waiting':
        _webrtcWaitingCtrl.add(p);
        break;
      case 'webrtc_offer':
        _webrtcOfferCtrl.add(p);
        break;
      case 'webrtc_answer':
        _webrtcAnswerCtrl.add(p);
        break;
      case 'webrtc_ice':
        _webrtcIceCtrl.add(p);
        break;
      case 'webrtc_hangup':
        _webrtcHangupCtrl.add(p);
        break;
      case 'webrtc_chat':
        _webrtcChatCtrl.add(p);
        break;
      case 'webrtc_typing':
        _webrtcCallTypingCtrl.add(p);
        break;
      case 'pong':
        // heartbeat response — no-op
        break;
      case 'group_call_invite':
        _groupCallInviteCtrl.add(p);
        break;
      case 'group_call_join':
        _groupCallJoinCtrl.add(p);
        break;
      case 'group_call_decline':
        _groupCallDeclineCtrl.add(p);
        break;
      case 'group_call_end':
        _groupCallEndCtrl.add(p);
        break;
    }
  }

  // ─── Send Helpers ─────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> message) {
    if (_socket == null) return;
    try {
      _socket!.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('WebSocket send error: $e');
    }
  }

  // ─── Chat ─────────────────────────────────────────────────────────────────

  void sendChatMessage({
    required int receiverId,
    required String content,
    int? conversationId,
    String? mediaUrl,
    String? mediaType,
    int? replyToId,
  }) {
    _send({
      'type': 'chat_message',
      'payload': {
        'receiver_id': receiverId,
        'content': content,
        if (conversationId != null) 'conversation_id': conversationId,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaType != null) 'media_type': mediaType,
        if (replyToId != null) 'reply_to_id': replyToId,
      },
    });
  }

  void sendGroupMessage({
    required int groupId,
    required String content,
    int? conversationId,
    String? mediaUrl,
    String? mediaType,
  }) {
    _send({
      'type': 'group_message',
      'payload': {
        'group_id': groupId,
        'content': content,
        if (conversationId != null) 'conversation_id': conversationId,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaType != null) 'media_type': mediaType,
      },
    });
  }

  void sendTyping({
    required int toUserId,
    required bool isTyping,
    int? groupId,
  }) {
    _send({
      'type': 'typing',
      'payload': {
        'to_user_id': toUserId,
        'is_typing': isTyping,
        if (groupId != null) 'group_id': groupId,
      },
    });
  }

  void sendMessageRead({required int messageId, required int conversationId}) {
    _send({
      'type': 'message_read',
      'payload': {'message_id': messageId, 'conversation_id': conversationId},
    });
  }

  void sendMessageReaction({required int messageId, required String emoji}) {
    _send({
      'type': 'message_reaction',
      'payload': {'message_id': messageId, 'emoji': emoji},
    });
  }

  // ─── WebRTC Signaling ─────────────────────────────────────────────────────

  /// Find a random peer to video chat with
  void webrtcFindPeer() => _send({'type': 'webrtc_find_peer', 'payload': {}});

  /// Cancel searching
  void webrtcCancelFind() =>
      _send({'type': 'webrtc_cancel_find', 'payload': {}});

  /// Send SDP offer to peer
  void webrtcSendOffer(int toUserId, Map<String, dynamic> sdp) => _send({
    'type': 'webrtc_offer',
    'payload': {'to_user_id': toUserId, 'data': sdp},
  });

  /// Send SDP answer to peer
  void webrtcSendAnswer(int toUserId, Map<String, dynamic> sdp) => _send({
    'type': 'webrtc_answer',
    'payload': {'to_user_id': toUserId, 'data': sdp},
  });

  /// Send ICE candidate to peer
  void webrtcSendIce(int toUserId, Map<String, dynamic> candidate) => _send({
    'type': 'webrtc_ice',
    'payload': {'to_user_id': toUserId, 'data': candidate},
  });

  /// Hang up
  void webrtcHangup(int toUserId) => _send({
    'type': 'webrtc_hangup',
    'payload': {'to_user_id': toUserId},
  });

  /// Send overlay chat message during video call
  void webrtcChatMsg(int toUserId, String text) => _send({
    'type': 'webrtc_call',
    'payload': {'to_user_id': toUserId, 'content': text},
  });

  /// Send typing indicator during video call
  void webrtcSendTyping(int toUserId, bool isTyping) => _send({
    'type': 'webrtc_typing',
    'payload': {'to_user_id': toUserId, 'is_typing': isTyping},
  });

  // ─── Group Call Signaling ──────────────────────────────────────────────────

  // Stream controllers for group call events
  final _groupCallInviteCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupCallJoinCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _groupCallDeclineCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupCallEndCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onGroupCallInvite =>
      _groupCallInviteCtrl.stream;
  Stream<Map<String, dynamic>> get onGroupCallJoin => _groupCallJoinCtrl.stream;
  Stream<Map<String, dynamic>> get onGroupCallDecline =>
      _groupCallDeclineCtrl.stream;
  Stream<Map<String, dynamic>> get onGroupCallEnd => _groupCallEndCtrl.stream;

  /// Invite all group members to a call
  void sendGroupCallInvite(int groupId, String groupName, String callType) =>
      _send({
        'type': 'group_call_invite',
        'payload': {
          'group_id': groupId,
          'group_name': groupName,
          'call_type': callType,
        },
      });

  /// Tell the caller you're joining
  void sendGroupCallJoin(int groupId, int callerId) => _send({
    'type': 'group_call_join',
    'payload': {'group_id': groupId, 'caller_id': callerId},
  });

  /// Tell the caller you declined
  void sendGroupCallDecline(int groupId, int callerId) => _send({
    'type': 'group_call_decline',
    'payload': {'group_id': groupId, 'caller_id': callerId},
  });

  /// End the group call for everyone
  void sendGroupCallEnd(int groupId) => _send({
    'type': 'group_call_end',
    'payload': {'group_id': groupId},
  });

  void joinLiveStream(int streamId) {
    _send({
      'type': 'live_viewer_join',
      'payload': {'stream_id': streamId},
    });
  }

  void leaveLiveStream(int streamId) {
    _send({
      'type': 'live_viewer_leave',
      'payload': {'stream_id': streamId},
    });
  }

  void sendLiveComment({
    required int streamId,
    required String content,
    String commentType = 'text',
    double giftValue = 0,
  }) {
    _send({
      'type': 'live_comment',
      'payload': {
        'stream_id': streamId,
        'content': content,
        'comment_type': commentType,
        'gift_value': giftValue,
      },
    });
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  void dispose() {
    disconnect();
    _chatMessageCtrl.close();
    _groupMessageCtrl.close();
    _typingCtrl.close();
    _onlineStatusCtrl.close();
    _messageReadCtrl.close();
    _messageReactionCtrl.close();
    _newPostCtrl.close();
    _postLikeCtrl.close();
    _newCommentCtrl.close();
    _followCtrl.close();
    _notificationCtrl.close();
    _liveStartCtrl.close();
    _liveEndCtrl.close();
    _liveCommentCtrl.close();
    _liveViewerCtrl.close();
    _liveGiftCtrl.close();
    _connectionCtrl.close();
    _webrtcMatchedCtrl.close();
    _webrtcWaitingCtrl.close();
    _webrtcOfferCtrl.close();
    _webrtcAnswerCtrl.close();
    _webrtcIceCtrl.close();
    _webrtcHangupCtrl.close();
    _webrtcChatCtrl.close();
    _webrtcCallTypingCtrl.close();
    _groupCallInviteCtrl.close();
    _groupCallJoinCtrl.close();
    _groupCallDeclineCtrl.close();
    _groupCallEndCtrl.close();
  }
}
