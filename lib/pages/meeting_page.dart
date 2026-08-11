import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import 'group_call_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MeetingPage — Zoom-style video meetings
//
// Features:
//   • New instant meeting → starts a group video call
//   • Join by meeting code
//   • Schedule a meeting (with date/time picker)
//   • Share meeting link / copy code
//   • Upcoming & past meetings list
//   • Real-time: new meeting invites arrive via WS group_call_invite
// ─────────────────────────────────────────────────────────────────────────────

class MeetingPage extends StatefulWidget {
  const MeetingPage({super.key});
  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final UserService _userService = UserService();

  // Scheduled meetings (stored locally for now — no backend endpoint needed)
  final List<_Meeting> _scheduled = [];
  final List<_Meeting> _past = [];
  String _myName = 'Me';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadMyInfo();
  }

  Future<void> _loadMyInfo() async {
    final user = AuthService().currentUser;
    setState(() {
      _myName =
          user?['full_name']?.toString() ??
          user?['username']?.toString() ??
          'Me';
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Generate a 9-digit meeting code ───────────────────────────────────────
  String _generateCode() {
    final r = Random();
    final a = 100 + r.nextInt(900);
    final b = 100 + r.nextInt(900);
    final c = 100 + r.nextInt(900);
    return '$a-$b-$c';
  }

  // ── Start instant meeting ─────────────────────────────────────────────────
  void _startInstantMeeting() async {
    // Pick participants
    final picked = await _showParticipantPicker();
    if (picked == null || picked.isEmpty) return;

    final code = _generateCode();
    final meetingName = '$_myName\'s Meeting';

    // Create a fake group conversation for this meeting
    // For simplicity: use the first participant as group context
    // In a full implementation, create a temporary group
    final groupId = DateTime.now().millisecondsSinceEpoch % 100000;

    // Add to past after navigation returns
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallPage(
            groupId: groupId,
            groupName: meetingName,
            callType: GroupCallType.video,
            isCaller: true,
          ),
        ),
      ).then((_) {
        setState(() {
          _past.insert(
            0,
            _Meeting(
              title: meetingName,
              code: code,
              time: DateTime.now(),
              participants: picked.length + 1,
              isPast: true,
            ),
          );
        });
      });
    }
  }

  // ── Join by code ──────────────────────────────────────────────────────────
  void _showJoinDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Meeting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the meeting code to join',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
              ),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '000-000-000',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.link),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final code = ctrl.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              _joinMeeting(code);
            },
            icon: const Icon(Icons.video_call),
            label: const Text('Join'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _joinMeeting(String code) {
    // Derive a groupId from the code for the call
    final groupId = code.replaceAll('-', '').hashCode.abs() % 100000;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupCallPage(
          groupId: groupId,
          groupName: 'Meeting $code',
          callType: GroupCallType.video,
          isCaller: false,
          callerName: 'Meeting Host',
        ),
      ),
    );
  }

  // ── Schedule meeting ──────────────────────────────────────────────────────
  void _showScheduleDialog() async {
    final titleCtrl = TextEditingController();
    DateTime? pickedDate;
    TimeOfDay? pickedTime;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Schedule Meeting'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Meeting Title',
                    prefixIcon: const Icon(Icons.title),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Date picker
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setS(() => pickedDate = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    pickedDate == null
                        ? 'Pick Date'
                        : '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}',
                  ),
                ),
                const SizedBox(height: 8),
                // Time picker
                OutlinedButton.icon(
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.now(),
                    );
                    if (t != null) setS(() => pickedTime = t);
                  },
                  icon: const Icon(Icons.access_time),
                  label: Text(
                    pickedTime == null ? 'Pick Time' : pickedTime!.format(ctx),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty || pickedDate == null || pickedTime == null) {
                  return;
                }
                Navigator.pop(ctx);
                final dt = DateTime(
                  pickedDate!.year,
                  pickedDate!.month,
                  pickedDate!.day,
                  pickedTime!.hour,
                  pickedTime!.minute,
                );
                setState(() {
                  _scheduled.add(
                    _Meeting(
                      title: title,
                      code: _generateCode(),
                      time: dt,
                      participants: 1,
                      isPast: false,
                    ),
                  );
                  _scheduled.sort((a, b) => a.time.compareTo(b.time));
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Meeting "$title" scheduled for ${_fmt(dt)}'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Schedule'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Participant picker ────────────────────────────────────────────────────
  Future<List<dynamic>?> _showParticipantPicker() async {
    final users = <dynamic>[];
    final selected = <int>{};
    bool loading = true;

    return showModalBottomSheet<List<dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (loading) {
            _userService.getSuggestions(limit: 20).then((list) {
              setS(() {
                users.addAll(list);
                loading = false;
              });
            });
          }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (_, sc) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Add Participants',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          final picked = users
                              .where((u) => selected.contains(u['id']))
                              .toList();
                          Navigator.pop(ctx, picked);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Start (${selected.length})'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: sc,
                          itemCount: users.length,
                          itemBuilder: (_, i) {
                            final u = users[i];
                            final uid = u['id'] as int? ?? 0;
                            final pic = u['profile_image']?.toString() ?? '';
                            final name =
                                u['full_name']?.toString() ??
                                u['username']?.toString() ??
                                'User';
                            final isSel = selected.contains(uid);
                            return CheckboxListTile(
                              value: isSel,
                              onChanged: (_) => setS(() {
                                if (isSel)
                                  selected.remove(uid);
                                else
                                  selected.add(uid);
                              }),
                              title: Text(name),
                              subtitle: Text('@${u['username'] ?? ''}'),
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
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              ),
                              activeColor: Colors.deepPurple,
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fmt(DateTime dt) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${days[dt.weekday - 1]} ${months[dt.month - 1]} ${dt.day}, $h:$m';
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Meeting code $code copied!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Meetings',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Quick action bar ─────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                _quickBtn(
                  icon: Icons.video_call_rounded,
                  label: 'New\nMeeting',
                  color: Colors.deepPurple,
                  onTap: _startInstantMeeting,
                ),
                const SizedBox(width: 12),
                _quickBtn(
                  icon: Icons.link_rounded,
                  label: 'Join\nMeeting',
                  color: Colors.blue,
                  onTap: _showJoinDialog,
                ),
                const SizedBox(width: 12),
                _quickBtn(
                  icon: Icons.calendar_month_rounded,
                  label: 'Schedule',
                  color: Colors.orange,
                  onTap: _showScheduleDialog,
                ),
                const SizedBox(width: 12),
                _quickBtn(
                  icon: Icons.share_rounded,
                  label: 'Share\nInvite',
                  color: Colors.green,
                  onTap: () {
                    final code = _generateCode();
                    _copyCode(code);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Tabs ─────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_upcomingTab(), _pastTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _upcomingTab() {
    if (_scheduled.isEmpty) {
      return _empty(
        icon: Icons.calendar_today_outlined,
        title: 'No upcoming meetings',
        subtitle: 'Schedule a meeting or start an instant one',
        actionLabel: 'Schedule Meeting',
        onAction: _showScheduleDialog,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _scheduled.length,
      itemBuilder: (_, i) => _meetingCard(_scheduled[i], upcoming: true),
    );
  }

  Widget _pastTab() {
    if (_past.isEmpty) {
      return _empty(
        icon: Icons.history,
        title: 'No past meetings',
        subtitle: 'Your meeting history will appear here',
        actionLabel: 'New Meeting',
        onAction: _startInstantMeeting,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _past.length,
      itemBuilder: (_, i) => _meetingCard(_past[i], upcoming: false),
    );
  }

  Widget _meetingCard(_Meeting m, {required bool upcoming}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: BoxDecoration(
              color: upcoming
                  ? Colors.deepPurple.withOpacity(0.06)
                  : Colors.grey.withOpacity(0.04),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: upcoming ? Colors.deepPurple : Colors.grey[400],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.video_call_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 13,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _fmt(m.time),
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (upcoming)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Upcoming',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                // Meeting code
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meeting Code',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            m.code,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _copyCode(m.code),
                            child: Icon(
                              Icons.copy,
                              size: 16,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Participants
                Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 16,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${m.participants}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                if (upcoming) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _joinMeeting(m.code),
                      icon: const Icon(Icons.video_call, size: 18),
                      label: const Text('Start / Join'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _copyCode(m.code),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side: const BorderSide(color: Colors.deepPurple),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => setState(() => _scheduled.remove(m)),
                  ),
                ] else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _joinMeeting(m.code),
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: const Text('Start Again'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        side: const BorderSide(color: Colors.deepPurple),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => setState(() => _past.remove(m)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: Colors.deepPurple),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add),
            label: Text(actionLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Data model ────────────────────────────────────────────────────────────────
class _Meeting {
  final String title;
  final String code;
  final DateTime time;
  final int participants;
  final bool isPast;

  const _Meeting({
    required this.title,
    required this.code,
    required this.time,
    required this.participants,
    required this.isPast,
  });
}
