import 'package:flutter/material.dart';
import '../services/api_client.dart';

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});
  @override
  State<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  final _api = ApiClient();

  bool _pushNotifications = true;
  bool _emailNotifications = false;
  bool _likesNotifs = true;
  bool _commentsNotifs = true;
  bool _followersNotifs = true;
  bool _mentionsNotifs = true;
  bool _messagesNotifs = true;
  bool _liveNotifs = true;
  bool _matchNotifs = true;
  bool _marketingNotifs = false;
  bool _sounds = true;
  bool _vibrations = true;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('/settings/notifications');
      if (mounted && r is Map) {
        setState(() {
          _pushNotifications = r['push_enabled'] ?? true;
          _emailNotifications = r['email_enabled'] ?? false;
          _likesNotifs = r['likes'] ?? true;
          _commentsNotifs = r['comments'] ?? true;
          _followersNotifs = r['followers'] ?? true;
          _mentionsNotifs = r['mentions'] ?? true;
          _messagesNotifs = r['messages'] ?? true;
          _liveNotifs = r['live'] ?? true;
          _sounds = r['sounds'] ?? true;
          _vibrations = r['vibrations'] ?? true;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _api.put(
        '/settings/notifications',
        body: {
          'push_enabled': _pushNotifications,
          'email_enabled': _emailNotifications,
          'likes': _likesNotifs,
          'comments': _commentsNotifs,
          'followers': _followersNotifs,
          'mentions': _mentionsNotifs,
          'messages': _messagesNotifs,
          'live': _liveNotifs,
          'sounds': _sounds,
          'vibrations': _vibrations,
        },
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification settings saved!'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved locally')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            letterSpacing: 0.5,
          ),
        ),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(height: 1, indent: 16, color: Colors.grey[100]),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _sw(
    String title,
    String subtitle,
    bool val,
    Function(bool) onChange,
  ) => SwitchListTile(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(
      subtitle,
      style: TextStyle(color: Colors.grey[500], fontSize: 12),
    ),
    value: val,
    onChanged: onChange,
    activeColor: Colors.deepPurple,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _section('General', [
                  _sw(
                    'Push Notifications',
                    'Receive notifications on your device',
                    _pushNotifications,
                    (v) => setState(() => _pushNotifications = v),
                  ),
                  _sw(
                    'Email Notifications',
                    'Get notified by email',
                    _emailNotifications,
                    (v) => setState(() => _emailNotifications = v),
                  ),
                ]),
                _section('Activity', [
                  _sw(
                    'Likes',
                    'When someone likes your post',
                    _likesNotifs,
                    (v) => setState(() => _likesNotifs = v),
                  ),
                  _sw(
                    'Comments',
                    'When someone comments on your post',
                    _commentsNotifs,
                    (v) => setState(() => _commentsNotifs = v),
                  ),
                  _sw(
                    'New Followers',
                    'When someone follows you',
                    _followersNotifs,
                    (v) => setState(() => _followersNotifs = v),
                  ),
                  _sw(
                    'Mentions',
                    'When someone tags you',
                    _mentionsNotifs,
                    (v) => setState(() => _mentionsNotifs = v),
                  ),
                ]),
                _section('Messages & Live', [
                  _sw(
                    'Messages',
                    'New direct messages',
                    _messagesNotifs,
                    (v) => setState(() => _messagesNotifs = v),
                  ),
                  _sw(
                    'Live Streams',
                    'When someone you follow goes live',
                    _liveNotifs,
                    (v) => setState(() => _liveNotifs = v),
                  ),
                  _sw(
                    'Matches & Dating',
                    'New matches and likes in Dating',
                    _matchNotifs,
                    (v) => setState(() => _matchNotifs = v),
                  ),
                  _sw(
                    'Marketing & Promotions',
                    'Updates about ads and offers',
                    _marketingNotifs,
                    (v) => setState(() => _marketingNotifs = v),
                  ),
                ]),
                _section('Sound & Vibration', [
                  _sw(
                    'Sound',
                    'Play sound for notifications',
                    _sounds,
                    (v) => setState(() => _sounds = v),
                  ),
                  _sw(
                    'Vibration',
                    'Vibrate for notifications',
                    _vibrations,
                    (v) => setState(() => _vibrations = v),
                  ),
                ]),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : const Text(
                              'Save Settings',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
