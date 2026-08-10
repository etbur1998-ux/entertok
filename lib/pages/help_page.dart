import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Help Center', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.grey[600]),
                const SizedBox(width: 12),
                Text(
                  'Search help...',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Quick help topics
          const Text(
            'Quick Help',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuickHelpCard(
                  icon: Icons.person_add,
                  title: 'Account',
                  color: Colors.blue,
                  onTap: () => _showHelpDetail(context, 'Account Help', 'Get help with your account settings, login issues, and profile management.'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickHelpCard(
                  icon: Icons.videocam,
                  title: 'Live Streaming',
                  color: Colors.red,
                  onTap: () => _showHelpDetail(context, 'Live Streaming Help', 'Learn how to go live, manage viewers, and use live features.'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuickHelpCard(
                  icon: Icons.chat,
                  title: 'Messaging',
                  color: Colors.green,
                  onTap: () => _showHelpDetail(context, 'Messaging Help', 'Get help with sending messages, creating groups, and chat features.'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickHelpCard(
                  icon: Icons.shopping_bag,
                  title: 'Shopping',
                  color: Colors.orange,
                  onTap: () => _showHelpDetail(context, 'Shopping Help', 'Learn about buying, selling, and managing orders.'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // FAQ section
          const Text(
            'Frequently Asked Questions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildFAQItem(
            context,
            'How do I reset my password?',
            'Go to Settings > Login & Security > Reset Password and follow the instructions.',
          ),
          _buildFAQItem(
            context,
            'How do I delete my account?',
            'Go to Settings > Account > Delete Account. Note that this action is irreversible.',
          ),
          _buildFAQItem(
            context,
            'How do I report inappropriate content?',
            'Tap the three dots on any post and select "Report" to report inappropriate content.',
          ),
          _buildFAQItem(
            context,
            'How do I become a verified creator?',
            'Currently, verification is by invitation only. Stay tuned for updates!',
          ),
          _buildFAQItem(
            context,
            'How do I monetize my content?',
            'Creators can monetize through brand deals, live gifts, and the Creator Fund program.',
          ),
          const SizedBox(height: 24),
          
          // Contact support
          const Text(
            'Contact Support',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.support_agent, size: 48, color: Colors.deepPurple),
                const SizedBox(height: 12),
                const Text(
                  'Need more help?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Contact our support team for personalized assistance.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Contact Support'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickHelpCard({
    required IconData icon,
    required String title,
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
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem(BuildContext context, String question, String answer) {
    return ExpansionTile(
      title: Text(question, style: const TextStyle(fontWeight: FontWeight.w500)),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(answer, style: TextStyle(color: Colors.grey[700])),
        ),
      ],
    );
  }

  void _showHelpDetail(BuildContext context, String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                content,
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('Got It'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
