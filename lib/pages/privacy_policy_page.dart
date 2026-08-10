import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Privacy Policy', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Privacy Policy',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Last updated: January 1, 2024',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          
          _buildSection(
            '1. Introduction',
            'EnterTok ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how your personal information is collected, used, and disclosed by EnterTok when you use our mobile application and website (collectively, the "Service").',
          ),
          _buildSection(
            '2. Information We Collect',
            'We collect information you provide directly to us. For example, we collect information when you create an account, fill out a profile, upload content, communicate with us, or respond to surveys. The types of information we may collect include: name, email address, phone number, profile picture, and any other information you choose to provide.',
          ),
          _buildSection(
            '3. How We Use Information',
            'We use the information we collect to: provide, maintain, and improve our services; send you technical notices, updates, security alerts, and support messages; respond to your comments and questions; communicate with you about products, services, and events; monitor and analyze trends, usage, and activities; and detect, investigate, and prevent fraudulent transactions and other illegal activities.',
          ),
          _buildSection(
            '4. Sharing of Information',
            'We may share information about you as follows: with vendors, consultants, and other service providers who need access to such information to carry out work on our behalf; in response to a request for information if we believe disclosure is in accordance with any applicable law, regulation, or legal process; between and among EnterTok and our current and future parents, affiliates, subsidiaries, and other companies under common control and ownership.',
          ),
          _buildSection(
            '5. Data Security',
            'We take reasonable measures to help protect personal information from loss, theft, misuse, and unauthorized access, disclosure, alteration, and destruction. However, no security system is impenetrable and we cannot guarantee the security of our systems or your information.',
          ),
          _buildSection(
            '6. Your Choices',
            'You may update, correct, or delete your account information at any time by logging into your account or contacting us. You may also opt out of receiving promotional communications from us by following the instructions in those communications.',
          ),
          _buildSection(
            '7. Children\'s Privacy',
            'Our Service is not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13. If you are a parent or guardian and believe your child has provided us with personal information, please contact us.',
          ),
          _buildSection(
            '8. Third-Party Services',
            'Our Service may contain links to third-party websites, services, or applications that are not operated by us. We are not responsible for the privacy practices of these third parties and we encourage you to review the privacy policies of those third parties.',
          ),
          _buildSection(
            '9. Changes to Policy',
            'We may change this Privacy Policy from time to time. If we make changes, we will notify you by revising the date at the top of this policy and, in some cases, we may provide you with additional notice.',
          ),
          _buildSection(
            '10. Contact Us',
            'If you have any questions about this Privacy Policy, please contact us at: privacy@entertok.com',
          ),
          const SizedBox(height: 24),
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

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
