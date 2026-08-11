import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/websocket_service.dart';

enum CallState { connecting, connected, ended }

enum CallType { video, audio }

// ─────────────────────────────────────────────────────────────────────────────
// CallPage — 1-to-1 audio or video call
//
// Two entry modes:
//  • Outgoing (isIncoming=false, shouldOffer=true):
//      _init → getMedia → setupPc → createOffer → wait for answer
//  • Incoming via global dialog (isIncoming=true, initialOffer=sdp):
//      _init → getMedia → setupPc → setRemoteDescription(initialOffer)
//              → createAnswer → send answer → wait for ICE to connect
//
// ICE candidates that arrive before remote description is set are buffered
// and applied once setRemoteDescription completes.
// ─────────────────────────────────────────────────────────────────────────────
class CallPage extends StatefulWidget {
  final int peerId;
  final String peerName;
  final String? peerAvatar;
  final CallType callType;
  final bool isIncoming;
  final bool shouldOffer;
  final Map<String, dynamic>?
  initialOffer; // pre-captured SDP from global listener

  const CallPage({
    super.key,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    required this.callType,
    this.isIncoming = false,
    this.shouldOffer = true,
    this.initialOffer,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _local = RTCVideoRenderer();
  final RTCVideoRenderer _remote = RTCVideoRenderer();

  CallState _state = CallState.connecting;
  bool _micOn = true;
  bool _camOn = true;
  bool _screenSharing = false; // ← screen share active
  MediaStream? _screenStream; // ← screen capture stream
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  // ICE candidate buffer — holds candidates until remote desc is set
  final List<RTCIceCandidate> _iceBuf = [];
  bool _remoteDescSet = false;

  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _subAnswer, _subIce, _subHangup;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _local.initialize();
    await _remote.initialize();

    _listenSignals();

    if (widget.isIncoming && widget.initialOffer != null) {
      // ── Incoming call with pre-captured offer ──────────────────────────
      await _getMedia();
      await _setupPc();
      await _processOffer(widget.initialOffer!);
    } else if (!widget.isIncoming) {
      // ── Outgoing call ──────────────────────────────────────────────────
      await _getMedia();
      await _setupPc();
      if (widget.shouldOffer) await _createOffer();
    }
    // if isIncoming but no initialOffer → wait for offer via _listenSignals
  }

  void _listenSignals() {
    // ICE candidates — buffer if remote desc not set yet
    _subIce = _ws.onWebRTCIce.listen((data) async {
      if ((data['from_user_id'] as num?)?.toInt() != widget.peerId) return;
      final c = data['data'] as Map<String, dynamic>? ?? {};
      if (c.isEmpty) return;
      final cand = RTCIceCandidate(
        c['candidate'] as String? ?? '',
        c['sdpMid'] as String? ?? '',
        (c['sdpMLineIndex'] as num?)?.toInt() ?? 0,
      );
      if (_remoteDescSet && _pc != null) {
        try {
          await _pc!.addCandidate(cand);
        } catch (_) {}
      } else {
        _iceBuf.add(cand); // buffer until remote desc is ready
      }
    });

    // Answer (for outgoing calls)
    _subAnswer = _ws.onWebRTCAnswer.listen((data) async {
      if ((data['from_user_id'] as num?)?.toInt() != widget.peerId) return;
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      if (_pc == null) return;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'answer',
        ),
      );
      _remoteDescSet = true;
      await _flushIceBuf();
      debugPrint('CallPage: remote answer set, ICE buf flushed');
    });

    // Hangup
    _subHangup = _ws.onWebRTCHangup.listen((data) {
      if ((data['from_user_id'] as num?)?.toInt() != widget.peerId) return;
      _endCall(remote: true);
    });
  }

  // ── Process incoming SDP offer and send answer ─────────────────────────────
  Future<void> _processOffer(Map<String, dynamic> sdpMap) async {
    if (_pc == null) return;
    try {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'offer',
        ),
      );
      _remoteDescSet = true;
      await _flushIceBuf();

      final ans = await _pc!.createAnswer();
      await _pc!.setLocalDescription(ans);
      _ws.webrtcSendAnswer(widget.peerId, ans.toMap());
      debugPrint(
        'CallPage: offer processed, answer sent to peer=${widget.peerId}',
      );
    } catch (e) {
      debugPrint('CallPage _processOffer error: $e');
    }
  }

  // ── Flush buffered ICE candidates ──────────────────────────────────────────
  Future<void> _flushIceBuf() async {
    if (_pc == null) return;
    for (final c in _iceBuf) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _iceBuf.clear();
  }

  // ── Media ──────────────────────────────────────────────────────────────────
  Future<void> _getMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.callType == CallType.video
            ? {'facingMode': 'user', 'width': 640, 'height': 480}
            : false,
      });
      _local.srcObject = _localStream;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('CallPage _getMedia error: $e');
    }
  }

  // ── Peer connection setup ──────────────────────────────────────────────────
  Future<void> _setupPc() async {
    _pc = await createPeerConnection(_iceConfig);

    // Add local tracks
    _localStream?.getTracks().forEach(
      (t) async => await _pc!.addTrack(t, _localStream!),
    );

    // Send our ICE candidates to peer
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        _ws.webrtcSendIce(widget.peerId, c.toMap());
      }
    };

    // Remote track → show video / mark connected
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remote.srcObject = event.streams.first;
          _state = CallState.connected;
        });
        _startTimer();
      }
    };

    // Connection state changes
    _pc!.onConnectionState = (s) {
      if (!mounted) return;
      debugPrint('CallPage connectionState: $s');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (mounted) setState(() => _state = CallState.connected);
        _startTimer();
      } else if (s ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endCall();
      }
    };

    // ICE connection state for extra signal
    _pc!.onIceConnectionState = (s) {
      debugPrint('CallPage ICE state: $s');
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (mounted) setState(() => _state = CallState.connected);
        _startTimer();
      }
    };
  }

  // ── Create offer (outgoing) ────────────────────────────────────────────────
  Future<void> _createOffer() async {
    if (_pc == null) return;
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.callType == CallType.video,
    });
    await _pc!.setLocalDescription(offer);
    _ws.webrtcSendOffer(widget.peerId, offer.toMap());
    debugPrint('CallPage: offer sent to peer=${widget.peerId}');
  }

  // ── Timer ──────────────────────────────────────────────────────────────────
  void _startTimer() {
    if (_timer?.isActive == true) return; // don't start twice
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  String get _elapsedStr {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Controls ───────────────────────────────────────────────────────────────
  void _toggleMic() {
    setState(() => _micOn = !_micOn);
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _micOn);
  }

  void _toggleCam() {
    if (widget.callType != CallType.video) return;
    setState(() => _camOn = !_camOn);
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _camOn);
  }

  // ── Screen sharing ─────────────────────────────────────────────────────────
  Future<void> _toggleScreenShare() async {
    if (_screenSharing) {
      await _stopScreenShare();
    } else {
      await _startScreenShare();
    }
  }

  Future<void> _startScreenShare() async {
    try {
      // getDisplayMedia shows the OS screen/window picker
      _screenStream = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': false, // system audio not needed for most cases
      });

      if (_pc == null || !mounted) return;

      final screenTrack = _screenStream!.getVideoTracks().first;

      // Replace the existing video sender track with the screen track
      final senders = await _pc!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(screenTrack);
          break;
        }
      }

      // Update local preview to show the screen
      _local.srcObject = _screenStream;

      // When user stops sharing from OS-level (e.g. clicks "Stop sharing")
      screenTrack.onEnded = () {
        _stopScreenShare();
      };

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
      debugPrint('Screen share error: $e');
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
    if (_pc == null) return;

    // Stop the screen stream
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    _screenStream = null;

    // Restore camera track
    if (_localStream != null) {
      final camTrack = _localStream!.getVideoTracks().firstOrNull;
      if (camTrack != null) {
        final senders = await _pc!.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(camTrack);
            break;
          }
        }
      }
      // Restore local preview to camera
      _local.srcObject = _localStream;
    }

    setState(() {
      _screenSharing = false;
      _camOn = widget.callType == CallType.video;
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

  void _endCall({bool remote = false}) {
    if (!remote) _ws.webrtcHangup(widget.peerId);
    _timer?.cancel();
    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    _pc?.close();
    _localStream?.dispose();
    if (mounted) {
      setState(() => _state = CallState.ended);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _subAnswer?.cancel();
    _subIce?.cancel();
    _subHangup?.cancel();
    _timer?.cancel();
    _pc?.close();
    _localStream?.dispose();
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_state == CallState.ended) return _endedScreen();
    if (widget.callType == CallType.audio) return _audioScreen();
    return _videoScreen();
  }

  // ─── Audio call screen ────────────────────────────────────────────────────
  Widget _audioScreen() => Scaffold(
    backgroundColor: const Color(0xFF1A1A2E),
    body: SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: Colors.white,
                size: 32,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Column(
            children: [
              _avatar(96),
              const SizedBox(height: 20),
              Text(
                widget.peerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _state == CallState.connected ? _elapsedStr : 'Connecting...',
                style: TextStyle(color: Colors.grey[400], fontSize: 16),
              ),
              if (_state == CallState.connecting)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _pulseRings(),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ctrlBtn(
                      _micOn ? Icons.mic : Icons.mic_off,
                      _micOn ? Colors.white : Colors.red,
                      _toggleMic,
                      label: _micOn ? 'Mute' : 'Unmuted',
                    ),
                    _ctrlBtn(
                      Icons.volume_up,
                      Colors.white,
                      () {},
                      label: 'Speaker',
                    ),
                    _ctrlBtn(
                      Icons.dialpad,
                      Colors.white,
                      () {},
                      label: 'Keypad',
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: _endCall,
                  child: _roundBtn(
                    Icons.call_end,
                    Colors.red,
                    72,
                    label: 'End',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // ─── Video call screen ────────────────────────────────────────────────────
  Widget _videoScreen() => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        // Remote video full screen
        _remote.srcObject != null
            ? RTCVideoView(
                _remote,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Container(
                color: const Color(0xFF1A1A2E),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _avatar(72),
                      const SizedBox(height: 14),
                      Text(
                        widget.peerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _state == CallState.connected
                            ? _elapsedStr
                            : 'Connecting...',
                        style: TextStyle(color: Colors.grey[400]),
                      ),

                      // Screen sharing banner (shown below the top bar)
                      if (_screenSharing)
                        Positioned(
                          top: 60,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            color: Colors.orange.withOpacity(0.88),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.present_to_all,
                                  color: Colors.white,
                                  size: 18,
                                ),
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
                        ),
                      if (_state == CallState.connecting) ...[
                        const SizedBox(height: 16),
                        _pulseRings(),
                      ],
                    ],
                  ),
                ),
              ),

        // Local PiP
        if (_localStream != null && _camOn)
          Positioned(
            top: 48,
            right: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 100,
                height: 140,
                child: RTCVideoView(
                  _local,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),
          ),

        // Top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
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
                  const Spacer(),
                  Column(
                    children: [
                      Text(
                        widget.peerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _state == CallState.connected
                            ? _elapsedStr
                            : 'Connecting...',
                        style: TextStyle(
                          color: _state == CallState.connected
                              ? Colors.green[300]
                              : Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ctrlBtn(
                    _micOn ? Icons.mic : Icons.mic_off,
                    _micOn ? Colors.white : Colors.red,
                    _toggleMic,
                    label: _micOn ? 'Mute' : 'Muted',
                  ),
                  _ctrlBtn(
                    _camOn ? Icons.videocam : Icons.videocam_off,
                    _camOn ? Colors.white : Colors.red,
                    _toggleCam,
                    label: _camOn ? 'Cam off' : 'Cam on',
                  ),
                  GestureDetector(
                    onTap: _endCall,
                    child: _roundBtn(Icons.call_end, Colors.red, 64),
                  ),
                  // ── Screen share ──────────────────────────────
                  _ctrlBtn(
                    _screenSharing
                        ? Icons.stop_screen_share
                        : Icons.present_to_all,
                    _screenSharing ? Colors.orange : Colors.white,
                    _toggleScreenShare,
                    label: _screenSharing ? 'Stop' : 'Share',
                  ),
                  _ctrlBtn(
                    Icons.volume_up,
                    Colors.white,
                    () {},
                    label: 'Speaker',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  // ─── Ended screen ─────────────────────────────────────────────────────────
  Widget _endedScreen() => Scaffold(
    backgroundColor: const Color(0xFF1A1A2E),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.call_end, color: Colors.red, size: 64),
          const SizedBox(height: 20),
          const Text(
            'Call ended',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_elapsed.inSeconds > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Duration: $_elapsedStr',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    ),
  );

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Widget _avatar(double r) {
    final pic = widget.peerAvatar;
    if (pic != null && pic.isNotEmpty) {
      return CircleAvatar(radius: r, backgroundImage: NetworkImage(pic));
    }
    return CircleAvatar(
      radius: r,
      backgroundColor: Colors.deepPurple,
      child: Text(
        widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: r * 0.55,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, Color color, double size, {String? label}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ],
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
            color: Colors.white.withValues(alpha: 0.15),
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

  Widget _pulseRings() => SizedBox(
    width: 120,
    height: 120,
    child: Stack(
      alignment: Alignment.center,
      children: [
        ...List.generate(
          3,
          (i) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1.2),
            duration: Duration(milliseconds: 1200 + i * 400),
            curve: Curves.easeOut,
            builder: (_, v, __) => Container(
              width: 40 + i * 20.0,
              height: 40 + i * 20.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.deepPurple.withValues(
                    alpha: (1.2 - v).clamp(0, 0.6),
                  ),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        _avatar(20),
      ],
    ),
  );
}
