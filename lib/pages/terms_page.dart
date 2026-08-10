import 'package:flutter/material.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Terms of Service', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Terms of Service',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Last updated: January 1, 2024',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          
          _buildSection(
            '1. Acceptance of Terms',
            'By accessing and using EnterTok, you accept and agree to be bound by the terms and provision of this agreement. Additionally, when using EnterTok\'s services, you shall be subject to any posted guidelines or rules applicable to such services.',
          ),
          _buildSection(
            '2. Description of Service',
            'EnterTok provides users with access to a rich collection of resources, including various communications tools, forums, shopping services, personalized content, and branded programming through its network of properties. You also understand and agree that the service may include advertisements and that these advertisements are necessary for EnterTok to provide the service.',
          ),
          _buildSection(
            '3. Registration Obligations',
            'In consideration of your use of the Service, you agree to: (a) provide true, accurate, current, and complete information about yourself as prompted by the Service\'s registration form and (b) maintain and promptly update the registration data to keep it true, accurate, current, and complete.',
          ),
          _buildSection(
            '4. Privacy Policy',
            'Registration data and certain other information about you is subject to our Privacy Policy. You understand that through your use of the Service, you consent to the collection and use of this information, including the transfer of this information to other countries for storage, processing, and use.',
          ),
          _buildSection(
            '5. User Conduct',
            'You agree not to use the Service to: upload, post, email, transmit, or otherwise make available any content that is unlawful, harmful, threatening, abusive, harassing, tortious, defamatory, vulgar, obscene, libelous, invasive of another\'s privacy, hateful, or racially, ethnically, or otherwise objectionable.',
          ),
          _buildSection(
            '6. Content Posted',
            'You are solely responsible for the content that you publish or display on the Service, or any material or information that you transmit to other members. You agree that EnterTok may delete any content that in its sole discretion violates, or may violate, any applicable law or the terms or spirit of this Agreement.',
          ),
          _buildSection(
            '7. Indemnity',
            'You agree to indemnify and hold EnterTok, and its subsidiaries, affiliates, officers, agents, co-branders, or other partners, and employees, harmless from any claim or demand, including reasonable attorneys\' fees, made by any third party due to or arising out of Content you submit, post, transmit, or make available through the Service.',
          ),
          _buildSection(
            '8. No Resale of Service',
            'You agree not to reproduce, duplicate, copy, sell, resell, or exploit for any commercial purposes, any portion of the Service, use of the Service, or access to the Service.',
          ),
          _buildSection(
            '9. Modifications to Service',
            'EnterTok reserves the right at any time and from time to time to modify or discontinue, temporarily or permanently, the Service (or any part thereof) with or without notice. You agree that EnterTok shall not be liable to you or to any third party for any modification, suspension, or discontinuance of the Service.',
          ),
          _buildSection(
            '10. Termination',
            'You agree that EnterTok, in its sole discretion, may terminate your password, account (or any part thereof), or use of the Service, and remove and discard any Content within the Service, for any reason, including, without limitation, for lack of use or if EnterTok believes that you have violated or acted inconsistently with the letter or spirit of this Agreement.',
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
