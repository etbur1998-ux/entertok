import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/websocket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MeetingCallPage — real room-based video meeting
//
// Signaling flow:
//  HOST:
//    1. Send `meeting_host` → backend stores code→hostUserId
//    2. Wait for `meeting_joiner` events (joiner knocked)
//    3. For each joiner → create WebRTC peer connection → send offer to joinerId
//
//  JOINER:
//    1. Send `meeting_join` → backend returns host's real userId
//    2. Connect to host → receive their WebRTC offer → answer it
//    3. Also get offers from any other participants
// ─────────────────────────────────────────────────────────────────────────────

class MeetingCallPage extends StatefulWidget {
  final int roomId;
  final String meetingName;
  final String meetingCode;
  final bool isHost;

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

class _Participant {
  final int userId;
  String name;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool connected = false;

  _Participant({required this.userId, required this.name});
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

  final Map<int, _Participant> _participants = {};
  // ICE candidates buffered before remote desc set: peerId → list
  final Map<int, List<RTCIceCandidate>> _iceBuf = {};

  bool _micOn = true;
  bool _camOn = true;
  bool _screenSharing = false;
  MediaStream? _screenStream;
  bool _localReady = false;

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String _status = 'Connecting...';

  StreamSubscription? _subHosting, _subJoinResult, _subJoiner;
  StreamSubscription? _subOffer, _subAnswer, _subIce, _subHangup;

  // Retry join timer (joiner polls until host is found)
  Timer? _joinRetry;
  int _joinAttempts = 0;

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

    if (widget.isHost) {
      // Register in room — backend stores our userId for joiners to find
      _ws.meetingHost(widget.meetingCode);
      setState(() => _status = 'Waiting for participants...');
    } else {
      // Wait 1 second before first poll — gives host time to register
      setState(() => _status = 'Connecting to meeting...');
      await Future.delayed(const Duration(seconds: 1));
      _tryJoin();
    }
  }

  void _tryJoin() {
    _ws.meetingJoin(widget.meetingCode);
    setState(() => _status = 'Looking for host...');
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

  void _listenSignals() {
    // Host confirmed hosting
    _subHosting = _ws.onMeetingHosting.listen((data) {
      if (mounted) setState(() => _status = 'Waiting for participants...');
      debugPrint('Meeting: hosting confirmed for ${data['code']}');
    });

    // Joiner received host info
    _subJoinResult = _ws.onMeetingJoinResult.listen((data) async {
      final status = data['status']?.toString();
      if (status == 'no_host') {
        _joinAttempts++;
        if (mounted) {
          setState(() => _status = 'Waiting for host... ($_joinAttempts)');
        }
        if (_joinAttempts < 20) {
          _joinRetry?.cancel();
          _joinRetry = Timer(const Duration(seconds: 3), _tryJoin);
        } else if (mounted) {
          setState(() => _status = 'Host not found. Check the code.');
        }
        return;
      }
      // Found host — create connection and wait for their offer
      final hostId = (data['host_id'] as num?)?.toInt();
      final hostName = data['host_name']?.toString() ?? 'Host';
      if (hostId == null) return;
      _joinRetry?.cancel();
      debugPrint('Meeting: found host=$hostId, setting up...');
      await _createParticipant(hostId, name: hostName, sendOffer: false);
      setState(() => _status = 'Connecting to host...');
    });

    // Someone joined our meeting (host receives this)
    _subJoiner = _ws.onMeetingJoiner.listen((data) async {
      final joinerId = (data['joiner_id'] as num?)?.toInt();
      final joinerName = data['joiner_name']?.toString() ?? 'Participant';
      if (joinerId == null || !mounted) return;
      debugPrint('Meeting: joiner=$joinerId joined');
      // Create peer and send offer to joiner
      await _createParticipant(joinerId, name: joinerName, sendOffer: true);
      setState(() => _status = '');
    });

    // Incoming offer (joiner receives from host, or mesh peer)
    _subOffer = _ws.onWebRTCOffer.listen((data) async {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null) return;
      debugPrint('Meeting: offer from $fromId');
      final p =
          _participants[fromId] ??
          await _createParticipant(
            fromId,
            name: 'Participant',
            sendOffer: false,
          );
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      await p.pc!.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'offer',
        ),
      );
      // Flush buffered ICE
      for (final c in (_iceBuf[fromId] ?? [])) {
        try {
          await p.pc!.addCandidate(c);
        } catch (_) {}
      }
      _iceBuf.remove(fromId);

      final ans = await p.pc!.createAnswer();
      await p.pc!.setLocalDescription(ans);
      _ws.webrtcSendAnswer(fromId, ans.toMap());
      if (mounted) setState(() => _status = '');
    });

    // Answer from peer
    _subAnswer = _ws.onWebRTCAnswer.listen((data) async {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null) return;
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      final p = _participants[fromId];
      await p?.pc?.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'answer',
        ),
      );
      // Flush buffered ICE
      for (final c in (_iceBuf[fromId] ?? [])) {
        try {
          await p!.pc!.addCandidate(c);
        } catch (_) {}
      }
      _iceBuf.remove(fromId);
    });

    // ICE candidate
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
      final p = _participants[fromId];
      if (p?.pc != null) {
        try {
          await p!.pc!.addCandidate(cand);
        } catch (_) {}
      } else {
        _iceBuf.putIfAbsent(fromId, () => []).add(cand);
      }
    });

    // Hangup
    _subHangup = _ws.onWebRTCHangup.listen((data) {
      final fromId = (data['from_user_id'] as num?)?.toInt();
      if (fromId == null || !mounted) return;
      setState(() {
        _participants[fromId]?.renderer.srcObject = null;
        _participants[fromId]?.connected = false;
      });
    });
  }

  Future<_Participant> _createParticipant(
    int uid, {
    required String name,
    required bool sendOffer,
  }) async {
    if (_participants.containsKey(uid)) return _participants[uid]!;
    final p = _Participant(userId: uid, name: name);
    await p.init();
    _participants[uid] = p;

    p.pc = await createPeerConnection(_iceConfig);
    _localStream?.getTracks().forEach(
      (t) async => await p.pc!.addTrack(t, _localStream!),
    );

    p.pc!.onIceCandidate = (c) {
      if (c.candidate != null) _ws.webrtcSendIce(uid, c.toMap());
    };

    p.pc!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          p.renderer.srcObject = event.streams.first;
          p.connected = true;
          _status = '';
        });
        _startTimer();
      }
    };

    p.pc!.onConnectionState = (s) {
      if (!mounted) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          p.connected = true;
          _status = '';
        });
        _startTimer();
      } else if (s ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => p.connected = false);
      }
    };

    if (sendOffer) {
      final offer = await p.pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await p.pc!.setLocalDescription(offer);
      _ws.webrtcSendOffer(uid, offer.toMap());
      debugPrint('Meeting: sent offer to $uid');
    }

    if (mounted) setState(() {});
    return p;
  }

  void _startTimer() {
    if (_timer?.isActive == true) return;
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
        for (final p in _participants.values) {
          final senders = await p.pc?.getSenders() ?? [];
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
        for (final p in _participants.values) {
          final senders = await p.pc?.getSenders() ?? [];
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
        debugPrint('Screen share: $e');
      }
    }
  }

  void _endMeeting() {
    _ws.meetingLeave(widget.meetingCode);
    for (final uid in _participants.keys) {
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
    _subHosting?.cancel();
    _subJoinResult?.cancel();
    _subJoiner?.cancel();
    _subOffer?.cancel();
    _subAnswer?.cancel();
    _subIce?.cancel();
    _subHangup?.cancel();
    _timer?.cancel();
    _joinRetry?.cancel();
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    for (final p in _participants.values) {
      p.dispose();
    }
    _localStream?.dispose();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _participants.values.where((p) => p.connected).length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          _status.isNotEmpty
                              ? _status
                              : connected > 0
                              ? '${connected + 1} participants · $_elapsedStr'
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
            if (_screenSharing)
              Container(
                width: double.infinity,
                color: Colors.orange.withOpacity(0.88),
                padding: const EdgeInsets.symmetric(vertical: 6),
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
            Expanded(child: _grid()),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _grid() {
    final connected = _participants.values.where((p) => p.connected).toList();
    // Show waiting overlay when no one connected
    if (connected.isEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _localTile(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 80),
                Icon(
                  Icons.link,
                  size: 44,
                  color: Colors.white.withOpacity(0.35),
                ),
                const SizedBox(height: 10),
                Text(
                  'Share code: ${widget.meetingCode}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _status.isNotEmpty
                      ? _status
                      : 'Waiting for others to join...',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final tiles = <Widget>[_localTile()];
    for (final p in connected) {
      tiles.add(_remoteTile(p));
    }
    final cols = tiles.length <= 1
        ? 1
        : tiles.length <= 4
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
        Positioned(bottom: 6, left: 6, child: _tag('You', !_micOn)),
      ],
    ),
  );

  Widget _remoteTile(_Participant p) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Stack(
      fit: StackFit.expand,
      children: [
        p.renderer.srcObject != null
            ? RTCVideoView(
                p.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Container(
                color: const Color(0xFF1A1A2E),
                child: Center(
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.blue,
                    child: Text(
                      p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
        Positioned(bottom: 6, left: 6, child: _tag(p.name, false)),
      ],
    ),
  );

  Widget _tag(String n, bool muted) => Container(
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
          n,
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
    color: Colors.black,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
        _btn(Icons.people, Colors.white, _showPeople, label: 'Members'),
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

  void _showPeople() {
    final connected = _participants.values.where((p) => p.connected).toList();
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
                '${connected.length + 1} Participants',
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
                trailing: const Icon(
                  Icons.circle,
                  color: Colors.green,
                  size: 9,
                ),
              ),
              ...connected.map(
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
