import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'websocket_service.dart';

/// Manages native desktop/system notifications for all real-time events.
/// Uses local_notifier for Windows toast notifications.
/// Falls back to debug prints on unsupported platforms.
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  bool _initialized = false;
  final List<StreamSubscription> _subs = [];

  // Track my own user ID so we don't notify for our own actions
  int? myUserId;

  Future<void> init({int? userId}) async {
    if (_initialized) return;
    myUserId = userId;

    try {
      await localNotifier.setup(
        appName: 'EnterTok',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _initialized = true;
      debugPrint('PushNotificationService: initialized ✓');
    } catch (e) {
      debugPrint('PushNotificationService: init failed — $e');
    }
  }

  /// Start listening to WS events and fire notifications.
  void startListening() {
    final ws = WebSocketService();
    _cancelAll();

    // ── New chat message ──────────────────────────────────────────────────
    _subs.add(
      ws.onChatMessage.listen((data) {
        final senderId = (data['sender_id'] as num?)?.toInt();
        if (senderId == myUserId) return; // own message
        final senderName = data['sender_name']?.toString() ?? 'Someone';
        final content = data['content']?.toString() ?? '';
        if (content.isEmpty) return;
        _show(
          id: 'msg_$senderId',
          title: senderName,
          body: content,
          icon: '💬',
        );
      }),
    );

    // ── New group message ─────────────────────────────────────────────────
    _subs.add(
      ws.onGroupMessage.listen((data) {
        final senderId = (data['sender_id'] as num?)?.toInt();
        if (senderId == myUserId) return;
        final senderName = data['sender_name']?.toString() ?? 'Someone';
        final groupName = 'Group';
        final content = data['content']?.toString() ?? '';
        if (content.isEmpty) return;
        _show(
          id: 'grp_${data['group_id']}',
          title: '$senderName → $groupName',
          body: content,
          icon: '👥',
        );
      }),
    );

    // ── Notification (like, follow, comment) ──────────────────────────────
    _subs.add(
      ws.onNotification.listen((data) {
        final actorName =
            (data['actor'] as Map?)?['username']?.toString() ?? 'Someone';
        final message = data['message']?.toString() ?? '';
        final type = data['type']?.toString() ?? '';
        final icon = _iconForType(type);
        _show(
          id: 'notif_${data['id'] ?? DateTime.now().millisecondsSinceEpoch}',
          title: 'EnterTok',
          body: '@$actorName $message',
          icon: icon,
        );
      }),
    );

    // ── Incoming call ─────────────────────────────────────────────────────
    _subs.add(
      ws.onWebRTCOffer.listen((data) {
        final fromName = data['from_name']?.toString() ?? 'Someone';
        _show(
          id: 'call_${data['from_user_id']}',
          title: '📞 Incoming Call',
          body: '$fromName is calling you',
          icon: '📞',
        );
      }),
    );

    // ── Group call invite ─────────────────────────────────────────────────
    _subs.add(
      ws.onGroupCallInvite.listen((data) {
        final callerName = data['caller_name']?.toString() ?? 'Someone';
        final groupName = data['group_name']?.toString() ?? 'a group';
        _show(
          id: 'gcall_${data['group_id']}',
          title: '📞 Group Call',
          body: '$callerName started a call in $groupName',
          icon: '👥',
        );
      }),
    );

    // ── New post from someone you follow ──────────────────────────────────
    _subs.add(
      ws.onNewPost.listen((data) {
        final username = data['username']?.toString() ?? '';
        if (username.isEmpty) return;
        _show(
          id: 'post_${data['id']}',
          title: 'New post',
          body: '@$username posted a new video',
          icon: '🎬',
        );
      }),
    );

    // ── Live stream started ───────────────────────────────────────────────
    _subs.add(
      ws.onLiveStart.listen((data) {
        final username = data['username']?.toString() ?? '';
        final title = data['title']?.toString() ?? 'Live stream';
        if (username.isEmpty) return;
        _show(
          id: 'live_${data['stream_id']}',
          title: '🔴 Live Now',
          body: '@$username: $title',
          icon: '🔴',
        );
      }),
    );

    debugPrint('PushNotificationService: listening to WS events ✓');
  }

  // ── Internal helpers ───────────────────────────────────────────────────

  Future<void> _show({
    required String id,
    required String title,
    required String body,
    String icon = '',
  }) async {
    if (!_initialized) return;
    try {
      final notification = LocalNotification(
        identifier: id,
        title: title,
        body: '$icon  $body',
      );
      await notification.show();
    } catch (e) {
      debugPrint('PushNotificationService: show error — $e');
    }
  }

  String _iconForType(String type) {
    switch (type) {
      case 'like':
        return '❤️';
      case 'comment':
        return '💬';
      case 'follow':
        return '👤';
      case 'mention':
        return '📣';
      default:
        return '🔔';
    }
  }

  void _cancelAll() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void dispose() {
    _cancelAll();
    _initialized = false;
  }
}
