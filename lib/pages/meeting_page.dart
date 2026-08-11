import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import 'meeting_call_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MeetingPage — Zoom-style meetings
// ─────────────────────────────────────────────────────────────────────────────

class MeetingPage extends StatefulWidget {
  const MeetingPage({super.key});
  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final MessageService _msgSvc = MessageService();

  final List<_Meeting> _upcoming = [];
  final List<_Meeting> _past = [];
  String _myName = 'Me';
  bool _creatingMeeting = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    final user = AuthService().currentUser;
    _myName =
        user?['full_name']?.toString() ?? user?['username']?.toString() ?? 'Me';
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String _genCode() {
    final r = Random();
    return '${100 + r.nextInt(900)}-${100 + r.nextInt(900)}-${100 + r.nextInt(900)}';
  }

  // ── NEW MEETING — show options sheet, then start ──────────────────────────
  void _newMeeting() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New Meeting',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              // Option 1: Start now solo (share code for others to join)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.video_call_rounded,
                    color: Colors.deepPurple,
                    size: 26,
                  ),
                ),
                title: const Text(
                  'Start an Instant Meeting',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Start now — share the code to invite others',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _startInstant();
                },
              ),
              const Divider(),
              // Option 2: Pick participants first
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.group_add_rounded,
                    color: Colors.blue,
                    size: 26,
                  ),
                ),
                title: const Text(
                  'Invite People to Meet',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Pick contacts and start immediately'),
                onTap: () {
                  Navigator.pop(ctx);
                  _startWithPeople();
                },
              ),
              const Divider(),
              // Option 3: Schedule for later
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.orange,
                    size: 26,
                  ),
                ),
                title: const Text(
                  'Schedule for Later',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Pick a date and time'),
                onTap: () {
                  Navigator.pop(ctx);
                  _scheduleMeeting();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Start alone — show the code, let others join
  void _startInstant() async {
    final code = _genCode();
    final name = '$_myName\'s Meeting';
    setState(() => _creatingMeeting = true);

    try {
      // Create a real group in the DB — even solo, so others can join by code
      // Use current user's ID + a dummy extra member list (just self)
      final result = await _msgSvc.createGroup(
        groupName: name,
        members: [], // creator is added automatically by backend
      );
      final groupId =
          (result['conversation']?['id'] as num?)?.toInt() ??
          (result['id'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch % 99999 + 1;

      setState(() => _creatingMeeting = false);
      _launchCall(code: code, name: name, groupId: groupId);
    } catch (e) {
      setState(() => _creatingMeeting = false);
      // Fallback: use a hash-based ID if group creation fails
      final groupId = code.replaceAll('-', '').hashCode.abs() % 99999 + 1;
      _launchCall(code: code, name: name, groupId: groupId);
    }
  }

  // Pick participants first
  void _startWithPeople() async {
    final groups = await _msgSvc.getUserGroups();
    if (!mounted) return;

    // Show existing groups to pick from
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Start Group Call',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startInstant(); // fallback: start solo
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New Group'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (groups.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No groups yet.\nCreate a group in Messages first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: sc,
                  itemCount: groups.length,
                  itemBuilder: (_, i) {
                    final g = groups[i];
                    final gid = (g['id'] as num).toInt();
                    final gname = g['group_name']?.toString() ?? 'Group';
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.deepPurple,
                        child: Icon(Icons.group, color: Colors.white, size: 20),
                      ),
                      title: Text(gname),
                      subtitle: Text('${g['member_count'] ?? 0} members'),
                      trailing: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          final code = _genCode();
                          _launchCall(code: code, name: gname, groupId: gid);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Call'),
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

  void _launchCall({
    required String code,
    required String name,
    required int groupId,
  }) async {
    setState(() => _creatingMeeting = true);

    // Show code before starting
    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Meeting Ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Share this code so others can join:'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied!')),
                        );
                      },
                      icon: const Icon(Icons.copy, color: Colors.deepPurple),
                    ),
                  ],
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
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.video_call),
              label: const Text('Start Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ).then((start) {
        setState(() => _creatingMeeting = false);
        if (start == true && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MeetingCallPage(
                roomId: groupId,
                meetingName: name,
                meetingCode: code,
                isHost: true,
              ),
            ),
          ).then((_) {
            setState(() {
              _past.insert(
                0,
                _Meeting(
                  title: name,
                  code: code,
                  time: DateTime.now(),
                  participants: 1,
                ),
              );
            });
          });
        }
      });
    }
  }

  // ── JOIN by code ──────────────────────────────────────────────────────────
  void _joinMeeting([String? preCode]) {
    final ctrl = TextEditingController(text: preCode ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Meeting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the 9-digit meeting code',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
              decoration: InputDecoration(
                hintText: '000-000-000',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 18),
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
              final roomId =
                  code.replaceAll('-', '').hashCode.abs() % 99999 + 1;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MeetingCallPage(
                    roomId: roomId,
                    meetingName: 'Meeting $code',
                    meetingCode: code,
                    isHost: false, // joiner — waits for host offer
                  ),
                ),
              );
            },
            icon: const Icon(Icons.videocam),
            label: const Text('Join'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── SCHEDULE ─────────────────────────────────────────────────────────────
  void _scheduleMeeting() async {
    final titleCtrl = TextEditingController(text: '$_myName\'s Meeting');
    DateTime? date;
    TimeOfDay? time;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Schedule Meeting'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    prefixIcon: const Icon(Icons.title),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (d != null) setS(() => date = d);
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          date == null
                              ? 'Date'
                              : '${date!.day}/${date!.month}/${date!.year}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.now(),
                          );
                          if (t != null) setS(() => time = t);
                        },
                        icon: const Icon(Icons.access_time, size: 16),
                        label: Text(time == null ? 'Time' : time!.format(ctx)),
                      ),
                    ),
                  ],
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
                final t = titleCtrl.text.trim();
                if (t.isEmpty || date == null || time == null) return;
                Navigator.pop(ctx);
                final dt = DateTime(
                  date!.year,
                  date!.month,
                  date!.day,
                  time!.hour,
                  time!.minute,
                );
                setState(() {
                  _upcoming.add(
                    _Meeting(
                      title: t,
                      code: _genCode(),
                      time: dt,
                      participants: 1,
                    ),
                  );
                  _upcoming.sort((a, b) => a.time.compareTo(b.time));
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Scheduled "$t"'),
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

  String _fmtDate(DateTime dt) {
    final ms = [
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
    return '${ms[dt.month - 1]} ${dt.day}  $h:$m';
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Code $code copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
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
            Tab(text: 'History'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Quick buttons ───────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Row(
              children: [
                _qbtn(
                  Icons.video_call_rounded,
                  'New\nMeeting',
                  Colors.deepPurple,
                  _newMeeting,
                ),
                const SizedBox(width: 10),
                _qbtn(
                  Icons.link_rounded,
                  'Join\nMeeting',
                  Colors.blue,
                  () => _joinMeeting(),
                ),
                const SizedBox(width: 10),
                _qbtn(
                  Icons.calendar_month_rounded,
                  'Schedule',
                  Colors.orange,
                  _scheduleMeeting,
                ),
                const SizedBox(width: 10),
                _qbtn(
                  Icons.content_copy_rounded,
                  'Copy\nInvite',
                  Colors.green,
                  () => _copy(_genCode()),
                ),
              ],
            ),
          ),
          if (_creatingMeeting)
            const LinearProgressIndicator(color: Colors.deepPurple),
          const Divider(height: 1),
          // ── Tabs ────────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [_upcomingTab(), _historyTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qbtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
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
    if (_upcoming.isEmpty) {
      return _empty(
        icon: Icons.calendar_today_outlined,
        title: 'No upcoming meetings',
        subtitle: 'Schedule a meeting or start an instant one',
        btnLabel: 'New Meeting',
        onBtn: _newMeeting,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _upcoming.length,
      itemBuilder: (_, i) => _card(
        _upcoming[i],
        onDelete: () => setState(() => _upcoming.removeAt(i)),
      ),
    );
  }

  Widget _historyTab() {
    if (_past.isEmpty) {
      return _empty(
        icon: Icons.history_rounded,
        title: 'No meeting history',
        subtitle: 'Your past meetings will appear here',
        btnLabel: 'Start a Meeting',
        onBtn: _newMeeting,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _past.length,
      itemBuilder: (_, i) => _card(
        _past[i],
        isPast: true,
        onDelete: () => setState(() => _past.removeAt(i)),
      ),
    );
  }

  Widget _card(
    _Meeting m, {
    bool isPast = false,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isPast
                        ? Colors.grey.withOpacity(0.15)
                        : Colors.deepPurple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.video_call_rounded,
                    color: isPast ? Colors.grey : Colors.deepPurple,
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
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 13,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _fmtDate(m.time),
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
                if (!isPast)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Scheduled',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Code row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    m.code,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _copy(m.code),
                    child: const Icon(
                      Icons.copy,
                      size: 16,
                      color: Colors.deepPurple,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _joinMeeting(m.code),
                    icon: const Icon(Icons.videocam, size: 18),
                    label: Text(isPast ? 'Start Again' : 'Start / Join'),
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
                  onPressed: () => _copy(m.code),
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
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String subtitle,
    required String btnLabel,
    required VoidCallback onBtn,
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
            child: Icon(icon, size: 38, color: Colors.deepPurple),
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
            onPressed: onBtn,
            icon: const Icon(Icons.add),
            label: Text(btnLabel),
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

  const _Meeting({
    required this.title,
    required this.code,
    required this.time,
    this.participants = 1,
  });
}
