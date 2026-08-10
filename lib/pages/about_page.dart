import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('About', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App logo and name
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.deepPurple,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.play_circle_filled,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'EnterTok',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // App description
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  'EnterTok is a social media platform where you can create and share short videos, connect with friends, discover content, and more!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat('125K', 'Downloads'),
                    _buildStat('4.5★', 'Rating'),
                    _buildStat('10M+', 'Users'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Features
          const Text(
            'Features',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(Icons.videocam, 'Live Streaming', 'Go live and connect with your audience'),
          _buildFeatureItem(Icons.movie, 'Short Videos', 'Create and share short-form videos'),
          _buildFeatureItem(Icons.message, 'Messaging', 'Chat with friends and followers'),
          _buildFeatureItem(Icons.explore, 'Discover', 'Explore trending content'),
          _buildFeatureItem(Icons.shopping_bag, 'Marketplace', 'Buy and sell products'),
          _buildFeatureItem(Icons.people, 'Connect', 'Network with professionals'),
          const SizedBox(height: 24),
          
          // Contact
          const Text(
            'Contact Us',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.email, color: Colors.deepPurple),
            title: const Text('Email'),
            subtitle: const Text('support@entertok.com'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.language, color: Colors.deepPurple),
            title: const Text('Website'),
            subtitle: const Text('www.entertok.com'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.help, color: Colors.deepPurple),
            title: const Text('Help Center'),
            subtitle: const Text('Get help and support'),
            onTap: () {},
          ),
          const SizedBox(height: 24),
          
          // Social media
          const Text(
            'Follow Us',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSocialIcon(Icons.facebook, Colors.blue),
              _buildSocialIcon(Icons.alternate_email, Colors.lightBlue),
              _buildSocialIcon(Icons.camera_alt, Colors.pink),
              _buildSocialIcon(Icons.play_circle, Colors.red),
            ],
          ),
          const SizedBox(height: 32),
          
          // Copyright
          Center(
            child: Text(
              '© 2024 EnterTok. All rights reserved.',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.deepPurple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon, Color color) {
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color),
    );
  }
}
