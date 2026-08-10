import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class UploadService {
  static String get _baseUrl => ApiClient.baseUrl;

  String _toAbsolute(String url) => ApiClient.resolveUrl(url);

  Future<Map<String, dynamic>> uploadFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) throw Exception('Not authenticated');

    final fileName = filePath.split('/').last;
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    String endpoint = '/uploads/file';
    if (['mp4', 'mov', 'avi', 'webm'].contains(ext)) {
      endpoint = '/uploads/video';
    } else if (['jpg', 'jpeg', 'png', 'gif'].contains(ext)) {
      endpoint = '/uploads/image';
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$endpoint'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final urlMatch = RegExp(
        r'"url"\s*:\s*"([^"]+)"',
      ).firstMatch(response.body);
      final fnMatch = RegExp(
        r'"filename"\s*:\s*"([^"]+)"',
      ).firstMatch(response.body);
      final szMatch = RegExp(r'"size"\s*:\s*(\d+)').firstMatch(response.body);
      return {
        'url': _toAbsolute(urlMatch?.group(1) ?? ''),
        'filename': fnMatch?.group(1) ?? fileName,
        'size': int.tryParse(szMatch?.group(1) ?? '0') ?? 0,
      };
    }
    throw Exception('Upload failed: ${response.statusCode}');
  }

  Future<String?> uploadVideo(File videoFile) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/uploads/video'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      await http.MultipartFile.fromPath('video', videoFile.path),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final match = RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(response.body);
      if (match != null) return _toAbsolute(match.group(1) ?? '');
    }
    return null;
  }

  Future<String?> uploadImage(File imageFile) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/uploads/image'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final match = RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(response.body);
      if (match != null) return _toAbsolute(match.group(1) ?? '');
    }
    return null;
  }
}
