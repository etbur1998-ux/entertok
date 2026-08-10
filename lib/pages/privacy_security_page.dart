import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';

class PrivacySecurityPage extends StatefulWidget {
  const PrivacySecurityPage({super.key});
  @override
  State<PrivacySecurityPage> createState() => _PrivacySecurityPageState();
}

class _PrivacySecurityPageState extends State<PrivacySecurityPage> {
  final _userService = UserService();

  bool _privateAccount = false;
  bool _allowComments = true;
  bool _allowMessages = true;
  bool _showOnlineStatus = true;
  bool _showReadReceipts = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final u = AuthService().currentUser;
    _privateAccount = u?['is_private'] == true;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _userService.updateProfile(isPrivate: _privateAccount);
      await AuthService().getCurrentUser();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Privacy settings saved!'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Privacy & Safety',
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
      body: ListView(
        children: [
          _section('Account Privacy', [
            SwitchListTile(
              title: const Text(
                'Private Account',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Only approved followers can see your posts',
              ),
              value: _privateAccount,
              onChanged: (v) => setState(() => _privateAccount = v),
              activeColor: Colors.deepPurple,
            ),
          ]),
          _section('Interactions', [
            SwitchListTile(
              title: const Text(
                'Allow Comments',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Let others comment on your posts'),
              value: _allowComments,
              onChanged: (v) => setState(() => _allowComments = v),
              activeColor: Colors.deepPurple,
            ),
            SwitchListTile(
              title: const Text(
                'Allow Messages',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Let others send you direct messages'),
              value: _allowMessages,
              onChanged: (v) => setState(() => _allowMessages = v),
              activeColor: Colors.deepPurple,
            ),
          ]),
          _section('Activity Status', [
            SwitchListTile(
              title: const Text(
                'Show Online Status',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Let others see when you\'re active'),
              value: _showOnlineStatus,
              onChanged: (v) => setState(() => _showOnlineStatus = v),
              activeColor: Colors.deepPurple,
            ),
            SwitchListTile(
              title: const Text(
                'Read Receipts',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Show when you\'ve read messages'),
              value: _showReadReceipts,
              onChanged: (v) => setState(() => _showReadReceipts = v),
              activeColor: Colors.deepPurple,
            ),
          ]),
          _section('Security', [
            ListTile(
              leading: const Icon(Icons.security, color: Colors.green),
              title: const Text(
                'Two-Factor Authentication',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Add an extra layer of security'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Off',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('2FA setup coming soon')),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined, color: Colors.blue),
              title: const Text(
                'Download Your Data',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Get a copy of your data'),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Preparing your data... You\'ll receive an email.',
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.grey),
              title: const Text(
                'Blocked Accounts',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Manage users you\'ve blocked'),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('No blocked users'))),
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
                        'Save Privacy Settings',
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
