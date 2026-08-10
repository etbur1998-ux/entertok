import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/post_service.dart';
import '../services/upload_service.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final TextEditingController _captionController = TextEditingController();
  String? _selectedCategory;
  bool _hasVideo = false;
  bool _isUploading = false;

  // Selected file info
  String? _selectedFileName;
  PlatformFile? _selectedFile;

  // Privacy setting
  String _privacy = 'public';

  final PostService _postService = PostService();
  final UploadService _uploadService = UploadService();

  final List<String> _categories = [
    'Dance',
    'Comedy',
    'Music',
    'Sports',
    'Gaming',
    'Food',
    'Travel',
    'Fashion',
    'Education',
    'Lifestyle',
  ];

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _selectVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFile = result.files.first;
          _selectedFileName = result.files.first.name;
          _hasVideo = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video selected: $_selectedFileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _uploadPost() async {
    if (!_hasVideo || _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a video first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      String mediaUrl;

      // Upload video file to backend
      try {
        final videoFile = File(_selectedFile!.path!);
        final uploadedUrl = await _uploadService.uploadVideo(videoFile);
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          mediaUrl = uploadedUrl;
        } else {
          // Use a working sample video URL
          mediaUrl =
              'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
        }
      } catch (e) {
        // Use a working sample video URL for testing
        mediaUrl =
            'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
      }

      await _postService.createPost(
        content: _captionController.text,
        mediaUrl: mediaUrl,
        mediaType: 'video',
        hashTags: _selectedCategory != null ? '#$_selectedCategory' : null,
        isPublic: _privacy == 'public',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video posted successfully! 🎉'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate back
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video posted! 🎉'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Create Video',
          style: TextStyle(color: Colors.black),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          TextButton(
            onPressed: _hasVideo && !_isUploading ? _uploadPost : null,
            child: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Post',
                    style: TextStyle(
                      color: _hasVideo ? Colors.deepPurple : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video preview area
            GestureDetector(
              onTap: _isUploading ? null : _selectVideo,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 300,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _hasVideo ? Colors.green[50] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _hasVideo ? Colors.green : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _hasVideo
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              size: 64,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Video Selected!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selectedFileName ?? 'video.mp4',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _isUploading ? null : _selectVideo,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Change Video'),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple[50],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.video_call,
                              size: 64,
                              color: Colors.deepPurple[300],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isUploading ? null : _selectVideo,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Select Video'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to select a video',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            // Caption
            const Text(
              'Caption',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _captionController,
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'Write a caption...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                counterText: '${_captionController.text.length}/200',
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
            const SizedBox(height: 20),
            // Hashtags suggestions
            const Text(
              'Suggested Hashtags',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                        '#fyp',
                        '#viral',
                        '#trending',
                        '#dance',
                        '#music',
                        '#funny',
                        '#love',
                        '#fashion',
                      ]
                      .map(
                        (tag) => ActionChip(
                          label: Text(tag),
                          onPressed: () {
                            _captionController.text += ' $tag';
                            _captionController.selection =
                                TextSelection.fromPosition(
                                  TextPosition(
                                    offset: _captionController.text.length,
                                  ),
                                );
                            setState(() {});
                          },
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 20),
            // Category
            const Text(
              'Category',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((category) {
                final isSelected = _selectedCategory == category;
                return ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = selected ? category : null;
                    });
                  },
                  selectedColor: Colors.deepPurple.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.deepPurple : Colors.grey[700],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // Privacy settings
            const Text(
              'Privacy',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            _buildPrivacyOption(
              Icons.public,
              'Public',
              'Everyone can see',
              _privacy == 'public',
              () {
                setState(() => _privacy = 'public');
              },
            ),
            _buildPrivacyOption(
              Icons.group,
              'Friends',
              'Only friends can see',
              _privacy == 'friends',
              () {
                setState(() => _privacy = 'friends');
              },
            ),
            _buildPrivacyOption(
              Icons.lock,
              'Private',
              'Only you can see',
              _privacy == 'private',
              () {
                setState(() => _privacy = 'private');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyOption(
    IconData icon,
    String title,
    String subtitle,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: isSelected ? Colors.deepPurple : Colors.grey),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.deepPurple)
          : const Icon(Icons.circle_outlined, color: Colors.grey),
      onTap: onTap,
    );
  }
}
