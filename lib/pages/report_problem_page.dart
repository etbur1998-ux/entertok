import 'package:flutter/material.dart';

class ReportProblemPage extends StatefulWidget {
  const ReportProblemPage({super.key});

  @override
  State<ReportProblemPage> createState() => _ReportProblemPageState();
}

class _ReportProblemPageState extends State<ReportProblemPage> {
  final TextEditingController _descriptionController = TextEditingController();
  String? _selectedIssue;

  final List<Map<String, dynamic>> _issueTypes = [
    {'icon': Icons.person, 'title': 'Account Issue', 'description': 'Login, password, or account access problems'},
    {'icon': Icons.videocam, 'title': 'Live Streaming', 'description': 'Issues with going live or watching streams'},
    {'icon': Icons.chat, 'title': 'Messaging', 'description': 'Problems with messages or chats'},
    {'icon': Icons.video_library, 'title': 'Video/Post', 'description': 'Issues with uploading or viewing content'},
    {'icon': Icons.shopping_bag, 'title': 'Shopping', 'description': 'Problems with purchases or orders'},
    {'icon': Icons.report, 'title': 'Report Content', 'description': 'Report inappropriate content or behavior'},
    {'icon': Icons.copyright, 'title': 'Copyright', 'description': 'Report copyright infringement'},
    {'icon': Icons.more_horiz, 'title': 'Other', 'description': 'Something else'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Report a Problem', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'What kind of problem are you experiencing?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          // Issue type selection
          ..._issueTypes.map((issue) => GestureDetector(
            onTap: () {
              setState(() {
                _selectedIssue = issue['title'];
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedIssue == issue['title'] 
                    ? Colors.deepPurple.withValues(alpha: 0.1) 
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedIssue == issue['title'] 
                      ? Colors.deepPurple 
                      : Colors.grey[300]!,
                  width: _selectedIssue == issue['title'] ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    issue['icon'],
                    color: _selectedIssue == issue['title'] 
                        ? Colors.deepPurple 
                        : Colors.grey[700],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          issue['title'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _selectedIssue == issue['title'] 
                                ? Colors.deepPurple 
                                : Colors.black,
                          ),
                        ),
                        Text(
                          issue['description'],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedIssue == issue['title'])
                    const Icon(Icons.check_circle, color: Colors.deepPurple),
                ],
              ),
            ),
          )),
          
          const SizedBox(height: 16),
          
          // Description
          if (_selectedIssue != null) ...[
            const Text(
              'Describe your problem in detail',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Please provide as much detail as possible...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Screenshot attachment
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.attach_file, color: Colors.grey[600]),
                  const SizedBox(width: 12),
                  Text(
                    'Add screenshot (optional)',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_descriptionController.text.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Report submitted successfully!')),
                    );
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please describe your problem')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                child: const Text('Submit Report'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
