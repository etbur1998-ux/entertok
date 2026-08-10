import 'dart:async';
import 'package:flutter/material.dart';
import '../services/message_service.dart';
import '../services/user_service.dart';
import '../services/websocket_service.dart';
import 'message_page.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});
  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final MessageService _ms = MessageService();
  final WebSocketService _ws = WebSocketService();

  List<Map<String, dynamic>> _myGroups = [];
  bool _loading = true;

  // Realtime: track unread per group
  final Map<int, int> _unreadMap = {};
  StreamSubscription? _groupMsgSub;
  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadGroups();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _groupMsgSub = _ws.onGroupMessage.listen((msg) {
      final gid = (msg['group_id'] as num?)?.toInt();
      if (gid == null || !mounted) return;
      setState(() {
        _unreadMap[gid] = (_unreadMap[gid] ?? 0) + 1;
        // Update last_message preview in list
        final idx = _myGroups.indexWhere((g) => g['id'] == gid);
        if (idx != -1) {
          _myGroups[idx]['last_message'] = msg['content'] ?? '';
          _myGroups[idx]['last_message_at'] = DateTime.now().toIso8601String();
        }
      });
    });
  }

  Future<void> _loadGroups() async {
    setState(() => _loading = true);
    try {
      final groups = await _ms.getUserGroups();
      if (mounted) {
        setState(() {
          _myGroups = List<Map<String, dynamic>>.from(groups);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _groupMsgSub?.cancel();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static const _colors = [
    Color(0xFF7C3AED),
    Color(0xFFEC4899),
    Color(0xFF3B82F6),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFF8B5CF6),
  ];

  Color _groupColor(dynamic id) =>
      _colors[((id as int?) ?? 0) % _colors.length];

  String _fmt(String? ts) {
    if (ts == null) return '';
    final d = DateTime.tryParse(ts);
    if (d == null) return '';
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month && d.year == now.year) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}/${d.month}';
  }

  void _openGroup(Map<String, dynamic> g) {
    final gid = g['id'] as int;
    final name = g['group_name']?.toString() ?? 'Group';
    setState(() => _unreadMap.remove(gid));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailPage(
          conversationId: gid,
          name: name,
          avatar: _groupColor(gid),
          isOnline: true,
          isGroup: true,
        ),
      ),
    ).then((_) => _loadGroups());
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Groups',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () => _showSearchSheet(),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.deepPurple,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
            onPressed: _showCreateGroupSheet,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: [
            Tab(icon: const Icon(Icons.group, size: 18), text: 'My Groups'),
            Tab(
              icon: Badge(
                label: Text('${_unreadMap.values.fold(0, (a, b) => a + b)}'),
                isLabelVisible: _unreadMap.values.any((v) => v > 0),
                child: const Icon(Icons.explore, size: 18),
              ),
              text: 'Discover',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_myGroupsTab(), _discoverTab()],
      ),
    );
  }

  // ── My Groups Tab ──────────────────────────────────────────────────────────

  Widget _myGroupsTab() {
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: Colors.deepPurple),
      );
    if (_myGroups.isEmpty) return _emptyGroups();

    return RefreshIndicator(
      onRefresh: _loadGroups,
      color: Colors.deepPurple,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _myGroups.length,
        itemBuilder: (_, i) => _groupTile(_myGroups[i]),
      ),
    );
  }

  Widget _groupTile(Map<String, dynamic> g) {
    final gid = g['id'] as int;
    final name = g['group_name']?.toString() ?? 'Group';
    final count = (g['member_count'] as num?)?.toInt() ?? 0;
    final last = g['last_message']?.toString() ?? '';
    final ts = g['last_message_at']?.toString();
    final role = g['my_role']?.toString() ?? 'member';
    final unread = _unreadMap[gid] ?? 0;
    final color = _groupColor(gid);

    return InkWell(
      onTap: () => _openGroup(g),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: unread > 0
              ? Colors.deepPurple.withValues(alpha: 0.04)
              : Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
        ),
        child: Row(
          children: [
            // Group avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: unread > 0
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ts != null)
                        Text(
                          _fmt(ts),
                          style: TextStyle(
                            color: unread > 0
                                ? Colors.deepPurple
                                : Colors.grey[500],
                            fontSize: 11,
                            fontWeight: unread > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          last.isNotEmpty ? last : '$count members',
                          style: TextStyle(
                            color: unread > 0
                                ? Colors.black87
                                : Colors.grey[600],
                            fontSize: 13,
                            fontWeight: unread > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.deepPurple,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.people, size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 3),
                      Text(
                        '$count members',
                        style: TextStyle(color: Colors.grey[400], fontSize: 11),
                      ),
                      if (role == 'admin') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.deepPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Long press shows options
            IconButton(
              icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 20),
              onPressed: () => _showGroupOptions(g),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyGroups() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.group, size: 56, color: Colors.deepPurple),
        ),
        const SizedBox(height: 20),
        const Text(
          'No groups yet',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Create a group to chat with multiple people',
          style: TextStyle(color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _showCreateGroupSheet,
          icon: const Icon(Icons.add),
          label: const Text('Create Group'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ],
    ),
  );

  // ── Discover Tab ───────────────────────────────────────────────────────────

  Widget _discoverTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // Invite card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invite Friends',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Start a group chat with people you know',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _showCreateGroupSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      'Create Group',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.group_add, color: Colors.white54, size: 52),
          ],
        ),
      ),
      const SizedBox(height: 20),
      // Tips
      const Text(
        'Group Tips',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      const SizedBox(height: 12),
      ...[
        (Icons.group, 'Add up to 256 members to a group', Colors.blue),
        (Icons.photo, 'Share photos, videos & files', Colors.green),
        (
          Icons.admin_panel_settings,
          'Admins can manage members',
          Colors.purple,
        ),
        (
          Icons.notifications,
          'Get notifications for new messages',
          Colors.orange,
        ),
        (Icons.mic, 'Record and send voice messages', Colors.red),
      ].map(
        (t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.$3.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(t.$1, color: t.$3, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(t.$2, style: const TextStyle(fontSize: 14))),
            ],
          ),
        ),
      ),
    ],
  );

  // ── Create Group Sheet ─────────────────────────────────────────────────────

  void _showCreateGroupSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateGroupSheet(
        onCreated: (g) {
          _loadGroups();
          if (g['id'] != null) _openGroup(g);
        },
      ),
    );
  }

  // ── Group Options ──────────────────────────────────────────────────────────

  void _showGroupOptions(Map<String, dynamic> g) {
    final gid = g['id'] as int;
    final name = g['group_name']?.toString() ?? 'Group';
    final role = g['my_role']?.toString() ?? 'member';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.open_in_new, color: Colors.deepPurple),
              title: const Text('Open Chat'),
              onTap: () {
                Navigator.pop(ctx);
                _openGroup(g);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Colors.blue),
              title: const Text('View Members'),
              onTap: () {
                Navigator.pop(ctx);
                _showMembersSheet(gid, name);
              },
            ),
            if (role == 'admin') ...[
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.amber),
                title: const Text('Edit Group'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditGroupSheet(g);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.green),
                title: const Text('Add Members'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddMembersSheet(gid);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text(
                'Leave Group',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _leaveGroup(gid, name);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Leave Group ────────────────────────────────────────────────────────────

  Future<void> _leaveGroup(int gid, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Leave "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _ms.leaveGroup(gid);
      setState(() => _myGroups.removeWhere((g) => g['id'] == gid));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Left group'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
    }
  }

  // ── Members Sheet ──────────────────────────────────────────────────────────

  void _showMembersSheet(int gid, String groupName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MembersSheet(groupId: gid, groupName: groupName),
    );
  }

  // ── Add Members Sheet ──────────────────────────────────────────────────────

  void _showAddMembersSheet(int gid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMembersSheet(groupId: gid, onAdded: _loadGroups),
    );
  }

  // ── Edit Group Sheet ───────────────────────────────────────────────────────

  void _showEditGroupSheet(Map<String, dynamic> g) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditGroupSheet(group: g, onUpdated: _loadGroups),
    );
  }

  // ── Search Sheet ───────────────────────────────────────────────────────────

  void _showSearchSheet() {
    showSearch(
      context: context,
      delegate: _GroupSearchDelegate(_myGroups, _openGroup),
    );
  }
}

// ─── Create Group Sheet ────────────────────────────────────────────────────

/// Public alias so message_page can use this directly
typedef CreateGroupSheet = _CreateGroupSheet;

class _CreateGroupSheet extends StatefulWidget {
  final void Function(Map<String, dynamic>) onCreated;
  const _CreateGroupSheet({required this.onCreated});
  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final UserService _us = UserService();
  final MessageService _ms = MessageService();

  List<Map<String, dynamic>> _allUsers = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  Future<void> _loadAllUsers() async {
    try {
      // Search with common letters to get all users (getSuggestions excludes followed users)
      final results = <Map<String, dynamic>>[];
      final seen = <int>{};
      for (final q in ['a', 'e', 'i', 'o', 'u', 'h', 'y', 'm', 'b']) {
        try {
          final found = await _us.searchUsers(q);
          for (final u in found) {
            final id = (u['id'] as num?)?.toInt() ?? 0;
            if (id > 0 && seen.add(id))
              results.add(Map<String, dynamic>.from(u));
          }
        } catch (_) {}
      }
      // Also try suggestions as fallback
      if (results.isEmpty) {
        final sugg = await _us.getSuggestions(limit: 50);
        for (final u in sugg) {
          final id = (u['id'] as num?)?.toInt() ?? 0;
          if (id > 0 && seen.add(id)) results.add(Map<String, dynamic>.from(u));
        }
      }
      if (mounted) {
        setState(() {
          _allUsers = results;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a group name')));
      return;
    }
    if (_selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least 2 members')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final result = await _ms.createGroup(
        groupName: _nameCtrl.text.trim(),
        members: _selected.toList(),
        groupDesc: _descCtrl.text.trim().isNotEmpty
            ? _descCtrl.text.trim()
            : null,
      );
      if (mounted) {
        Navigator.pop(context);
        final conv = result['conversation'] as Map<String, dynamic>? ?? result;
        widget.onCreated(conv);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Group "${_nameCtrl.text.trim()}" created!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'New Group',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  _creating
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed:
                              _selected.length >= 2 && _nameCtrl.text.isNotEmpty
                              ? _create
                              : null,
                          child: const Text(
                            'Create',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Group name *',
                      prefixIcon: const Icon(
                        Icons.group,
                        color: Colors.deepPurple,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.deepPurple,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    decoration: InputDecoration(
                      hintText: 'Group description (optional)',
                      prefixIcon: const Icon(Icons.info_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Add Members (${_selected.length} selected)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'min 2',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: sc,
                      itemCount: _allUsers.length,
                      itemBuilder: (_, i) {
                        final u = _allUsers[i];
                        final uid = (u['id'] as num?)?.toInt() ?? 0;
                        final name =
                            u['full_name']?.toString() ??
                            u['username']?.toString() ??
                            'User';
                        final pic = u['profile_image']?.toString() ?? '';
                        final sel = _selected.contains(uid);
                        return CheckboxListTile(
                          value: sel,
                          activeColor: Colors.deepPurple,
                          onChanged: (v) => setState(
                            () =>
                                v! ? _selected.add(uid) : _selected.remove(uid),
                          ),
                          secondary: CircleAvatar(
                            backgroundImage: pic.isNotEmpty
                                ? NetworkImage(pic)
                                : null,
                            backgroundColor: Colors.deepPurple,
                            child: pic.isEmpty
                                ? Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            '@${u['username'] ?? ''}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Members Sheet ─────────────────────────────────────────────────────────

class _MembersSheet extends StatefulWidget {
  final int groupId;
  final String groupName;
  const _MembersSheet({required this.groupId, required this.groupName});
  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  final MessageService _ms = MessageService();
  List<dynamic> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ms
        .getGroupMembers(widget.groupId)
        .then((m) {
          if (mounted)
            setState(() {
              _members = m;
              _loading = false;
            });
        })
        .catchError((_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '${widget.groupName} · ${_members.length} members',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: sc,
                      itemCount: _members.length,
                      itemBuilder: (_, i) {
                        final m = _members[i];
                        final u = m['user'] ?? m;
                        final name =
                            u['full_name']?.toString() ??
                            u['username']?.toString() ??
                            'User';
                        final pic = u['profile_image']?.toString() ?? '';
                        final role = m['role']?.toString() ?? 'member';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: (pic.isNotEmpty)
                                ? NetworkImage(pic)
                                : null,
                            backgroundColor: Colors.deepPurple,
                            child: pic.isEmpty
                                ? Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '@${u['username'] ?? ''}',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                          trailing: role == 'admin'
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Admin',
                                    style: TextStyle(
                                      color: Colors.deepPurple,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Members Sheet ─────────────────────────────────────────────────────

class _AddMembersSheet extends StatefulWidget {
  final int groupId;
  final VoidCallback onAdded;
  const _AddMembersSheet({required this.groupId, required this.onAdded});
  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final UserService _us = UserService();
  final MessageService _ms = MessageService();
  List<Map<String, dynamic>> _users = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  Future<void> _loadAllUsers() async {
    try {
      final results = <Map<String, dynamic>>[];
      final seen = <int>{};
      for (final q in ['a', 'e', 'i', 'o', 'h', 'y', 'm', 'b']) {
        try {
          final found = await _us.searchUsers(q);
          for (final u in found) {
            final id = (u['id'] as num?)?.toInt() ?? 0;
            if (id > 0 && seen.add(id))
              results.add(Map<String, dynamic>.from(u));
          }
        } catch (_) {}
      }
      if (results.isEmpty) {
        final sugg = await _us.getSuggestions(limit: 50);
        for (final u in sugg) {
          final id = (u['id'] as num?)?.toInt() ?? 0;
          if (id > 0 && seen.add(id)) results.add(Map<String, dynamic>.from(u));
        }
      }
      if (mounted)
        setState(() {
          _users = results;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (_selected.isEmpty) return;
    setState(() => _adding = true);
    try {
      await _ms.addGroupMembers(widget.groupId, _selected.toList());
      widget.onAdded();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${_selected.length} member(s)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.97,
      minChildSize: 0.4,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Add Members (${_selected.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const Spacer(),
                  _adding
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ElevatedButton(
                          onPressed: _selected.isNotEmpty ? _add : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Add'),
                        ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: sc,
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        final uid = (u['id'] as num?)?.toInt() ?? 0;
                        final name =
                            u['full_name']?.toString() ??
                            u['username']?.toString() ??
                            '';
                        final pic = u['profile_image']?.toString() ?? '';
                        return CheckboxListTile(
                          value: _selected.contains(uid),
                          activeColor: Colors.deepPurple,
                          onChanged: (v) => setState(
                            () =>
                                v! ? _selected.add(uid) : _selected.remove(uid),
                          ),
                          secondary: CircleAvatar(
                            backgroundImage: pic.isNotEmpty
                                ? NetworkImage(pic)
                                : null,
                            backgroundColor: Colors.deepPurple,
                            child: pic.isEmpty
                                ? Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            '@${u['username'] ?? ''}',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Edit Group Sheet ──────────────────────────────────────────────────────

class _EditGroupSheet extends StatefulWidget {
  final Map<String, dynamic> group;
  final VoidCallback onUpdated;
  const _EditGroupSheet({required this.group, required this.onUpdated});
  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  late TextEditingController _nameCtrl;
  final MessageService _ms = MessageService();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.group['group_name']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await _ms.updateGroup(
        widget.group['id'] as int,
        groupName: _nameCtrl.text.trim(),
      );
      widget.onUpdated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit Group',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Group Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.group),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Search Delegate ───────────────────────────────────────────────────────

class _GroupSearchDelegate extends SearchDelegate {
  final List<Map<String, dynamic>> _groups;
  final void Function(Map<String, dynamic>) _onTap;

  _GroupSearchDelegate(this._groups, this._onTap);

  @override
  String get searchFieldLabel => 'Search groups...';

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final q = query.toLowerCase();
    final results = q.isEmpty
        ? _groups
        : _groups
              .where(
                (g) => (g['group_name']?.toString() ?? '')
                    .toLowerCase()
                    .contains(q),
              )
              .toList();

    if (results.isEmpty) {
      return const Center(child: Text('No groups found'));
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final g = results[i];
        final name = g['group_name']?.toString() ?? 'Group';
        final count = (g['member_count'] as num?)?.toInt() ?? 0;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.deepPurple,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(name),
          subtitle: Text('$count members'),
          onTap: () {
            close(context, null);
            _onTap(g);
          },
        );
      },
    );
  }
}
