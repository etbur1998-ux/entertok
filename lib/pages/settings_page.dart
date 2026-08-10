import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/api_client.dart';
import 'edit_profile_page.dart';
import 'privacy_security_page.dart';
import 'notifications_settings_page.dart';
import 'login_security_page.dart';
import 'help_page.dart';
import 'wallet_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = false;
  bool _dataSaver = false;
  String _language = 'English';
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _user = AuthService().currentUser;
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final pic = _user?['profile_image']?.toString() ?? '';
    final name =
        _user?['full_name']?.toString() ??
        _user?['username']?.toString() ??
        'User';
    final username = _user?['username']?.toString() ?? '';
    final email = _user?['email']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        children: [
          // ── Profile Card ────────────────────────────────────────────────────
          GestureDetector(
            onTap: () => _push(const EditProfilePage()),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.deepPurple,
                    backgroundImage: pic.isNotEmpty
                        ? NetworkImage(ApiClient.resolveUrl(pic))
                        : null,
                    child: pic.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          '@$username',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Edit',
                      style: TextStyle(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Account ─────────────────────────────────────────────────────────
          _section('Account', [
            _item(
              Icons.person_outline,
              'Edit Profile',
              'Update your info and photo',
              Colors.deepPurple,
              () => _push(const EditProfilePage()),
            ),
            _item(
              Icons.account_balance_wallet_outlined,
              'Wallet',
              'Manage your ETBurPay wallet',
              Colors.green,
              () => _push(const WalletPage()),
            ),
            _item(
              Icons.lock_outline,
              'Login & Security',
              'Password, sessions, 2FA',
              Colors.blue,
              () => _push(const LoginSecurityPage()),
            ),
            _item(
              Icons.shield_outlined,
              'Privacy & Safety',
              'Account visibility and blocked users',
              Colors.indigo,
              () => _push(const PrivacySecurityPage()),
            ),
          ]),

          // ── Preferences ─────────────────────────────────────────────────────
          _section('Preferences', [
            _item(
              Icons.notifications_outlined,
              'Notifications',
              'Likes, comments, messages',
              Colors.orange,
              () => _push(const NotificationsSettingsPage()),
            ),
            _switchItem(
              Icons.dark_mode_outlined,
              'Dark Mode',
              'Switch to dark theme',
              Colors.blueGrey,
              _darkMode,
              (v) => setState(() => _darkMode = v),
            ),
            _switchItem(
              Icons.data_saver_on_outlined,
              'Data Saver',
              'Use less mobile data',
              Colors.teal,
              _dataSaver,
              (v) => setState(() => _dataSaver = v),
            ),
            _item(
              Icons.language_outlined,
              'Language',
              _language,
              Colors.purple,
              _showLanguagePicker,
            ),
            _item(
              Icons.accessibility_outlined,
              'Accessibility',
              'Font size, contrast',
              Colors.brown,
              _showAccessibility,
            ),
          ]),

          // ── Content ─────────────────────────────────────────────────────────
          _section('Content & Activity', [
            _item(
              Icons.video_settings_outlined,
              'Video Quality',
              'Auto, HD, SD',
              Colors.red,
              _showVideoQuality,
            ),
            _item(
              Icons.auto_awesome_outlined,
              'Content Preferences',
              'Customize your feed',
              Colors.amber,
              _showContentPrefs,
            ),
            _item(
              Icons.block_outlined,
              'Blocked Users',
              'Manage blocked accounts',
              Colors.grey,
              _showBlockedUsers,
            ),
            _item(
              Icons.history_outlined,
              'Watch History',
              'Videos you\'ve watched',
              Colors.cyan,
              () {},
            ),
          ]),

          // ── Support ─────────────────────────────────────────────────────────
          _section('Support', [
            _item(
              Icons.help_outline,
              'Help Center',
              'FAQs and guides',
              Colors.deepPurple,
              () => _push(const HelpPage()),
            ),
            _item(
              Icons.feedback_outlined,
              'Send Feedback',
              'Report a bug or suggest a feature',
              Colors.green,
              _showFeedback,
            ),
            _item(
              Icons.report_outlined,
              'Report a Problem',
              'Technical issues',
              Colors.orange,
              _showReport,
            ),
            _item(
              Icons.info_outlined,
              'About EnterTok',
              'Version and credits',
              Colors.blue,
              _showAbout,
            ),
          ]),

          // ── Legal ───────────────────────────────────────────────────────────
          _section('Legal', [
            _item(
              Icons.description_outlined,
              'Terms of Service',
              '',
              Colors.grey,
              _showTerms,
            ),
            _item(
              Icons.privacy_tip_outlined,
              'Privacy Policy',
              '',
              Colors.grey,
              _showPrivacyPolicy,
            ),
            _item(
              Icons.cookie_outlined,
              'Cookie Policy',
              '',
              Colors.grey,
              () {},
            ),
          ]),

          // ── Logout / Delete ─────────────────────────────────────────────────
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'Log Out',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: _confirmDeleteAccount,
              child: const Text(
                'Delete Account',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'EnterTok v1.0.0  •  Build 2026',
              style: TextStyle(color: Colors.grey[400], fontSize: 11),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─── Section helpers ──────────────────────────────────────────────────────

  Widget _section(String title, List<Widget> items) => Column(
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
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              items[i],
              if (i < items.length - 1)
                Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: Colors.grey[100],
                ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _item(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
    ),
    subtitle: subtitle.isNotEmpty
        ? Text(
            subtitle,
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          )
        : null,
    trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
  );

  Widget _switchItem(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    bool val,
    Function(bool) onChanged,
  ) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(color: Colors.grey[500], fontSize: 12),
    ),
    trailing: Switch(
      value: val,
      onChanged: onChanged,
      activeColor: Colors.deepPurple,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
  );

  // ─── Language ─────────────────────────────────────────────────────────────

  void _showLanguagePicker() {
    final langs = [
      'English',
      'Spanish',
      'French',
      'German',
      'Arabic',
      'Chinese',
      'Japanese',
      'Portuguese',
      'Hindi',
      'Swahili',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
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
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Select Language',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: langs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(
                title: Text(langs[i]),
                trailing: _language == langs[i]
                    ? const Icon(Icons.check_circle, color: Colors.deepPurple)
                    : null,
                onTap: () {
                  setState(() => _language = langs[i]);
                  Navigator.pop(context);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── Video Quality ────────────────────────────────────────────────────────

  void _showVideoQuality() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          String selected = 'Auto';
          return Column(
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
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Video Quality',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...[
                'Auto (Recommended)',
                'HD (1080p)',
                'HD (720p)',
                'SD (480p)',
                'Low (360p)',
              ].map((q) {
                final isSelected = selected == q.split(' ')[0];
                return ListTile(
                  title: Text(q),
                  subtitle: q.contains('Auto')
                      ? const Text('Adjusts based on your connection')
                      : null,
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.deepPurple)
                      : null,
                  onTap: () {
                    setLocal(() => selected = q.split(' ')[0]);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // ─── Content Preferences ──────────────────────────────────────────────────

  void _showContentPrefs() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final prefs = {
            'Dance & Music': true,
            'Comedy': true,
            'Education': false,
            'Gaming': false,
            'Food': true,
            'Travel': true,
            'Fitness': false,
            'Technology': true,
            'Art': false,
            'News': false,
          };
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, sc) => Column(
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Content Preferences',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Choose topics you want to see in your feed',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    controller: sc,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: prefs.keys.map((k) {
                          final on = prefs[k] ?? false;
                          return FilterChip(
                            label: Text(k),
                            selected: on,
                            onSelected: (v) => setLocal(() => prefs[k] = v),
                            selectedColor: Colors.deepPurple.withValues(
                              alpha: 0.15,
                            ),
                            checkmarkColor: Colors.deepPurple,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Preferences saved!'),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Save Preferences'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Blocked Users ────────────────────────────────────────────────────────

  void _showBlockedUsers() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Blocked Users',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block, size: 56, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No blocked users',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Users you block won\'t be able to see your profile',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Accessibility ────────────────────────────────────────────────────────

  void _showAccessibility() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          double fontSize = 1.0;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Accessibility',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Text Size',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Slider(
                  value: fontSize,
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  activeColor: Colors.deepPurple,
                  label: fontSize == 1.0
                      ? 'Normal'
                      : fontSize < 1.0
                      ? 'Small'
                      : 'Large',
                  onChanged: (v) => setLocal(() => fontSize = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Aa', style: TextStyle(fontSize: 12 * fontSize)),
                    Text('Aa', style: TextStyle(fontSize: 16 * fontSize)),
                    Text('Aa', style: TextStyle(fontSize: 20 * fontSize)),
                  ],
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text('High Contrast'),
                  subtitle: const Text('Improve text readability'),
                  value: false,
                  onChanged: (_) {},
                ),
                SwitchListTile(
                  title: const Text('Reduce Motion'),
                  subtitle: const Text('Minimize animations'),
                  value: false,
                  onChanged: (_) {},
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Feedback ────────────────────────────────────────────────────────────

  void _showFeedback() {
    final ctrl = TextEditingController();
    String category = 'Bug Report';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send Feedback',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: category,
                items:
                    [
                          'Bug Report',
                          'Feature Request',
                          'Content Issue',
                          'Account Problem',
                          'Other',
                        ]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                onChanged: (v) => setLocal(() => category = v!),
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Describe the issue or suggestion',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Feedback submitted. Thank you!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Submit Feedback',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Report ───────────────────────────────────────────────────────────────

  void _showReport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
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
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Report a Problem',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...[
            'App Crashes',
            'Videos won\'t play',
            'Login Issues',
            'Payment Problems',
            'Content Not Loading',
            'Other Technical Issue',
          ].map(
            (issue) => ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.orange),
              title: Text(issue),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Reported: $issue. Our team will investigate.',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── About ────────────────────────────────────────────────────────────────

  void _showAbout() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'EnterTok',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              'Version 1.0.0 (Build 2026)',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            ...[
              ('📱', 'Platform', 'Flutter / Go'),
              ('🌐', 'Backend', 'Go + SQLite'),
              ('⚡', 'Real-time', 'WebSocket + WebRTC'),
              ('🔒', 'Security', 'JWT + HTTPS'),
            ].map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(r.$1, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 12),
                    Text(
                      '${r.$2}: ',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    Text(
                      r.$3,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '© 2026 EnterTok. All rights reserved.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Legal ────────────────────────────────────────────────────────────────

  void _showTerms() => _showLegalDoc('Terms of Service', '''
Last updated: June 2026

1. Acceptance of Terms
By using EnterTok, you agree to these Terms of Service.

2. User Accounts
You are responsible for maintaining the security of your account.

3. Content Policy
Users may not post illegal, harmful, or offensive content.

4. Intellectual Property
All content remains the property of its original creator.

5. Privacy
We respect your privacy. See our Privacy Policy for details.

6. Termination
We reserve the right to terminate accounts that violate these terms.
  ''');

  void _showPrivacyPolicy() => _showLegalDoc('Privacy Policy', '''
Last updated: June 2026

1. Information We Collect
We collect information you provide when creating an account.

2. How We Use Your Information
- To provide and improve our services
- To send notifications
- To display relevant content

3. Information Sharing
We do not sell your personal information to third parties.

4. Data Security
We use industry-standard encryption to protect your data.

5. Your Rights
You have the right to access, correct, or delete your data.

6. Contact Us
For privacy concerns: privacy@entertok.com
  ''');

  void _showLegalDoc(String title, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: Text(title, style: const TextStyle(color: Colors.black)),
            iconTheme: const IconThemeData(color: Colors.black),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              content,
              style: const TextStyle(fontSize: 14, height: 1.7),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Auth ─────────────────────────────────────────────────────────────────

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text(
          'Are you sure you want to log out of your account?',
        ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.red),
        ),
        content: const Text(
          'This will permanently delete your account, all your posts, messages, and data. This cannot be undone.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Account deletion requested. You will receive an email to confirm.',
                  ),
                  duration: Duration(seconds: 4),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete My Account'),
          ),
        ],
      ),
    );
  }
}
