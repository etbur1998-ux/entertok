import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/websocket_service.dart';

class RandomVideoPage extends StatefulWidget {
  const RandomVideoPage({super.key});
  @override
  State<RandomVideoPage> createState() => _RandomVideoPageState();
}

enum _VState { idle, searching, connected, disconnected }

class _RandomVideoPageState extends State<RandomVideoPage>
    with WidgetsBindingObserver {
  // ─── WebRTC ───────────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer _local = RTCVideoRenderer();
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  bool _rendersReady = false;

  // ─── State ────────────────────────────────────────────────────────────────
  _VState _state = _VState.idle;
  int _peerId = 0;
  String _peerName = 'Stranger';
  String _peerAvatar = '';
  bool _shouldOffer = false;
  int _onlineCount = 512;
  Timer? _onlineTimer;
  Timer? _searchTimeout;

  // ─── Controls ─────────────────────────────────────────────────────────────
  bool _micOn = true;
  bool _camOn = true;
  bool _chatOpen = true; // chat panel visible by default

  // ─── Chat ─────────────────────────────────────────────────────────────────
  final List<Map<String, String>> _msgs = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _peerTyping = false; // peer is currently typing
  Timer? _typingDebounce; // our outgoing typing debounce
  Timer? _peerTypingClear; // auto-clear peer typing after timeout

  // ─── WebSocket ────────────────────────────────────────────────────────────
  final WebSocketService _ws = WebSocketService();
  StreamSubscription? _subMatched,
      _subWaiting,
      _subOffer,
      _subAnswer,
      _subIce,
      _subHangup,
      _subChat,
      _subCallTyping;

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
    WidgetsBinding.instance.addObserver(this);
    _initRenderers();
    _onlineTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted)
        setState(() => _onlineCount += DateTime.now().second.isEven ? 3 : -2);
    });
    _listenSignals();
  }

  Future<void> _initRenderers() async {
    await _local.initialize();
    await _remote.initialize();
    if (mounted) setState(() => _rendersReady = true);
  }

  void _listenSignals() {
    _subMatched = _ws.onWebRTCMatched.listen((data) async {
      _peerId = (data['peer_id'] as num?)?.toInt() ?? 0;
      _peerName = data['peer_name']?.toString() ?? 'Stranger';
      _peerAvatar = data['peer_avatar']?.toString() ?? '';
      _shouldOffer = data['should_offer'] == true;
      _searchTimeout?.cancel();
      await _setupPc();
      if (_shouldOffer) await _createOffer();
    });

    _subWaiting = _ws.onWebRTCWaiting.listen((_) {
      if (mounted) setState(() => _state = _VState.searching);
      _searchTimeout = Timer(const Duration(seconds: 25), () {
        if (mounted && _state == _VState.searching) _simulateMatch();
      });
    });

    _subOffer = _ws.onWebRTCOffer.listen((data) async {
      // Always update peerId from the offer sender
      final fromId = (data['from_user_id'] as num?)?.toInt() ?? 0;
      if (fromId != 0 && _peerId == 0) {
        _peerId = fromId;
        debugPrint('RandomVideo: peerId set from offer → $_peerId');
      }
      if (_pc == null) await _setupPc();
      final sdp = data['data'] as Map<String, dynamic>? ?? {};
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          sdp['sdp'] as String? ?? '',
          sdp['type'] as String? ?? 'offer',
        ),
      );
      final ans = await _pc!.createAnswer();
      await _pc!.setLocalDescription(ans);
      _ws.webrtcSendAnswer(_peerId, ans.toMap());
    });

    _subAnswer = _ws.onWebRTCAnswer.listen((data) async {
      final sdp = data['data'] as Map<String, dynamic>? ?? {};
      await _pc?.setRemoteDescription(
        RTCSessionDescription(
          sdp['sdp'] as String? ?? '',
          sdp['type'] as String? ?? 'answer',
        ),
      );
    });

    _subIce = _ws.onWebRTCIce.listen((data) async {
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

    _subHangup = _ws.onWebRTCHangup.listen((_) {
      if (mounted) _onPeerLeft();
    });

    _subChat = _ws.onWebRTCChat.listen((data) {
      if (!mounted) return;
      final text = data['content']?.toString() ?? '';
      debugPrint('RandomVideo: received chat content="$text" data=$data');
      if (text.isNotEmpty) {
        _peerTypingClear?.cancel();
        setState(() {
          _peerTyping = false;
          _msgs.add({'text': text, 'who': 'peer', 'ts': _ts()});
        });
        _scrollEnd();
      }
    });

    _subCallTyping = _ws.onWebRTCCallTyping.listen((data) {
      if (!mounted) return;
      final typing = data['is_typing'] == true;
      _peerTypingClear?.cancel();
      setState(() => _peerTyping = typing);
      if (typing) {
        // Auto-clear after 3s if no stop event arrives
        _peerTypingClear = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _peerTyping = false);
        });
      }
    });
  }

  // ─── WebRTC helpers ───────────────────────────────────────────────────────

  Future<void> _getMedia() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': 'user', 'width': 640, 'height': 480},
      });
      _local.srcObject = _localStream;
    } catch (_) {}
  }

  Future<void> _setupPc() async {
    _pc = await createPeerConnection(_iceConfig);
    _localStream?.getTracks().forEach(
      (t) async => await _pc!.addTrack(t, _localStream!),
    );
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null && _peerId != 0)
        _ws.webrtcSendIce(_peerId, c.toMap());
    };
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty && mounted) {
        setState(() {
          _remote.srcObject = event.streams.first;
          _state = _VState.connected;
        });
      }
    };
    _pc!.onConnectionState = (s) {
      if (!mounted) return;
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _state = _VState.connected);
      } else if (s ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _onPeerLeft();
      }
    };
  }

  Future<void> _createOffer() async {
    if (_pc == null || _peerId == 0) return;
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _pc!.setLocalDescription(offer);
    _ws.webrtcSendOffer(_peerId, offer.toMap());
  }

  void _simulateMatch() {
    if (mounted && _state == _VState.searching) {
      setState(() {
        _state = _VState.connected;
        _peerName = 'Stranger ${DateTime.now().second}';
      });
      _addSystemMsg('Connected! Say hello 👋');
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _start() async {
    setState(() {
      _state = _VState.searching;
      _msgs.clear();
      _peerId = 0;
    });
    await _getMedia();
    _ws.webrtcFindPeer();
  }

  void _hangup() {
    if (_peerId != 0) _ws.webrtcHangup(_peerId);
    _closePc();
    setState(() => _state = _VState.disconnected);
    _addSystemMsg('You ended the conversation');
  }

  void _next() {
    if (_peerId != 0) _ws.webrtcHangup(_peerId);
    _closePc();
    _msgs.clear();
    _start();
  }

  void _closePc() {
    _pc?.close();
    _pc = null;
    _remote.srcObject = null;
    _peerId = 0;
  }

  void _onPeerLeft() {
    _closePc();
    if (mounted) {
      _addSystemMsg('Stranger has disconnected');
      setState(() => _state = _VState.disconnected);
    }
  }

  void _toggleMic() {
    setState(() => _micOn = !_micOn);
    _localStream?.getAudioTracks().forEach((t) => t.enabled = _micOn);
  }

  void _toggleCam() {
    setState(() => _camOn = !_camOn);
    _localStream?.getVideoTracks().forEach((t) => t.enabled = _camOn);
  }

  void _flipCam() =>
      _localStream?.getVideoTracks().forEach((t) => Helper.switchCamera(t));

  void _sendChat() {
    final t = _chatCtrl.text.trim();
    if (t.isEmpty) return;
    debugPrint('RandomVideo: sending chat to peerId=$_peerId text="$t"');
    setState(() => _msgs.add({'text': t, 'who': 'me', 'ts': _ts()}));
    _chatCtrl.clear();
    if (_peerId != 0) {
      _ws.webrtcChatMsg(_peerId, t);
      _ws.webrtcSendTyping(_peerId, false);
    } else {
      debugPrint('RandomVideo: WARNING peerId=0, message not sent!');
    }
    _typingDebounce?.cancel();
    _scrollEnd();
  }

  void _onChatTyping(String value) {
    if (_peerId == 0) return;
    // Send "typing" immediately on first keystroke
    _ws.webrtcSendTyping(_peerId, true);
    // Debounce "stop typing" for 1.5s of inactivity
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (_peerId != 0) _ws.webrtcSendTyping(_peerId, false);
    });
  }

  void _addSystemMsg(String text) {
    if (mounted)
      setState(() => _msgs.add({'text': text, 'who': 'system', 'ts': _ts()}));
    _scrollEnd();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _ts() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
    } else if (s == AppLifecycleState.resumed && _camOn) {
      _localStream?.getVideoTracks().forEach((t) => t.enabled = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onlineTimer?.cancel();
    _searchTimeout?.cancel();
    _subMatched?.cancel();
    _subWaiting?.cancel();
    _subOffer?.cancel();
    _subAnswer?.cancel();
    _subIce?.cancel();
    _subHangup?.cancel();
    _subChat?.cancel();
    _subCallTyping?.cancel();
    _typingDebounce?.cancel();
    _peerTypingClear?.cancel();
    if (_peerId != 0) _ws.webrtcHangup(_peerId);
    _ws.webrtcCancelFind();
    _pc?.close();
    _localStream?.dispose();
    _local.dispose();
    _remote.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _VState.idle:
        return _idleScreen();
      case _VState.searching:
        return _searchingScreen();
      case _VState.connected:
        return _connectedScreen();
      case _VState.disconnected:
        return _disconnectedScreen();
    }
  }

  // ─── Idle Screen ──────────────────────────────────────────────────────────

  Widget _idleScreen() => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Column(
        children: [
          // Back button + title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text(
                    'Video Random Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Header card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4A148C), Color(0xFFEC4899)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Omegle-style Video Chat',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Real P2P video + text chat with strangers',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '$_onlineCount online now',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Camera preview
                  if (_rendersReady && _localStream != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 160,
                        width: double.infinity,
                        child: RTCVideoView(
                          _local,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam_off,
                              color: Colors.grey,
                              size: 36,
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Camera preview',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  // Rules
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        ...[
                          ('🎥', 'Keep camera on for better connections'),
                          ('💬', 'Text chat available during video calls'),
                          ('⏭️', 'Tap "Next" to skip to a new person anytime'),
                          ('🚫', 'No inappropriate content — be kind'),
                          ('🔒', 'Anonymous — you appear as "Stranger"'),
                        ].map(
                          (r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Text(
                                  r.$1,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    r.$2,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Start button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.videocam_rounded, size: 24),
                      label: const Text(
                        'Start Video Chat',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEC4899),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.grey,
                      size: 16,
                    ),
                    label: const Text(
                      'Go Back',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ─── Searching Screen ─────────────────────────────────────────────────────

  Widget _searchingScreen() => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          _ws.webrtcCancelFind();
          _searchTimeout?.cancel();
          setState(() => _state = _VState.idle);
        },
      ),
      title: const Text(
        'Finding someone...',
        style: TextStyle(color: Colors.white),
      ),
    ),
    body: Column(
      children: [
        if (_rendersReady && _localStream != null)
          Container(
            height: 200,
            color: Colors.grey[900],
            child: RTCVideoView(
              _local,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 5,
                      color: Color(0xFFEC4899),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Looking for a stranger...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_onlineCount people online',
                style: TextStyle(color: Colors.grey[400]),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      _ws.webrtcCancelFind();
                      _searchTimeout?.cancel();
                      setState(() {
                        _state = _VState.idle;
                        _msgs.clear();
                      });
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    label: const Text(
                      'Back',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      _ws.webrtcCancelFind();
                      _searchTimeout?.cancel();
                      _start();
                    },
                    icon: const Icon(Icons.refresh, color: Color(0xFFEC4899)),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(color: Color(0xFFEC4899)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEC4899)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
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
  );

  // ─── Connected Screen ─────────────────────────────────────────────────────

  Widget _connectedScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar with Back + peer info + Next ──────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
              ),
              child: Row(
                children: [
                  // Back → asks to confirm
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: _confirmLeave,
                  ),
                  const SizedBox(width: 6),
                  // Peer avatar
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.deepPurple,
                    backgroundImage: _peerAvatar.isNotEmpty
                        ? NetworkImage(_peerAvatar)
                        : null,
                    child: _peerAvatar.isEmpty
                        ? Text(
                            _peerName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  // Peer name + LIVE
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _peerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Row(
                          children: const [
                            Icon(Icons.circle, color: Colors.green, size: 8),
                            SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Find Next button (always visible, prominent)
                  GestureDetector(
                    onTap: _next,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC4899),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Next',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Video + Chat split view ────────────────────────────────────────
            Expanded(
              child: _chatOpen
                  ? _splitView() // video + chat side by side / stacked
                  : _fullVideoView(),
            ),
            // ── Bottom controls ───────────────────────────────────────────────
            _bottomControls(),
          ],
        ),
      ),
    );
  }

  // Split: video on top, chat on bottom (portrait-friendly)
  Widget _splitView() {
    return Column(
      children: [
        // Video area (top half)
        Flexible(
          flex: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Remote
              _remote.srcObject != null && _rendersReady
                  ? RTCVideoView(
                      _remote,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
                      color: Colors.grey[900],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.deepPurple,
                              backgroundImage: _peerAvatar.isNotEmpty
                                  ? NetworkImage(_peerAvatar)
                                  : null,
                              child: _peerAvatar.isEmpty
                                  ? Text(
                                      _peerName[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _peerName,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
              // Local PiP
              if (_rendersReady && _localStream != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: _flipCam,
                    child: Container(
                      width: 80,
                      height: 110,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white30, width: 1.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: _camOn
                            ? RTCVideoView(
                                _local,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              )
                            : Container(
                                color: Colors.grey[800],
                                child: const Center(
                                  child: Icon(
                                    Icons.videocam_off,
                                    color: Colors.white54,
                                    size: 22,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Divider with chat toggle
        GestureDetector(
          onTap: () => setState(() => _chatOpen = !_chatOpen),
          child: Container(
            height: 28,
            color: Colors.grey[900],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.drag_handle, color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Chat',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.grey[500],
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        // Chat area (bottom half)
        Flexible(flex: 1, child: _chatPanel()),
      ],
    );
  }

  // Full video with chat overlay toggle
  Widget _fullVideoView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _remote.srcObject != null && _rendersReady
            ? RTCVideoView(
                _remote,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Container(color: Colors.grey[900]),
        if (_rendersReady && _localStream != null)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _flipCam,
              child: Container(
                width: 90,
                height: 130,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white30, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _camOn
                      ? RTCVideoView(
                          _local,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: Icon(
                              Icons.videocam_off,
                              color: Colors.white54,
                              size: 28,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        // Chat toggle button
        Positioned(
          bottom: 8,
          left: 8,
          child: GestureDetector(
            onTap: () => setState(() => _chatOpen = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_msgs.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chatPanel() => Column(
    children: [
      // Messages
      Expanded(
        child: _msgs.isEmpty && !_peerTyping
            ? Center(
                child: Text(
                  'Say hello! 👋',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              )
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                itemCount: _msgs.length + (_peerTyping ? 1 : 0),
                itemBuilder: (_, i) {
                  // Typing indicator as last item
                  if (_peerTyping && i == _msgs.length) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                            bottomLeft: Radius.circular(2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TypingDot(delay: 0),
                            const SizedBox(width: 3),
                            _TypingDot(delay: 150),
                            const SizedBox(width: 3),
                            _TypingDot(delay: 300),
                          ],
                        ),
                      ),
                    );
                  }
                  final m = _msgs[i];
                  final who = m['who'] ?? '';
                  if (who == 'system') {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            m['text'] ?? '',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  final isMe = who == 'me';
                  return Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFFEC4899).withValues(alpha: 0.9)
                            : Colors.grey[800],
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(isMe ? 14 : 2),
                          bottomRight: Radius.circular(isMe ? 2 : 14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            m['text'] ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            m['ts'] ?? '',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      // Input row
      Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        color: Colors.grey[900],
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendChat(),
                onChanged: _onChatTyping,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey[850],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendChat,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFFEC4899),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _bottomControls() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: Colors.black,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ctrlBtn(
          _micOn ? Icons.mic : Icons.mic_off,
          _micOn ? Colors.white : Colors.red,
          _toggleMic,
          'Mic',
        ),
        _ctrlBtn(
          _camOn ? Icons.videocam : Icons.videocam_off,
          _camOn ? Colors.white : Colors.red,
          _toggleCam,
          'Camera',
        ),
        _ctrlBtn(Icons.flip_camera_ios, Colors.white70, _flipCam, 'Flip'),
        _ctrlBtn(
          _chatOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
          _chatOpen ? const Color(0xFFEC4899) : Colors.white70,
          () => setState(() => _chatOpen = !_chatOpen),
          'Chat',
        ),
        _ctrlBtn(Icons.call_end, Colors.red, _hangup, 'End'),
      ],
    ),
  );

  Widget _ctrlBtn(
    IconData icon,
    Color color,
    VoidCallback onTap,
    String label,
  ) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color == Colors.red
                ? Colors.red
                : Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color == Colors.red ? Colors.white : color,
            size: 20,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
      ],
    ),
  );

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Leave Chat?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Do you want to end this conversation?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stay', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _hangup();
              setState(() => _state = _VState.idle);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEC4899),
              foregroundColor: Colors.white,
            ),
            child: const Text('Leave'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _next();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Next Person'),
          ),
        ],
      ),
    );
  }

  // ─── Disconnected Screen ──────────────────────────────────────────────────

  Widget _disconnectedScreen() => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Column(
        children: [
          // Back button
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => setState(() {
                _state = _VState.idle;
                _msgs.clear();
              }),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_off_outlined,
                    size: 52,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Conversation Ended',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_peerName has left the chat',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(height: 28),
                // Chat replay (last messages)
                if (_msgs.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) {
                        final m = _msgs[i];
                        final isMe = m['who'] == 'me';
                        final isSystem = m['who'] == 'system';
                        if (isSystem)
                          return Center(
                            child: Text(
                              m['text'] ?? '',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                          );
                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? const Color(
                                      0xFFEC4899,
                                    ).withValues(alpha: 0.5)
                                  : Colors.grey[800],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              m['text'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _state = _VState.idle;
                        _msgs.clear();
                      }),
                      icon: const Icon(
                        Icons.home_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        'Home',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _next,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text(
                        'Next Person',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEC4899),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
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

// ─── Animated typing dot ──────────────────────────────────────────────────────
class _TypingDot extends StatefulWidget {
  final int delay; // ms delay before animation starts
  const _TypingDot({required this.delay});
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Colors.white70,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
