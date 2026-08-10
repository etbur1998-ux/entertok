import 'package:flutter/material.dart';

class LoginSecurityPage extends StatefulWidget {
  const LoginSecurityPage({super.key});

  @override
  State<LoginSecurityPage> createState() => _LoginSecurityPageState();
}

class _LoginSecurityPageState extends State<LoginSecurityPage> {
  final List<Map<String, dynamic>> _loginHistory = [
    {'device': 'iPhone 14 Pro', 'location': 'New York, USA', 'time': '2 minutes ago', 'current': true},
    {'device': 'MacBook Pro', 'location': 'New York, USA', 'time': '1 hour ago', 'current': false},
    {'device': 'iPad Air', 'location': 'Los Angeles, USA', 'time': 'Yesterday', 'current': false},
    {'device': 'Samsung Galaxy S23', 'location': 'Chicago, USA', 'time': '3 days ago', 'current': false},
  ];

  final List<Map<String, dynamic>> _activeSessions = [
    {'device': 'iPhone 14 Pro', 'location': 'New York, USA', 'active': true, 'time': 'Current session'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Login & Security', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        children: [
          // Your account info
          _buildSection(
            'Your Account',
            [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.deepPurple,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: const Text('john_doe'),
                subtitle: const Text('john.doe@email.com'),
                trailing: const Icon(Icons.check_circle, color: Colors.green),
              ),
            ],
          ),
          
          // Active session
          _buildSection(
            'Active Sessions',
            [
              ..._activeSessions.map((session) => ListTile(
                leading: const Icon(Icons.phone_android, color: Colors.green),
                title: Text(session['device']),
                subtitle: Text('${session['location']} • ${session['time']}'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
              )),
            ],
          ),
          
          // Login history
          _buildSection(
            'Login History',
            [
              ..._loginHistory.map((login) => ListTile(
                leading: Icon(
                  login['current'] ? Icons.phone_android : Icons.devices,
                  color: login['current'] ? Colors.green : Colors.grey,
                ),
                title: Text(login['device']),
                subtitle: Text('${login['location']} • ${login['time']}'),
                trailing: login['current']
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Current',
                          style: TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      )
                    : TextButton(
                        onPressed: () {},
                        child: const Text('Remove'),
                      ),
              )),
            ],
          ),
          
          // Two-factor authentication
          _buildSection(
            'Two-Factor Authentication',
            [
              ListTile(
                leading: const Icon(Icons.security, color: Colors.orange),
                title: const Text('Two-Factor Authentication'),
                subtitle: const Text('Not enabled'),
                trailing: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Enable'),
                ),
              ),
            ],
          ),
          
          // Password & Security
          _buildSection(
            'Password & Security',
            [
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Password'),
                subtitle: const Text('Last changed 30 days ago'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showChangePasswordDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.email),
                title: const Text('Email'),
                subtitle: const Text('john.doe@email.com'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Phone Number'),
                subtitle: const Text('+1 (555) 123-4567'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
            ],
          ),
          
          // Connected Apps
          _buildSection(
            'Connected Apps',
            [
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Apps and Websites'),
                subtitle: const Text('3 connected'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Shared Logins'),
                subtitle: const Text('No shared logins'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
            ],
          ),
          
          // Data & Privacy
          _buildSection(
            'Data & Privacy',
            [
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download Your Data'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete Your Account', style: TextStyle(color: Colors.red)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
                const SnackBar(content: Text('Password changed successfully!')),
              );
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone. All your data, posts, and followers will be permanently deleted.',
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
                const SnackBar(content: Text('Account deletion initiated')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
