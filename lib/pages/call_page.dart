import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/websocket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallPage — one-to-one video or audio call between two known users
// ─────────────────────────────────────────────────────────────────────────────

enum CallState { ringing, connecting, connected, ended }

enum CallType { video, audio }

class CallPage extends StatefulWidget {
  final int peerId;
  final String peerName;
  final String? peerAvatar;
  final CallType callType;
  final bool isIncoming; // true = we received the call
  final bool shouldOffer; // true = we create the SDP offer
  // Pre-captured SDP offer from global listener — passed so CallPage
  // doesn't miss the offer that was already received
  final Map<String, dynamic>? initialOffer;

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
  // ── WebRTC ─────────────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _local = RTCVideoRenderer();
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  bool _rendersReady = false;

  // ── State ──────────────────────────────────────────────────────────────────
  CallState _state = CallState.ringing;
  bool _micOn = true;
  bool _camOn = true;
  bool _speaker = true;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  // ── WS subscriptions ───────────────────────────────────────────────────────
  final WebSocketService _ws = WebSocketService();
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
    _init();
  }

  Future<void> _init() async {
    await _local.initialize();
    await _remote.initialize();
    if (mounted) setState(() => _rendersReady = true);
    _listenSignals();

    if (widget.isIncoming) {
      // Wait for user to accept — state stays ringing
    } else {
      // Outgoing call — get media then send offer
      await _getMedia();
      await _setupPc();
      if (widget.shouldOffer) await _createOffer();
      if (mounted) setState(() => _state = CallState.connecting);
    }
  }

  void _listenSignals() {
    _subOffer = _ws.onWebRTCOffer.listen((data) async {
      if ((data['from_user_id'] as num?)?.toInt() != widget.peerId) return;
      // Accept the offer
      if (_pc == null) {
        await _getMedia();
        await _setupPc();
      }
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'offer',
        ),
      );
      final ans = await _pc!.createAnswer();
      await _pc!.setLocalDescription(ans);
      _ws.webrtcSendAnswer(widget.peerId, ans.toMap());
      if (mounted) setState(() => _state = CallState.connecting);
    });

    _subAnswer = _ws.onWebRTCAnswer.listen((data) async {
      if ((data['from_user_id'] as num?)?.toInt() != widget.peerId) return;
      final sdpMap = data['data'] as Map<String, dynamic>? ?? {};
      await _pc?.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'answer',
        ),
      );
    });

    _subIce = _ws.onWebRTCIce.listen((data) async {
      if ((data['from_user_id'] as num?)?.toInt() != widget.peerId) return;
      final c = data['data'] as Map<String, dynamic>? ?? {};
      if (c.isNotEmpty) {
        try {
          await _pc?.addCandidate(
            RTCIceCandidate(
              c['candidate'] as String? ?? '',
              c['sdpMid'] as String? ?? '',
              (c['sdpMLineIndex'] as num?)?.toInt() ?? 0,
            ),
          );
        } catch (_) {}
      }
    });

    _subHangup = _ws.onWebRTCHangup.listen((data) {
      if ((data['from_user_id'] as num?)?.toInt() != widget.peerId) return;
      _endCall(remote: true);
    });
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
      debugPrint('_getMedia error: $e');
    }
  }

  Future<void> _setupPc() async {
    _pc = await createPeerConnection(_iceConfig);

    _localStream?.getTracks().forEach(
      (t) async => await _pc!.addTrack(t, _localStream!),
    );

    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) _ws.webrtcSendIce(widget.peerId, c.toMap());
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remote.srcObject = event.streams.first;
          _state = CallState.connected;
        });
        _startTimer();
      }
    };

    _pc!.onConnectionState = (s) {
      if (!mounted) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _state = CallState.connected);
        _startTimer();
      } else if (s ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _endCall();
      }
    };
  }

  Future<void> _createOffer() async {
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.callType == CallType.video,
    });
    await _pc!.setLocalDescription(offer);
    _ws.webrtcSendOffer(widget.peerId, offer.toMap());
  }

  // ── Timer ──────────────────────────────────────────────────────────────────

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

  // ── Accept incoming call ───────────────────────────────────────────────────

  Future<void> _acceptCall() async {
    await _getMedia();
    await _setupPc();
    if (mounted) setState(() => _state = CallState.connecting);

    // Process the pre-captured offer if it was passed in
    if (widget.initialOffer != null && widget.initialOffer!.isNotEmpty) {
      final sdpMap = widget.initialOffer!;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp'] as String? ?? '',
          sdpMap['type'] as String? ?? 'offer',
        ),
      );
      final ans = await _pc!.createAnswer();
      await _pc!.setLocalDescription(ans);
      _ws.webrtcSendAnswer(widget.peerId, ans.toMap());
    }
    // Otherwise _listenSignals' _subOffer will handle the next offer
  }

  // ── End call ───────────────────────────────────────────────────────────────

  void _endCall({bool remote = false}) {
    if (!remote) _ws.webrtcHangup(widget.peerId);
    _timer?.cancel();
    _pc?.close();
    _localStream?.dispose();
    if (mounted) {
      setState(() => _state = CallState.ended);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    }
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

  void _flipCam() {
    _localStream?.getVideoTracks().forEach((t) => Helper.switchCamera(t));
  }

  @override
  void dispose() {
    _subOffer?.cancel();
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
    if (_state == CallState.ringing && widget.isIncoming)
      return _incomingScreen();
    if (widget.callType == CallType.audio) return _audioCallScreen();
    return _videoCallScreen();
  }

  // ─── Incoming call screen ──────────────────────────────────────────────────

  Widget _incomingScreen() => Scaffold(
    backgroundColor: const Color(0xFF1A1A2E),
    body: SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              Text(
                widget.callType == CallType.video
                    ? 'Incoming Video Call'
                    : 'Incoming Audio Call',
                style: const TextStyle(color: Colors.white54, fontSize: 16),
              ),
              const SizedBox(height: 24),
              _avatar(80),
              const SizedBox(height: 16),
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
                widget.callType == CallType.video
                    ? '📹 Video call'
                    : '📞 Audio call',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Decline
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: _roundBtn(
                  Icons.call_end,
                  Colors.red,
                  72,
                  label: 'Decline',
                ),
              ),
              // Accept
              GestureDetector(
                onTap: _acceptCall,
                child: _roundBtn(
                  widget.callType == CallType.video
                      ? Icons.videocam
                      : Icons.call,
                  Colors.green,
                  72,
                  label: 'Accept',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // ─── Audio call screen ─────────────────────────────────────────────────────

  Widget _audioCallScreen() => Scaffold(
    backgroundColor: const Color(0xFF1A1A2E),
    body: SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top: back button
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

          // Center: avatar + name + status
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
                _state == CallState.connected
                    ? _elapsedStr
                    : _state == CallState.ringing
                    ? 'Calling...'
                    : 'Connecting...',
                style: TextStyle(color: Colors.grey[400], fontSize: 16),
              ),
              // Pulse animation when ringing
              if (_state == CallState.ringing || _state == CallState.connecting)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _pulseRings(),
                ),
            ],
          ),

          // Bottom controls
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Column(
              children: [
                // Secondary controls
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
                      _speaker ? Icons.volume_up : Icons.volume_off,
                      _speaker ? Colors.white : Colors.orange,
                      () => setState(() => _speaker = !_speaker),
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
                // End call button
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

  // ─── Video call screen ─────────────────────────────────────────────────────

  Widget _videoCallScreen() => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        // ── Remote video (full screen) ───────────────────────────────────
        if (_rendersReady && _remote.srcObject != null)
          RTCVideoView(
            _remote,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          Container(
            color: const Color(0xFF1A1A2E),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _avatar(80),
                  const SizedBox(height: 16),
                  Text(
                    widget.peerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _state == CallState.ringing
                        ? 'Calling...'
                        : _state == CallState.connecting
                        ? 'Connecting...'
                        : '',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  if (_state != CallState.connected) const SizedBox(height: 20),
                  if (_state != CallState.connected) _pulseRings(),
                ],
              ),
            ),
          ),

        // ── Local video (PiP corner) ─────────────────────────────────────
        if (_rendersReady && _localStream != null && _camOn)
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

        // ── Top bar ──────────────────────────────────────────────────────
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
                      if (_state == CallState.connected)
                        Text(
                          _elapsedStr,
                          style: TextStyle(
                            color: Colors.green[300],
                            fontSize: 12,
                          ),
                        )
                      else
                        Text(
                          _state == CallState.connecting
                              ? 'Connecting...'
                              : 'Calling...',
                          style: TextStyle(
                            color: Colors.grey[400],
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

        // ── Bottom controls ───────────────────────────────────────────────
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
                  // End call
                  GestureDetector(
                    onTap: _endCall,
                    child: _roundBtn(Icons.call_end, Colors.red, 64),
                  ),
                  _ctrlBtn(
                    Icons.flip_camera_ios,
                    Colors.white,
                    _flipCam,
                    label: 'Flip',
                  ),
                  _ctrlBtn(
                    _speaker ? Icons.volume_up : Icons.volume_off,
                    _speaker ? Colors.white : Colors.orange,
                    () => setState(() => _speaker = !_speaker),
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

  // ─── Ended screen ──────────────────────────────────────────────────────────

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

  // ─── Helpers ───────────────────────────────────────────────────────────────

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
