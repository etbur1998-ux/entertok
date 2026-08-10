import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/upload_service.dart';
import '../services/api_client.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _authService = AuthService();
  final _userService = UserService();

  late TextEditingController _nameCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _websiteCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _phoneCtrl;

  bool _isLoading = false;
  bool _isSaving = false;
  String? _profileImageUrl;
  File? _localImage;

  @override
  void initState() {
    super.initState();
    final u = _authService.currentUser;
    _nameCtrl = TextEditingController(text: u?['full_name']?.toString() ?? '');
    _bioCtrl = TextEditingController(text: u?['bio']?.toString() ?? '');
    _websiteCtrl = TextEditingController(text: u?['website']?.toString() ?? '');
    _locationCtrl = TextEditingController(
      text: u?['location']?.toString() ?? '',
    );
    _phoneCtrl = TextEditingController(text: u?['phone']?.toString() ?? '');
    _profileImageUrl = u?['profile_image']?.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _websiteCtrl.dispose();
    _locationCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
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
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickFromGallery();
              },
            ),
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take a Photo'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickFromCamera();
                },
              ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.deepPurple),
              title: const Text('Enter Image URL'),
              onTap: () async {
                Navigator.pop(ctx);
                await _enterUrl();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS) {
        final r = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (r != null && r.files.isNotEmpty && r.files.first.path != null) {
          setState(() => _localImage = File(r.files.first.path!));
        }
      } else {
        final x = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 800,
        );
        if (x != null) setState(() => _localImage = File(x.path));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 800,
      );
      if (x != null && mounted) setState(() => _localImage = File(x.path));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _enterUrl() async {
    final ctrl = TextEditingController(text: _profileImageUrl ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Profile Photo URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dlg, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _profileImageUrl = result;
        _localImage = null;
      });
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
      return;
    }
    setState(() => _isSaving = true);
    try {
      String? finalPhotoUrl = _profileImageUrl;
      // Upload local image if picked
      if (_localImage != null && !kIsWeb) {
        final uploaded = await UploadService().uploadImage(_localImage!);
        if (uploaded != null && uploaded.isNotEmpty) finalPhotoUrl = uploaded;
      }

      await _userService.updateProfile(
        fullName: _nameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        website: _websiteCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        profileImage: finalPhotoUrl,
      );
      await _authService.getCurrentUser();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedPic = _profileImageUrl != null
        ? ApiClient.resolveUrl(_profileImageUrl)
        : '';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Avatar picker
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _pickProfileImage,
                          child: CircleAvatar(
                            radius: 52,
                            backgroundColor: Colors.deepPurple,
                            backgroundImage: _localImage != null && !kIsWeb
                                ? FileImage(_localImage!) as ImageProvider
                                : (resolvedPic.isNotEmpty
                                      ? NetworkImage(resolvedPic)
                                      : null),
                            child: (_localImage == null && resolvedPic.isEmpty)
                                ? const Icon(
                                    Icons.person,
                                    size: 52,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: _pickProfileImage,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: const BoxDecoration(
                                color: Colors.deepPurple,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _pickProfileImage,
                    child: const Text('Change Photo'),
                  ),
                  const SizedBox(height: 20),
                  _field(_nameCtrl, 'Full Name', Icons.person, required: true),
                  const SizedBox(height: 14),
                  _field(
                    _bioCtrl,
                    'Bio',
                    Icons.info_outline,
                    maxLines: 3,
                    hint: 'Tell people about yourself',
                  ),
                  const SizedBox(height: 14),
                  _field(
                    _phoneCtrl,
                    'Phone',
                    Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    _websiteCtrl,
                    'Website',
                    Icons.link,
                    hint: 'https://yourwebsite.com',
                  ),
                  const SizedBox(height: 14),
                  _field(
                    _locationCtrl,
                    'Location',
                    Icons.location_on,
                    hint: 'City, Country',
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
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
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
    bool required = false,
  }) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label + (required ? ' *' : ''),
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.deepPurple),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
      alignLabelWithHint: maxLines > 1,
    ),
  );
}
