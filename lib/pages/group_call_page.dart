import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/websocket_service.dart';
import '../services/message_service.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GroupCallPage — Invite-based group WebRTC call (video or audio)
//
// Caller flow:
//   1. Opens page → sends group_call_invite WS message
//   2. Shows _CallerWaitingScreen (list of members + their join status)
//   3. When a member joins → create WebRTC offer to that member only
//   4. Transitions to _ActiveCallScreen once ≥1 member joins
//
// Member flow:
//   1. Receives group_call_invite in main.dart global listener → navigates here
//   2. Shows _MemberRingingScreen (caller info + Join/Decline)
//   3. Join → sends group_call_join, enters active call
//   4. Decline → sends group_call_decline, pops page
// ─────────────────────────────────────────────────────────────────────────────

enum GroupCallType { video, audio }

enum _CallRole { caller, member }

enum _MemberStatus { invited, joined, declined }

class GroupCallPage extends StatefulWidget {
  final int groupId;
  final String groupName;
  final GroupCallType callType;

  // Caller opens with isCaller=true (no callerInfo needed)
  // Member opens with isCaller=false + callerInfo from WS invite
  final bool isCaller;
  final int? callerUserId;
  final String? callerName;
  final String? callerAvatar;

  const GroupCallPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.callType = GroupCallType.video,
    this.isCaller = true,
    this.callerUserId,
    this.callerName,
    this.callerAvatar,
  });

  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

// One remote participant
class _Peer {
  final int userId;
  final String name;
  final String avatar;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool connected = false;
  bool muted = false;

  _Peer({required this.userId, required this.name, required this.avatar});

  Future<void> init() async => await renderer.initialize();

  Future<void> dispose() async {
    await pc?.close();
    await renderer.dispose();
  }
}

class _GroupCallPageState extends State<GroupCallPage> {
  final WebSocketService _ws = WebSocketService();
  final MessageService _ms = MessageService();
  final AuthService _auth = AuthService();

  // ── Role & phase ──────────────────────────────────────────────────────────
  late _CallRole _role;
  bool _ringing = true; // member sees ringing screen while true
  bool _callActive = false;

  // ── Local media ───────────────────────────────────────────────────────────
  MediaStream? _localStream;
  final RTCVideoRenderer _local = RTCVideoRenderer();
  bool _localReady = false;
  bool _micOn = true;
  bool _camOn = true;
  bool _screenSharing = false;
  MediaStream? _screenStream;

  // ── Peers (remote) ────────────────────────────────────────────────────────
  final Map<int, _Peer> _peers = {};

  // ── Members list shown on caller waiting screen ───────────────────────────
  // { userId → { name, avatar, status } }
  final Map<int, Map<String, dynamic>> _members = {};

  // ── WS subscriptions ──────────────────────────────────────────────────────
  StreamSubscription? _subJoin, _subDecline, _subEnd;
  StreamSubscription? _subOffer, _subAnswer, _subIce, _subHangup;

  // ── Timer ─────────────────────────────────────────────────────────────────
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  // ── my user id ────────────────────────────────────────────────────────────
  int? _myUserId;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    _role = widget.isCaller ? _CallRole.caller : _CallRole.member;
    _init();
  }

  Future<void> _init() async {
    // Get current user id
    try {
      final me = await _auth.getCurrentUser();
      _myUserId = (me['id'] as num?)?.toInt();
    } catch (_) {}

    await _local.initialize();
    setState(() => _localReady = true);

    _listenSignals();

    if (_role == _CallRole.caller) {
      await _getMedia();
      await _loadGroupMembers();
      // Send invite to all members
      _ws.sendGroupCallInvite(
        widget.groupId,
        widget.groupName,
        widget.callType == GroupCallType.video ? 'video' : 'audio',
      );
    }
    // Members just show ringing screen — no media yet
  }

  Future<void> _getMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.callType == GroupCallType.video
            ? {'facingMode': 'user', 'width': 640, 'height': 480}
            : false,
      });
      _local.srcObject = _localStream;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('GroupCall media error: $e');
    }
  }

  Future<void> _loadGroupMembers() async {
    try {
      final list = await _ms.getGroupMembers(widget.groupId);
      setState(() {
        for (final m in list) {
          final u = m['user'] ?? m;
          final uid = (u['id'] as num?)?.toInt();
          if (uid == null || uid == _myUserId) continue;
          _members[uid] = {
            'name':
                u['full_name']?.toString() ??
                u['username']?.toString() ??
                'Member',
            'avatar': u['profile_image']?.toString() ?? '',
            'status': _MemberStatus.invited,
          };
        }
      });
    } catch (e) {
      // No group in DB (meeting mode) — that's fine, members join via code
      debugPrint('GroupCall load members: $e (meeting mode — no members)');
    }
  }

  // ── WebRTC setup ──────────────────────────────────────────────────────────

  Future<void> _setupPcAndOffer(int userId) async {
    if (_peers.containsKey(userId)) return;
    final m = _members[userId];
    final peer = _Peer(
      userId: userId,
      name: m?['name'] as String? ?? 'Member $userId',
      avatar: m?['avatar'] as String? ?? '',
    );
    await peer.init();
    _peers[userId] = peer;

    peer.pc = await createPeerConnection(_iceConfig);
    _localStream?.getTracks().forEach(
      (t) async => await peer.pc!.addTrack(t, _localStream!),
    );

    peer.pc!.onIceCandidate = (c) {
      if (c.candidate != null) _ws.webrtcSendIce(userId, c.toMap());
    };

    peer.pc!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          peer.renderer.srcObject = event.streams.first;
          peer.connected = true;
        });
      }
    };

    peer.pc!.onConnectionState = (s) {
      if (!mounted) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => peer.connected = true);
      } else if (s ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() {
          peer.connected = false;
          peer.renderer.srcObject = null;
        });
      }
    };

    if (mounted) setState(() {});

    // Create offer
    final offer = await peer.pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.callType == GroupCallType.video,
    });
    await peer.pc!.setLocalDescription(offer);
    _ws.webrtcSendOffer(userId, offer.toMap());
  }

  Future<void> _handleIncomingOffer(
    int fromId,
    Map<String, dynamic> sdpMap,
  ) async {
    if (!_peers.containsKey(fromId)) {
      final peer = _Peer(userId: fromId, name: 'Member $fromId', avatar: '');
      await peer.init();
      _peers[fromId] = peer;

      peer.pc = await createPeerConnection(_iceConfig);
      _localStream?.getTracks().forEach(
        (t) async => await peer.pc!.addTrack(t, _localStream!),
      );
      peer.pc!.onIceCandidate = (c) {
        if (c.candidate != null) _ws.webrtcSendIce(fromId, c.toMap());
      };
      peer.pc!.onTrack = (event) {
        if (event.streams.isNotEmpty && mounted) {
          setState(() {
            peer.renderer.srcObject = event.streams.first;
            peer.connected = true;
          });
        }
      };
      peer.pc!.onConnectionState = (s) {
        if (!mounted) return;
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() => peer.connected = true);
        }
      };
      if (mounted) setState(() {});
    }

    final peer = _peers[fromId]!;
    await peer.pc?.setRemoteDescription(
      RTCSessionDescription(
        sdpMap['sdp'] as String? ?? '',
        sdpMap['type'] as String? ?? 'offer',
      ),
    );
    final ans = await peer.pc?.createAnswer();
    if (ans != null) {
      await peer.pc?.setLocalDescription(ans);
      _ws.webrtcSendAnswer(fromId, ans.toMap());
    }
  }

  void _listenSignals() {
    // Member joined → caller creates peer connection & offer
    _subJoin = _ws.onGroupCallJoin.listen((data) async {
      if (!mounted) return;
      final joinerId = (data['joiner_id'] as num?)?.toInt();
      if (joinerId == null) return;

      if (_role == _CallRole.caller) {
        // Update member status
        if (_members.containsKey(joinerId)) {
          setState(() {
            _members[joinerId]!['status'] = _MemberStatus.joined;
            _callActive = true;
          });
        }
        // Create WebRTC offer to this member
        await _setupPcAndOffer(joinerId);
      }
    });

    // Member declined
    _subDecline = _ws.onGroupCallDecline.listen((data) {
      if (!mounted) return;
      final declinerId = (data['decliner_id'] as num?)?.toInt();
      if (declinerId == null) return;
      if (_role == _CallRole.caller) {
        setState(() {
          if (_members.containsKey(declinerId)) {
            _members[declinerId]!['status'] = _MemberStatus.declined;
          }
        });
      }
    });

    // Call ended by someone
    _subEnd = _ws.onGroupCallEnd.listen((data) {
      if (!mounted) return;
      Navigator.of(context).pop();
    });

    // WebRTC offer (member receives from caller after joining)
    _subOffer = _ws.onWebRTCOffer.listen((data) async {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null || !mounted) return;
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      await _handleIncomingOffer(fromId, sdpMap);
    });

    // WebRTC answer
    _subAnswer = _ws.onWebRTCAnswer.listen((data) async {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null) return;
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      await _peers[fromId]?.pc?.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'answer',
        ),
      );
    });

    // WebRTC ICE
    _subIce = _ws.onWebRTCIce.listen((data) async {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null) return;
      final c = data['data'] as Map<String, dynamic>? ?? {};
      if (c.isNotEmpty) {
        try {
          await _peers[fromId]?.pc?.addCandidate(
            RTCIceCandidate(
              c['candidate'] as String? ?? '',
              c['sdpMid'] as String? ?? '',
              (c['sdpMLineIndex'] as num?)?.toInt() ?? 0,
            ),
          );
        } catch (_) {}
      }
    });

    // WebRTC hangup (individual peer left)
    _subHangup = _ws.onWebRTCHangup.listen((data) {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null || !mounted) return;
      setState(() {
        _peers[fromId]?.renderer.srcObject = null;
        _peers[fromId]?.connected = false;
        if (_members.containsKey(fromId)) {
          _members[fromId]!['status'] = _MemberStatus.declined;
        }
      });
    });
  }

  // ── Member accepts call ───────────────────────────────────────────────────

  Future<void> _joinCall() async {
    setState(() {
      _ringing = false;
      _callActive = true;
    });
    await _getMedia();
    _ws.sendGroupCallJoin(widget.groupId, widget.callerUserId ?? 0);
    _startTimer();
  }

  void _declineCall() {
    _ws.sendGroupCallDecline(widget.groupId, widget.callerUserId ?? 0);
    Navigator.of(context).pop();
  }

  // ── End call ──────────────────────────────────────────────────────────────

  void _endCall() {
    _ws.sendGroupCallEnd(widget.groupId);
    // also hangup each peer
    for (final p in _peers.keys) {
      _ws.webrtcHangup(p);
    }
    Navigator.of(context).pop();
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  String get _elapsedStr {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggleMic() {
    setState(() => _micOn = !_micOn);
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _micOn);
  }

  void _toggleCam() {
    if (widget.callType != GroupCallType.video) return;
    setState(() => _camOn = !_camOn);
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _camOn);
  }

  // ── Screen sharing ────────────────────────────────────────────────────────

  Future<void> _toggleScreenShare() async {
    _screenSharing ? await _stopScreenShare() : await _startScreenShare();
  }

  Future<void> _startScreenShare() async {
    try {
      _screenStream = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': false,
      });
      if (!mounted) return;

      final screenTrack = _screenStream!.getVideoTracks().first;

      // Replace video track in ALL peer connections
      for (final peer in _peers.values) {
        final senders = await peer.pc?.getSenders() ?? [];
        for (final s in senders) {
          if (s.track?.kind == 'video') {
            await s.replaceTrack(screenTrack);
            break;
          }
        }
      }

      _local.srcObject = _screenStream;
      screenTrack.onEnded = () => _stopScreenShare();

      setState(() {
        _screenSharing = true;
        _camOn = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.present_to_all, color: Colors.white),
                SizedBox(width: 8),
                Text('Screen sharing started'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Group screen share error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Screen share failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopScreenShare() async {
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    _screenStream = null;

    // Restore camera track in all peer connections
    final camTrack = _localStream?.getVideoTracks().firstOrNull;
    if (camTrack != null) {
      for (final peer in _peers.values) {
        final senders = await peer.pc?.getSenders() ?? [];
        for (final s in senders) {
          if (s.track?.kind == 'video') {
            await s.replaceTrack(camTrack);
            break;
          }
        }
      }
    }
    if (_localStream != null) _local.srcObject = _localStream;

    setState(() {
      _screenSharing = false;
      _camOn = widget.callType == GroupCallType.video;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screen sharing stopped'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subJoin?.cancel();
    _subDecline?.cancel();
    _subEnd?.cancel();
    _subOffer?.cancel();
    _subAnswer?.cancel();
    _subIce?.cancel();
    _subHangup?.cancel();
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    for (final p in _peers.values) {
      p.dispose();
    }
    _localStream?.dispose();
    _local.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Member sees ringing screen until they join/decline
    if (_role == _CallRole.member && _ringing) {
      return _buildRingingScreen();
    }
    // Caller sees waiting screen until at least one person joins
    if (_role == _CallRole.caller && !_callActive) {
      return _buildCallerWaitingScreen();
    }
    // Active call
    return _buildActiveCall();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RINGING SCREEN (shown to members)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRingingScreen() {
    final callerName = widget.callerName ?? 'Someone';
    final callerAvatar = widget.callerAvatar ?? '';
    final isVideo = widget.callType == GroupCallType.video;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Caller avatar with pulse rings
            _PulseAvatar(name: callerName, avatarUrl: callerAvatar, size: 90),
            const SizedBox(height: 24),
            Text(
              callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.groupName} · ${isVideo ? "Group Video Call" : "Group Audio Call"}',
              style: TextStyle(color: Colors.grey[400], fontSize: 15),
            ),
            const Spacer(),
            // Join / Decline buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _declineCall,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Decline',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  // Join
                  Column(
                    children: [
                      GestureDetector(
                        onTap: _joinCall,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isVideo ? Icons.videocam : Icons.call,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Join',
                        style: TextStyle(color: Colors.white70),
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

  // ─────────────────────────────────────────────────────────────────────────
  // CALLER WAITING SCREEN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCallerWaitingScreen() {
    final joined = _members.values
        .where((m) => m['status'] == _MemberStatus.joined)
        .length;
    final total = _members.length;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Group icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              widget.groupName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              total == 0
                  ? 'Waiting for participants...'
                  : '$joined / $total joined',
              style: TextStyle(color: Colors.grey[400], fontSize: 15),
            ),
            const SizedBox(height: 12),
            // Animated "ringing" indicator
            const _RingingDots(),
            const SizedBox(height: 32),
            // Member list or meeting mode message
            Expanded(
              child: _members.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link, size: 48, color: Colors.grey[600]),
                          const SizedBox(height: 16),
                          Text(
                            'Share the meeting code',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'so others can join',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const _RingingDots(),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _members.length,
                      itemBuilder: (_, i) {
                        final uid = _members.keys.elementAt(i);
                        final m = _members[uid]!;
                        final status = m['status'] as _MemberStatus;
                        return _memberStatusTile(
                          name: m['name'] as String,
                          avatar: m['avatar'] as String,
                          status: status,
                        );
                      },
                    ),
            ),
            // End call button
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'End Call',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberStatusTile({
    required String name,
    required String avatar,
    required _MemberStatus status,
  }) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case _MemberStatus.invited:
        statusColor = Colors.grey;
        statusIcon = Icons.phone_in_talk;
        statusText = 'Ringing...';
        break;
      case _MemberStatus.joined:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Joined';
        break;
      case _MemberStatus.declined:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Declined';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          avatar.isNotEmpty
              ? CircleAvatar(radius: 22, backgroundImage: NetworkImage(avatar))
              : CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.deepPurple,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(statusIcon, color: statusColor, size: 22),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVE CALL SCREEN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActiveCall() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            // Screen sharing banner
            if (_screenSharing)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.orange.withOpacity(0.9),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.present_to_all, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'You are sharing your screen',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: widget.callType == GroupCallType.video
                  ? _videoGrid()
                  : _audioGrid(),
            ),
            _bottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                widget.groupName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                _callActive
                    ? '${_peers.values.where((p) => p.connected).length + 1} participants · $_elapsedStr'
                    : 'Connecting...',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 48),
      ],
    ),
  );

  Widget _videoGrid() {
    final participants = <Widget>[_localVideoTile()];
    for (final peer in _peers.values) {
      participants.add(_remoteTile(peer));
    }
    final count = participants.length;
    final crossCount = count <= 1
        ? 1
        : count <= 4
        ? 2
        : 3;

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 3 / 4,
      ),
      itemCount: participants.length,
      itemBuilder: (_, i) => participants[i],
    );
  }

  Widget _localVideoTile() => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _localReady && _localStream != null && _camOn
            ? RTCVideoView(
                _local,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : _avatarBg('You', null, Colors.deepPurple),
        Positioned(bottom: 8, left: 8, child: _nameTag('You', !_micOn)),
      ],
    ),
  );

  Widget _remoteTile(_Peer peer) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      fit: StackFit.expand,
      children: [
        peer.connected && peer.renderer.srcObject != null
            ? RTCVideoView(
                peer.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : _avatarBg(peer.name, peer.avatar, Colors.blue),
        Positioned(
          bottom: 8,
          left: 8,
          child: _nameTag(
            peer.name.length > 10
                ? '${peer.name.substring(0, 10)}…'
                : peer.name,
            false,
          ),
        ),
      ],
    ),
  );

  Widget _nameTag(String name, bool micOff) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (micOff) ...[
          const Icon(Icons.mic_off, color: Colors.red, size: 12),
          const SizedBox(width: 3),
        ],
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _avatarBg(String name, String? pic, Color color) => Container(
    color: const Color(0xFF1A1A2E),
    child: Center(
      child: (pic != null && pic.isNotEmpty)
          ? CircleAvatar(radius: 36, backgroundImage: NetworkImage(pic))
          : CircleAvatar(
              radius: 36,
              backgroundColor: color,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    ),
  );

  Widget _audioGrid() => GridView.builder(
    padding: const EdgeInsets.all(16),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
    ),
    itemCount: _peers.length + 1,
    itemBuilder: (_, i) {
      if (i == 0) {
        return _audioCard('You', null, Colors.deepPurple, true, _micOn);
      }
      final peer = _peers.values.elementAt(i - 1);
      return _audioCard(
        peer.name,
        peer.avatar,
        Colors.blue,
        peer.connected,
        !peer.muted,
      );
    },
  );

  Widget _audioCard(
    String name,
    String? pic,
    Color color,
    bool connected,
    bool micOn,
  ) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: connected
            ? Colors.green.withOpacity(0.4)
            : Colors.grey.withOpacity(0.2),
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            (pic != null && pic.isNotEmpty)
                ? CircleAvatar(radius: 32, backgroundImage: NetworkImage(pic))
                : CircleAvatar(
                    radius: 32,
                    backgroundColor: color,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
            if (!micOn)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_off, color: Colors.white, size: 12),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          name.length > 10 ? '${name.substring(0, 10)}…' : name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.circle,
              size: 7,
              color: connected ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              connected ? 'Connected' : 'Connecting...',
              style: TextStyle(
                color: connected ? Colors.green[300] : Colors.grey[400],
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _bottomControls() => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ctrlBtn(
          _micOn ? Icons.mic : Icons.mic_off,
          _micOn ? Colors.white : Colors.red,
          _toggleMic,
          label: _micOn ? 'Mute' : 'Muted',
        ),
        if (widget.callType == GroupCallType.video)
          _ctrlBtn(
            _camOn ? Icons.videocam : Icons.videocam_off,
            _camOn ? Colors.white : Colors.red,
            _toggleCam,
            label: _camOn ? 'Cam off' : 'Cam on',
          ),
        GestureDetector(
          onTap: _endCall,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'End',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        _ctrlBtn(
          Icons.people,
          Colors.white,
          _showParticipants,
          label: 'Members',
        ),
        // ── Screen share ──────────────────────────────────────
        _ctrlBtn(
          _screenSharing ? Icons.stop_screen_share : Icons.present_to_all,
          _screenSharing ? Colors.orange : Colors.white,
          _toggleScreenShare,
          label: _screenSharing ? 'Stop' : 'Share',
        ),
      ],
    ),
  );

  Widget _ctrlBtn(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    String? label,
  }) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ],
      ],
    ),
  );

  void _showParticipants() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_peers.length + 1} Participants',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.deepPurple,
                  child: Icon(Icons.person, color: Colors.white, size: 20),
                ),
                title: const Text(
                  'You',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_micOn)
                      const Icon(Icons.mic_off, color: Colors.red, size: 18),
                    const SizedBox(width: 4),
                    const Icon(Icons.circle, color: Colors.green, size: 10),
                  ],
                ),
              ),
              ..._peers.values.map(
                (p) => ListTile(
                  leading: CircleAvatar(
                    backgroundImage: p.avatar.isNotEmpty
                        ? NetworkImage(p.avatar)
                        : null,
                    backgroundColor: Colors.blue,
                    child: p.avatar.isEmpty
                        ? Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white),
                          )
                        : null,
                  ),
                  title: Text(
                    p.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Icon(
                    Icons.circle,
                    color: p.connected ? Colors.green : Colors.grey,
                    size: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Pulsating avatar (used in ringing screen)
class _PulseAvatar extends StatefulWidget {
  final String name;
  final String avatarUrl;
  final double size;

  const _PulseAvatar({
    required this.name,
    required this.avatarUrl,
    this.size = 80,
  });

  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 1.0,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.scale(scale: _anim.value, child: child),
      child: Container(
        width: widget.size * 2,
        height: widget.size * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.deepPurple.withOpacity(0.2),
        ),
        child: Center(
          child: widget.avatarUrl.isNotEmpty
              ? CircleAvatar(
                  radius: widget.size,
                  backgroundImage: NetworkImage(widget.avatarUrl),
                )
              : CircleAvatar(
                  radius: widget.size,
                  backgroundColor: Colors.deepPurple,
                  child: Text(
                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.size * 0.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Animated dots "Calling..." indicator
class _RingingDots extends StatefulWidget {
  const _RingingDots();

  @override
  State<_RingingDots> createState() => _RingingDotsState();
}

class _RingingDotsState extends State<_RingingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final delay = i * 0.33;
            final t = (_ctrl.value - delay).clamp(0.0, 1.0);
            final opacity = (t < 0.5 ? t * 2 : (1.0 - t) * 2).clamp(0.2, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Opacity(
                opacity: opacity,
                child: const Icon(Icons.circle, color: Colors.white, size: 10),
              ),
            );
          }),
        );
      },
    );
  }
}
