import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'websocket_service.dart';
export 'api_client.dart';

class AuthService {
  // Use singleton ApiClient
  final ApiClient _apiClient = ApiClient();
  
  // Google Sign-In
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Keys for storing data
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userKey = 'user_data';
  static const String _tokenExpiryKey = 'token_expiry';

  // Current user data
  Map<String, dynamic>? _currentUser;

  // Getters
  ApiClient get apiClient => _apiClient;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _token != null;
  String? get _token => _apiClient.token;

  // Initialize - load token from storage and refresh if needed
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userData = prefs.getString(_userKey);
    final tokenExpiry = prefs.getInt(_tokenExpiryKey);

    if (token != null) {
      // Check if token is expired or about to expire (within 1 hour)
      final now = DateTime.now().millisecondsSinceEpoch;
      final shouldRefresh = tokenExpiry != null && 
          (tokenExpiry - now) < (3600 * 1000); // 1 hour
      
      _apiClient.setToken(token);
      if (userData != null) {
        _currentUser = jsonDecode(userData);
      }
      
      // Try to refresh token if needed for persistent login
      if (shouldRefresh) {
        await refreshToken();
      }
    }
  }

  // Register a new user
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
  }) async {
    final response = await _apiClient.post('/auth/register', body: {
      'username': username,
      'email': email,
      'password': password,
      'full_name': fullName ?? '',
    });

    if (response['token'] != null) {
      await _saveAuthData(response);
    }

    return response;
  }

  // Login user
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post('/auth/login', body: {
      'email': email,
      'password': password,
    });

    if (response['token'] != null) {
      await _saveAuthData(response);
    }

    return response;
  }

  // Login with Google
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      // Sign out first if already signed in
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      
      // Trigger Google Sign-In
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        throw Exception('Google sign-in was cancelled');
      }
      
      // Get auth details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      // Send to backend
      final response = await _apiClient.post('/auth/google', body: {
        'google_id': googleUser.id,
        'email': googleUser.email,
        'display_name': googleUser.displayName ?? '',
        'photo_url': googleUser.photoUrl ?? '',
        'id_token': googleAuth.idToken ?? '',
      });

      if (response['token'] != null) {
        await _saveAuthData(response);
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Login with Google (manual - using provided data)
  Future<Map<String, dynamic>> loginWithGoogle({
    required String googleId,
    required String email,
    String? displayName,
    String? photoUrl,
    String? idToken,
  }) async {
    final response = await _apiClient.post('/auth/google', body: {
      'google_id': googleId,
      'email': email,
      'display_name': displayName ?? '',
      'photo_url': photoUrl ?? '',
      'id_token': idToken ?? '',
    });

    if (response['token'] != null) {
      await _saveAuthData(response);
    }

    return response;
  }

  // Logout user
  Future<void> logout() async {
    WebSocketService().disconnect();
    _apiClient.clearToken();
    _currentUser = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_tokenExpiryKey);
    await prefs.remove(_userKey);
  }

  // Get current user profile
  Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await _apiClient.get('/auth/me');
    _currentUser = response;
    return response;
  }

  // Change password
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _apiClient.post('/auth/change-password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  // Save auth data to storage (including refresh token for persistent login)
  Future<void> _saveAuthData(Map<String, dynamic> response) async {
    final token = response['token'];
    final refreshToken = response['refresh_token'];
    final user = response['user'];
    final expiresIn = response['expires_in'] as int?; // seconds until expiry

    if (token != null) {
      _apiClient.setToken(token);
      _currentUser = user;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      
      if (refreshToken != null) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }
      
      final expiryTimestamp = DateTime.now().millisecondsSinceEpoch + 
          ((expiresIn ?? 86400) * 1000);
      await prefs.setInt(_tokenExpiryKey, expiryTimestamp);
      await prefs.setString(_userKey, jsonEncode(user));

      // Connect WebSocket after successful auth
      WebSocketService().connect(token);
    }
  }

  // Refresh token to keep user logged in
  Future<bool> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
    
    if (refreshToken == null) {
      return false;
    }
    
    try {
      final response = await _apiClient.post('/auth/refresh', body: {
        'refresh_token': refreshToken,
      });
      
      if (response['token'] != null) {
        await _saveAuthData(response);
        return true;
      }
      return false;
    } catch (e) {
      // Refresh failed - clear tokens
      await logout();
      return false;
    }
  }

  // Check if user is logged in
  Future<bool> checkAuth() async {
    if (_token == null) return false;
    
    try {
      await getCurrentUser();
      return true;
    } catch (e) {
      await logout();
      return false;
    }
  }
}
