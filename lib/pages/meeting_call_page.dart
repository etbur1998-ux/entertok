import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/websocket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MeetingCallPage — Zoom-style meeting room
//
// Works like a video call room identified by a numeric roomId derived from
// the meeting code. Two modes:
//
//  • HOST   (isHost=true):  gets media → creates offer → waits for anyone
//                           who joins (via onWebRTCOffer/Answer)
//  • JOINER (isHost=false): gets media → waits for host offer → answers it
//
// Both sides use the same roomId so WS routes signaling between them.
// Supports multiple participants via a simple mesh: each person creates a
// peer connection to every other person.
// ─────────────────────────────────────────────────────────────────────────────

class MeetingCallPage extends StatefulWidget {
  final int roomId; // derived from meeting code
  final String meetingName; // display name
  final String meetingCode; // shown in UI
  final bool isHost; // true = started the meeting

  const MeetingCallPage({
    super.key,
    required this.roomId,
    required this.meetingName,
    required this.meetingCode,
    this.isHost = false,
  });

  @override
  State<MeetingCallPage> createState() => _MeetingCallPageState();
}

class _Peer {
  final int userId;
  final String name;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool connected = false;

  _Peer({required this.userId, required this.name});

  Future<void> init() async => await renderer.initialize();
  Future<void> dispose() async {
    await pc?.close();
    await renderer.dispose();
  }
}

class _MeetingCallPageState extends State<MeetingCallPage>
    with WidgetsBindingObserver {
  final WebSocketService _ws = WebSocketService();

  MediaStream? _localStream;
  final RTCVideoRenderer _local = RTCVideoRenderer();
  bool _localReady = false;

  final Map<int, _Peer> _peers = {};
  final List<RTCIceCandidate> _pendingIce = [];

  bool _micOn = true;
  bool _camOn = true;
  bool _screenSharing = false;
  MediaStream? _screenStream;

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  bool _connected = false;

  StreamSubscription? _subOffer, _subAnswer, _subIce, _subHangup;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _local.initialize();
    setState(() => _localReady = true);
    await _getMedia();
    _listenSignals();
    // Host sends offer with roomId as the target
    // Joiner waits for offer from host
    if (widget.isHost) {
      // Announce presence — send a "ping offer" to room
      // We use roomId as peerId for signaling routing
      await _createPeer(widget.roomId, shouldOffer: true);
    }
  }

  Future<void> _getMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      });
      _local.srcObject = _localStream;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('MeetingCall _getMedia: $e');
    }
  }

  Future<_Peer> _createPeer(int uid, {bool shouldOffer = false}) async {
    if (_peers.containsKey(uid)) return _peers[uid]!;
    final peer = _Peer(userId: uid, name: 'Participant');
    await peer.init();
    _peers[uid] = peer;

    peer.pc = await createPeerConnection(_iceConfig);
    _localStream?.getTracks().forEach(
      (t) async => await peer.pc!.addTrack(t, _localStream!),
    );

    peer.pc!.onIceCandidate = (c) {
      if (c.candidate != null) _ws.webrtcSendIce(uid, c.toMap());
    };

    peer.pc!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          peer.renderer.srcObject = event.streams.first;
          peer.connected = true;
          _connected = true;
        });
        _startTimer();
      }
    };

    peer.pc!.onConnectionState = (s) {
      if (!mounted) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          peer.connected = true;
          _connected = true;
        });
        _startTimer();
      } else if (s ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() {
          peer.connected = false;
        });
      }
    };

    if (shouldOffer) {
      final offer = await peer.pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peer.pc!.setLocalDescription(offer);
      _ws.webrtcSendOffer(uid, offer.toMap());
      debugPrint('MeetingCall: sent offer to room peer $uid');
    }

    if (mounted) setState(() {});
    return peer;
  }

  void _listenSignals() {
    _subOffer = _ws.onWebRTCOffer.listen((data) async {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null) return;
      debugPrint('MeetingCall: received offer from $fromId');

      final peer = await _createPeer(fromId, shouldOffer: false);
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      await peer.pc!.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'offer',
        ),
      );
      // Flush pending ICE
      for (final c in _pendingIce) {
        try {
          await peer.pc!.addCandidate(c);
        } catch (_) {}
      }
      _pendingIce.clear();

      final ans = await peer.pc!.createAnswer();
      await peer.pc!.setLocalDescription(ans);
      _ws.webrtcSendAnswer(fromId, ans.toMap());
    });

    _subAnswer = _ws.onWebRTCAnswer.listen((data) async {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null) return;
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      final peer = _peers[fromId];
      if (peer?.pc != null) {
        await peer!.pc!.setRemoteDescription(
          RTCSessionDescription(
            sdpMap['sdp'] as String? ?? '',
            sdpMap['type'] as String? ?? 'answer',
          ),
        );
      }
    });

    _subIce = _ws.onWebRTCIce.listen((data) async {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null) return;
      final c = data['data'] as Map<String, dynamic>? ?? {};
      if (c.isEmpty) return;
      final cand = RTCIceCandidate(
        c['candidate'] as String? ?? '',
        c['sdpMid'] as String? ?? '',
        (c['sdpMLineIndex'] as num?)?.toInt() ?? 0,
      );
      final peer = _peers[fromId];
      if (peer?.pc != null) {
        try {
          await peer!.pc!.addCandidate(cand);
        } catch (_) {}
      } else {
        _pendingIce.add(cand); // buffer until peer is created
      }
    });

    _subHangup = _ws.onWebRTCHangup.listen((data) {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null || !mounted) return;
      setState(() {
        _peers[fromId]?.renderer.srcObject = null;
        _peers[fromId]?.connected = false;
      });
    });
  }

  void _startTimer() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  String get _elapsed2 {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _toggleMic() {
    setState(() => _micOn = !_micOn);
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _micOn);
  }

  void _toggleCam() {
    setState(() => _camOn = !_camOn);
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _camOn);
  }

  Future<void> _toggleScreenShare() async {
    if (_screenSharing) {
      _screenStream?.getTracks().forEach((t) => t.stop());
      _screenStream?.dispose();
      _screenStream = null;
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
        _camOn = true;
      });
    } else {
      try {
        _screenStream = await navigator.mediaDevices.getDisplayMedia({
          'video': true,
          'audio': false,
        });
        if (!mounted) return;
        final screenTrack = _screenStream!.getVideoTracks().first;
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
        screenTrack.onEnded = () => _toggleScreenShare();
        setState(() {
          _screenSharing = true;
          _camOn = false;
        });
      } catch (e) {
        debugPrint('Screen share error: $e');
      }
    }
  }

  void _endMeeting() {
    for (final uid in _peers.keys) {
      _ws.webrtcHangup(uid);
    }
    Navigator.pop(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
    } else if (state == AppLifecycleState.resumed && _camOn) {
      _localStream?.getVideoTracks().forEach((t) => t.enabled = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subOffer?.cancel();
    _subAnswer?.cancel();
    _subIce?.cancel();
    _subHangup?.cancel();
    _timer?.cancel();
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    for (final p in _peers.values) {
      p.dispose();
    }
    _localStream?.dispose();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.black,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: _endMeeting,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          widget.meetingName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          _connected
                              ? '${_peers.values.where((p) => p.connected).length + 1} participants · $_elapsed2'
                              : 'Waiting for participants...',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Screen sharing banner
            if (_screenSharing)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: Colors.orange.withOpacity(0.88),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.present_to_all, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'You are sharing your screen',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            // ── Video grid ───────────────────────────────────────────
            Expanded(child: _videoGrid()),
            // ── Controls ─────────────────────────────────────────────
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _videoGrid() {
    final tiles = <Widget>[_localTile()];
    for (final p in _peers.values) {
      if (p.connected) tiles.add(_remoteTile(p));
    }
    // If no one connected yet — show waiting message in the grid
    if (tiles.length == 1 && !_connected) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _localTile(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 100),
                Icon(
                  Icons.link,
                  size: 48,
                  color: Colors.white.withOpacity(0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Share code: ${widget.meetingCode}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Waiting for others to join...',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final count = tiles.length;
    final cols = count <= 1
        ? 1
        : count <= 4
        ? 2
        : 3;
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 3 / 4,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) => tiles[i],
    );
  }

  Widget _localTile() => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _localReady && _localStream != null && _camOn
            ? RTCVideoView(
                _local,
                mirror: !_screenSharing,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Container(
                color: const Color(0xFF1A1A2E),
                child: const Center(
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.deepPurple,
                    child: Icon(Icons.person, color: Colors.white, size: 32),
                  ),
                ),
              ),
        Positioned(bottom: 6, left: 6, child: _nameTag('You', !_micOn)),
      ],
    ),
  );

  Widget _remoteTile(_Peer peer) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Stack(
      fit: StackFit.expand,
      children: [
        peer.renderer.srcObject != null
            ? RTCVideoView(
                peer.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Container(
                color: const Color(0xFF1A1A2E),
                child: Center(
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.blue,
                    child: Text(
                      peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
        Positioned(bottom: 6, left: 6, child: _nameTag(peer.name, false)),
      ],
    ),
  );

  Widget _nameTag(String name, bool muted) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (muted) ...[
          const Icon(Icons.mic_off, color: Colors.red, size: 11),
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

  Widget _controls() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
    color: Colors.black,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _btn(
          _micOn ? Icons.mic : Icons.mic_off,
          _micOn ? Colors.white : Colors.red,
          _toggleMic,
          label: _micOn ? 'Mute' : 'Muted',
        ),
        _btn(
          _camOn ? Icons.videocam : Icons.videocam_off,
          _camOn ? Colors.white : Colors.red,
          _toggleCam,
          label: _camOn ? 'Cam' : 'Cam off',
        ),
        // End meeting button
        GestureDetector(
          onTap: _endMeeting,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'End',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),
        _btn(
          _screenSharing ? Icons.stop_screen_share : Icons.present_to_all,
          _screenSharing ? Colors.orange : Colors.white,
          _toggleScreenShare,
          label: _screenSharing ? 'Stop' : 'Share',
        ),
        _btn(Icons.people, Colors.white, _showParticipants, label: 'Members'),
      ],
    ),
  );

  Widget _btn(
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
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.13),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        if (label != null) ...[
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 9),
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
                '${_peers.values.where((p) => p.connected).length + 1} Participants',
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
                  child: Icon(Icons.person, color: Colors.white, size: 18),
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
                      const Icon(Icons.mic_off, color: Colors.red, size: 16),
                    const SizedBox(width: 4),
                    const Icon(Icons.circle, color: Colors.green, size: 9),
                  ],
                ),
              ),
              ..._peers.values
                  .where((p) => p.connected)
                  .map(
                    (p) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(
                          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.circle,
                        color: Colors.green,
                        size: 9,
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
