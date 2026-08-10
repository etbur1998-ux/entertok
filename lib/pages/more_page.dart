 import 'package:flutter/material.dart';

import 'upload_page.dart';
import 'profile_page.dart';
import 'meeting_page.dart';
import 'saved_page.dart';
import 'settings_page.dart';
import 'help_page.dart';
import 'auth_page.dart';
import 'wallet_page.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> menuItems = [
      {'icon': Icons.account_balance_wallet, 'label': 'Wallet', 'color': Colors.green},
      {'icon': Icons.person, 'label': 'My Profile', 'color': Colors.deepPurple},
      {'icon': Icons.videocam, 'label': 'Meet', 'color': Colors.purple},
      {'icon': Icons.bookmark_outline, 'label': 'Saved', 'color': Colors.blue},
      {'icon': Icons.settings_outlined, 'label': 'Settings', 'color': Colors.grey},
      {'icon': Icons.help_outline, 'label': 'Help', 'color': Colors.green},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: ListView.builder(
        itemCount: menuItems.length,
        itemBuilder: (context, index) {
          final item = menuItems[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: item['color'].withValues(alpha: 0.2),
              child: Icon(
                item['icon'],
                color: item['color'],
              ),
            ),
            title: Text(
              item['label'],
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              switch (item['label']) {
                case 'Wallet':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const WalletPage()),
                  );
                  break;
                case 'Login / Sign Up':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AuthPage()),
                  );
                  break;
                case 'My Profile':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfilePage()),
                  );
                  break;
                case 'Meet':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MeetingPage()),
                  );
                  break;
                case 'Create Post':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UploadPage()),
                  );
                  break;
                case 'Notifications':
                  _showComingSoon(context, 'Notifications');
                  break;
                case 'Saved':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SavedPage()),
                  );
                  break;
                case 'Settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsPage()),
                  );
                  break;
                case 'Help':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HelpPage()),
                  );
                  break;
                case 'Logout':
                  _showLogoutDialog(context);
                  break;
              }
            },
          );
        },
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon!')),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).pushReplacementNamed('/auth');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
