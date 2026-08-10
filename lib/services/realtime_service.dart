// realtime_service.dart — thin wrapper kept for backward compatibility.
// All real-time logic now lives in WebSocketService.
export 'websocket_service.dart';

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'websocket_service.dart';

/// Backward-compatible alias that delegates to WebSocketService.
class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  final _ws = WebSocketService();

  Stream<Map<String, dynamic>> get onNewPost => _ws.onNewPost;
  Stream<Map<String, dynamic>> get onLikeUpdate => _ws.onPostLike;
  Stream<Map<String, dynamic>> get onCommentUpdate => _ws.onNewComment;
  Stream<Map<String, dynamic>> get onFollowUpdate => _ws.onFollow;
  Stream<Map<String, dynamic>> get onNotification => _ws.onNotification;
  Stream<bool> get onConnectionChange => _ws.onConnectionChange;

  bool get isConnected => _ws.isConnected;

  Future<void> connect() async {
    final token = AuthService().apiClient.token;
    if (token == null) {
      debugPrint('RealtimeService: No token available');
      return;
    }
    await _ws.connect(token);
  }

  void disconnect() => _ws.disconnect();

  void sendTyping({required int toUserId, required bool isTyping}) {
    _ws.sendTyping(toUserId: toUserId, isTyping: isTyping);
  }

  void dispose() {
    // Don't dispose the singleton WebSocketService here
  }
}
