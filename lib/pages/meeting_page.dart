import 'package:flutter/material.dart';

class MeetingPage extends StatefulWidget {
  const MeetingPage({super.key});

  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage> {
  final List<Map<String, dynamic>> _upcomingMeetings = [
    {'title': 'Team Standup', 'time': 'Today, 10:00 AM', 'participants': 5, 'avatar': Colors.blue},
    {'title': 'Project Review', 'time': 'Today, 2:00 PM', 'participants': 8, 'avatar': Colors.green},
    {'title': 'Client Call', 'time': 'Tomorrow, 11:00 AM', 'participants': 3, 'avatar': Colors.orange},
    {'title': 'Design Sync', 'time': 'Tomorrow, 3:00 PM', 'participants': 4, 'avatar': Colors.purple},
  ];

  final List<Map<String, dynamic>> _pastMeetings = [
    {'title': 'Sprint Planning', 'time': 'Yesterday, 10:00 AM', 'participants': 6},
    {'title': 'Marketing Review', 'time': 'Feb 20, 2:00 PM', 'participants': 5},
    {'title': 'Tech Discussion', 'time': 'Feb 19, 4:00 PM', 'participants': 3},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Meetings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Colors.black), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.black), onPressed: () {}),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick actions
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.video_call,
                  label: 'New Meeting',
                  color: Colors.green,
                  onTap: () => _showNewMeetingDialog(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.link,
                  label: 'Join Meeting',
                  color: Colors.blue,
                  onTap: () => _showJoinDialog(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Upcoming meetings
          const Text(
            'Upcoming Meetings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._upcomingMeetings.map((meeting) => _buildMeetingCard(meeting, isUpcoming: true)),
          
          const SizedBox(height: 24),
          
          // Past meetings
          const Text(
            'Past Meetings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._pastMeetings.map((meeting) => _buildMeetingCard(meeting, isUpcoming: false)),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingCard(Map<String, dynamic> meeting, {required bool isUpcoming}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: meeting['avatar'] ?? Colors.grey,
            child: const Icon(Icons.groups, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meeting['title'],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  meeting['time'],
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.people, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${meeting['participants']} participants',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isUpcoming)
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Join'),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              color: Colors.grey,
              onPressed: () {},
            ),
        ],
      ),
    );
  }

  void _showNewMeetingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Meeting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_call, color: Colors.green),
              title: const Text('Instant Meeting'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Starting instant meeting...')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.blue),
              title: const Text('Schedule Meeting'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Schedule meeting dialog coming soon')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog() {
    final TextEditingController _codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Meeting'),
        content: TextField(
          controller: _codeController,
          decoration: const InputDecoration(
            hintText: 'Enter meeting code',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Joining meeting...')),
              );
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}
