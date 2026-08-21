import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  // ── Home server — accessible from all devices on the LAN ──────────────────
  static const String serverHost = '192.168.1.7';
  static const String serverPort = '8082';
  static const String serverBase = 'http://$serverHost:$serverPort';
  static const String baseUrl = '$serverBase/api/v1';

  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  String? _token;

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;
  String? get token => _token;

  /// Resolve any relative /uploads/… URL to absolute
  static String resolveUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$serverBase$url';
    return url;
  }

  Map<String, String> get _headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null && _token!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_token';
    }
    return h;
  }

  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    try {
      Uri uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      debugPrint('GET $endpoint error: $e');
      if (endpoint.contains('/posts/feed') ||
          endpoint.contains('/posts/trending')) {
        return {'posts': []};
      }
      if (endpoint.contains('/products')) return {'products': []};
      if (endpoint.contains('/users/suggestions') ||
          endpoint.contains('/users/search')) {
        return {'users': []};
      }
      if (endpoint.contains('/notifications'))
        return {'notifications': [], 'unread_count': 0};
      if (endpoint.contains('/messages/conversations'))
        return {'conversations': []};
      throw ApiException('Network error: $e');
    }
  }

  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<dynamic> put(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<dynamic> delete(String endpoint) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl$endpoint'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  dynamic _handleResponse(http.Response response) {
    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true};
      }
      throw ApiException(
        'Request failed: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    final errorMsg = data['error'] ?? 'Unknown error';
    throw ApiException(
      '$errorMsg (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}
