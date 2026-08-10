import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'pages/home_page.dart';
import 'pages/message_page.dart';
import 'pages/market_page.dart';
import 'pages/discovery_page.dart';
import 'pages/connect_page.dart';
import 'pages/upload_page.dart';
import 'pages/splash_page.dart';
import 'pages/auth_page.dart';
import 'pages/marketing_page.dart';
import 'pages/live_page.dart';
import 'pages/settings_page.dart';
import 'pages/wallet_page.dart';
import 'pages/edit_profile_page.dart';
import 'pages/saved_page.dart';
import 'pages/help_page.dart';
import 'pages/group_call_page.dart';
import 'pages/call_page.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'services/websocket_service.dart';

/// Global navigator key — lets us push routes from anywhere (e.g. WS listener)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global group-call invite listener — started once after login
StreamSubscription? _globalGroupCallSub;

/// Global 1-to-1 incoming call listener — shows ringing dialog from anywhere
StreamSubscription? _globalIncomingCallSub;

void startGlobalGroupCallListener() {
  _globalGroupCallSub?.cancel();
  _globalGroupCallSub = WebSocketService().onGroupCallInvite.listen((data) {
    final groupId = (data['group_id'] as num?)?.toInt();
    if (groupId == null) return;
    final groupName = data['group_name']?.toString() ?? 'Group Call';
    final callType = data['call_type']?.toString() ?? 'video';
    final callerUserId = (data['caller_id'] as num?)?.toInt();
    final callerName = data['caller_name']?.toString() ?? 'Someone';
    final callerAvatar = data['caller_avatar']?.toString() ?? '';

    debugPrint(
      '📞 GROUP CALL INVITE received: group=$groupName caller=$callerName',
    );

    navigatorKey.currentState?.push(
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

void startGlobalIncomingCallListener() {
  _globalIncomingCallSub?.cancel();
  _globalIncomingCallSub = WebSocketService().onWebRTCOffer.listen((data) {
    final fromId = (data['from_user_id'] as num?)?.toInt();
    final fromName = data['from_name']?.toString() ?? 'Someone';
    final fromAvatar = data['from_avatar']?.toString() ?? '';
    if (fromId == null) return;

    debugPrint('📲 INCOMING CALL from $fromName (id=$fromId)');

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    // Don't show dialog if CallPage is already on the navigator stack
    final currentRoute = ModalRoute.of(ctx);
    if (currentRoute?.settings.name == '/call') return;

    // Extract the SDP offer so CallPage can use it directly
    final sdpData = data['data'] as Map<String, dynamic>? ?? {};

    // Detect video vs audio from SDP (if sdp contains 'video' section)
    final sdpStr = sdpData['sdp']?.toString() ?? '';
    final isVideo = sdpStr.contains('m=video');

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => _IncomingCallDialog(
        sdpOffer: sdpData,
        fromId: fromId,
        fromName: fromName,
        fromAvatar: fromAvatar,
        isVideo: isVideo,
      ),
    );
  });
}

/// Start all global listeners at once — call after login/auto-login
Future<void> startAllGlobalListeners() async {
  final auth = AuthService();
  final userId = (auth.currentUser?['id'] as num?)?.toInt();

  startGlobalGroupCallListener();
  startGlobalIncomingCallListener();

  // Init and start push notifications
  final push = PushNotificationService();
  await push.init(userId: userId);
  push.startListening();
}

/// Global incoming call dialog widget
class _IncomingCallDialog extends StatelessWidget {
  final Map<String, dynamic> sdpOffer;
  final int fromId;
  final String fromName;
  final String fromAvatar;
  final bool isVideo;

  const _IncomingCallDialog({
    required this.sdpOffer,
    required this.fromId,
    required this.fromName,
    required this.fromAvatar,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          fromAvatar.isNotEmpty
              ? CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(fromAvatar),
                )
              : CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.deepPurple,
                  child: Text(
                    fromName.isNotEmpty ? fromName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
          const SizedBox(height: 16),
          Text(
            fromName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isVideo ? Icons.videocam : Icons.call,
                color: Colors.green,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                isVideo ? 'Incoming video call' : 'Incoming audio call',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        // Decline
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            WebSocketService().webrtcHangup(fromId);
          },
          icon: const Icon(Icons.call_end, color: Colors.red),
          label: const Text('Decline', style: TextStyle(color: Colors.red)),
        ),
        // Accept — pass the sdpOffer so CallPage can answer immediately
        ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => CallPage(
                  peerId: fromId,
                  peerName: fromName,
                  peerAvatar: fromAvatar.isNotEmpty ? fromAvatar : null,
                  callType: isVideo ? CallType.video : CallType.audio,
                  isIncoming: true,
                  shouldOffer: false,
                  initialOffer: sdpOffer, // ← key fix: pre-captured SDP
                ),
              ),
            );
          },
          icon: Icon(isVideo ? Icons.videocam : Icons.call),
          label: const Text('Accept'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // Required for Windows/Linux/macOS
  await AuthService().init();
  final token = AuthService().apiClient.token;
  if (token != null) {
    WebSocketService().connect(token);
    // Start after first frame so navigatorKey is attached
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await startAllGlobalListeners();
    });
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EnterTok',
      navigatorKey: navigatorKey, // ← attach global key
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashPage(),
        '/auth': (context) => const AuthPage(),
        '/home': (context) => const ResponsiveHomePage(),
      },
    );
  }
}

class ResponsiveHomePage extends StatefulWidget {
  const ResponsiveHomePage({super.key});
  @override
  State<ResponsiveHomePage> createState() => _ResponsiveHomePageState();
}

class _ResponsiveHomePageState extends State<ResponsiveHomePage>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _unreadNotifications = 0;
  int _unreadMessages = 0;
  StreamSubscription? _notifSub;
  StreamSubscription? _msgSub;
  StreamSubscription? _connSub;
  StreamSubscription? _groupCallSub;

  final _ws = WebSocketService();
  final _notifService = NotificationService();

  final List<NavigationItem> _navItems = [
    NavigationItem(icon: Icons.home_outlined, label: 'Home'),
    NavigationItem(icon: Icons.message_outlined, label: 'Message'),
    NavigationItem(icon: Icons.store_outlined, label: 'Market'),
    NavigationItem(icon: Icons.explore_outlined, label: 'Discover'),
    NavigationItem(icon: Icons.people_outline, label: 'Connect'),
  ];

  final List<NavigationItem> _moreMenuItems = [
    NavigationItem(icon: Icons.live_tv, label: 'Live'),
    NavigationItem(icon: Icons.campaign, label: 'Marketing'),
    NavigationItem(icon: Icons.account_balance_wallet, label: 'Wallet'),
    NavigationItem(icon: Icons.bookmark_outline, label: 'Saved'),
    NavigationItem(icon: Icons.settings_outlined, label: 'Settings'),
    NavigationItem(icon: Icons.help_outline, label: 'Help'),
    NavigationItem(icon: Icons.upload_rounded, label: 'Upload'),
    NavigationItem(icon: Icons.logout, label: 'Logout'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUnreadCounts();
    _subscribeRealtime();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground — reconnect WS if needed
      final token = AuthService().apiClient.token;
      if (token != null && !WebSocketService().isConnected) {
        WebSocketService().connect(token);
      }
      _loadUnreadCounts();
    }
  }

  Future<void> _loadUnreadCounts() async {
    try {
      final count = await _notifService.getUnreadCount();
      if (mounted) setState(() => _unreadNotifications = count);
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _notifSub = _ws.onNotification.listen((_) {
      if (mounted) setState(() => _unreadNotifications++);
    });
    _msgSub = _ws.onChatMessage.listen((_) {
      if (mounted && _selectedIndex != 1) setState(() => _unreadMessages++);
    });
    _connSub = _ws.onConnectionChange.listen((connected) {
      if (mounted && connected) _loadUnreadCounts();
    });
    // Group call invites handled globally via startGlobalGroupCallListener()
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifSub?.cancel();
    _msgSub?.cancel();
    _connSub?.cancel();
    _groupCallSub?.cancel();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == 5) {
      _showMoreSheet();
    } else {
      if (index == 1) setState(() => _unreadMessages = 0);
      setState(() => _selectedIndex = index);
    }
  }

  void _showMoreSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
            const SizedBox(height: 8),
            ..._moreMenuItems.map(
              (item) => ListTile(
                leading: Icon(item.icon, color: Colors.deepPurple),
                title: Text(item.label),
                onTap: () {
                  Navigator.pop(ctx);
                  _handleMore(item.label);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMore(String label) {
    switch (label) {
      case 'Live':
        _push(const LivePage());
        break;
      case 'Marketing':
        _push(const MarketingPage());
        break;
      case 'Wallet':
        _push(const WalletPage());
        break;
      case 'Saved':
        _push(const SavedPage());
        break;
      case 'Settings':
        _push(const SettingsPage());
        break;
      case 'Help':
        _push(const HelpPage());
        break;
      case 'Upload':
        _push(const UploadPage());
        break;
      case 'Logout':
        _confirmLogout();
        break;
    }
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService().logout();
              if (mounted)
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/auth', (_) => false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Real-time Notifications Panel ────────────────────────────────────────
  void _showNotifications() {
    setState(() => _unreadNotifications = 0);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotificationsPanel(notifService: _notifService),
    );
  }

  void _showProfile() {
    final user = AuthService().currentUser;
    final pic = user?['profile_image']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
            const SizedBox(height: 16),
            CircleAvatar(
              radius: 48,
              backgroundColor: Colors.deepPurple,
              backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
              child: pic.isEmpty
                  ? const Icon(Icons.person, size: 48, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              user?['full_name'] ?? 'User',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              '@${user?['username'] ?? 'username'}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat('${user?['post_count'] ?? 0}', 'Posts'),
                _stat(_fmt(user?['follower_count'] ?? 0), 'Followers'),
                _stat('${user?['following_count'] ?? 0}', 'Following'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _push(const EditProfilePage());
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _push(const SettingsPage());
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Settings'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _stat(String val, String label) => Column(
    children: [
      Text(
        val,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ],
  );

  String _fmt(dynamic count) {
    final n = (count as num?)?.toInt() ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 768 ? _mobile() : _desktop(),
    );
  }

  Widget _mobile() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_fill,
              color: Colors.deepPurple,
              size: 28,
            ),
            const SizedBox(width: 6),
            const Text(
              'EnterTok',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: Colors.grey[700]),
            onPressed: _showSearch,
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.notifications_outlined,
                  color: Colors.grey[700],
                ),
                onPressed: _showNotifications,
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _badge(_unreadNotifications),
                ),
            ],
          ),
          GestureDetector(onTap: _showProfile, child: _buildAvatar()),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _push(const WalletPage()),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Wallet',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex < 5 ? _selectedIndex : 0,
        onTap: _onNavTap,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: [
          ..._navItems.asMap().entries.map(
            (e) => BottomNavigationBarItem(
              icon: e.key == 1 && _unreadMessages > 0
                  ? Stack(
                      children: [
                        Icon(e.value.icon),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: _badge(_unreadMessages),
                        ),
                      ],
                    )
                  : Icon(e.value.icon),
              label: e.value.label,
            ),
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }

  Widget _badge(int count) => Container(
    padding: const EdgeInsets.all(2),
    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
    child: Text(
      '${count > 99 ? '99+' : count}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
    ),
  );

  Widget _buildAvatar() {
    final user = AuthService().currentUser;
    final pic = user?['profile_image']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.deepPurple,
        backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
        child: pic.isEmpty
            ? const Icon(Icons.person, color: Colors.white, size: 18)
            : null,
      ),
    );
  }

  Widget _desktop() {
    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_fill,
                  color: Colors.deepPurple,
                  size: 32,
                ),
                const SizedBox(width: 6),
                const Text(
                  'EnterTok',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 200,
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                _desktopNav(Icons.home_outlined, 'Home', 0),
                _desktopNav(Icons.message_outlined, 'Messages', 1),
                _desktopNav(Icons.store_outlined, 'Market', 2),
                _desktopNav(Icons.explore_outlined, 'Discover', 3),
                _desktopNav(Icons.people_outline, 'Connect', 4),
                _desktopNav(
                  Icons.live_tv,
                  'Live',
                  -1,
                  onTap: () => _push(const LivePage()),
                ),
                const SizedBox(width: 12),
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: _showNotifications,
                    ),
                    if (_unreadNotifications > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _badge(_unreadNotifications),
                      ),
                  ],
                ),
                GestureDetector(onTap: _showProfile, child: _buildAvatar()),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _push(const WalletPage()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.account_balance_wallet,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Wallet',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _desktopNav(
    IconData icon,
    String label,
    int index, {
    VoidCallback? onTap,
  }) {
    final selected = _selectedIndex == index;
    return InkWell(
      onTap: onTap ?? () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.deepPurple.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? Colors.deepPurple : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.deepPurple : Colors.grey[600],
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search users, videos, hashtags...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Trending',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['#fyp', '#viral', '#dance', '#music', '#tech', '#food']
                  .map((t) => ActionChip(label: Text(t), onPressed: () {}))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final screens = [
      const HomePage(),
      const MessagePage(),
      const MarketPage(),
      const DiscoveryPage(),
      const ConnectPage(),
    ];
    return screens[_selectedIndex < screens.length ? _selectedIndex : 0];
  }
}

// ─── Notifications Panel ──────────────────────────────────────────────────────
class _NotificationsPanel extends StatefulWidget {
  final NotificationService notifService;
  const _NotificationsPanel({required this.notifService});
  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.notifService.getNotifications();
      if (mounted) {
        setState(() {
          _notifications = result['notifications'] ?? [];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.comment;
      case 'follow':
        return Icons.person_add;
      case 'message':
        return Icons.message;
      default:
        return Icons.notifications;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return Colors.blue;
      case 'follow':
        return Colors.green;
      case 'message':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await widget.notifService.markAllAsRead();
                    await _load();
                  },
                  child: const Text('Mark all read'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notifications.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications yet',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: scrollCtrl,
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = _notifications[i];
                      final type = n['type']?.toString() ?? '';
                      final isRead = n['is_read'] == true;
                      final actor = n['actor'] ?? {};
                      final actorPic = actor['profile_image']?.toString() ?? '';
                      return ListTile(
                        tileColor: isRead
                            ? null
                            : Colors.deepPurple.withValues(alpha: 0.04),
                        leading: CircleAvatar(
                          backgroundColor: _colorFor(
                            type,
                          ).withValues(alpha: 0.15),
                          backgroundImage: actorPic.isNotEmpty
                              ? NetworkImage(actorPic)
                              : null,
                          child: actorPic.isEmpty
                              ? Icon(
                                  _iconFor(type),
                                  color: _colorFor(type),
                                  size: 20,
                                )
                              : null,
                        ),
                        title: Text(
                          '@${actor['username'] ?? 'user'} ${n['message'] ?? ''}',
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _timeAgo(n['created_at']?.toString()),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                        trailing: isRead
                            ? null
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.deepPurple,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        onTap: () async {
                          if (!isRead) {
                            await widget.notifService.markAsRead(n['id']);
                            _load();
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── NavigationItem ───────────────────────────────────────────────────────────
class NavigationItem {
  final IconData icon;
  final String label;
  NavigationItem({required this.icon, required this.label});
}
