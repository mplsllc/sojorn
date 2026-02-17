import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';
import '../models/auth_user.dart' as model;

enum AuthChangeEvent { signedIn, signedOut, tokenRefreshed }

class AuthState {
  final AuthChangeEvent event;
  final Session? session;
  const AuthState(this.event, this.session);
}

class Session {
  final String accessToken;
  final String tokenType;
  final User user;
  const Session({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });
}

class User {
  final String id;
  final String? email;
  final Map<String, dynamic> userMetadata;
  final String? role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const User({
    required this.id,
    this.email,
    this.userMetadata = const {},
    this.role,
    this.createdAt,
    this.updatedAt,
  });
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._internal();

  factory AuthService() {
    _instance ??= AuthService._internal();
    return _instance!;
  }

  final _storage = const FlutterSecureStorage();
  
  String? _accessToken;
  String? _temporaryToken; 
  model.AuthUser? _localUser;
  bool _initialized = false;
  final _authEventController = StreamController<AuthState>.broadcast();

  AuthService._internal() {
    _init();
  }

  Future<void> _init() async {
    if (_initialized) return;
    
    _accessToken = await _storage.read(key: 'access_token');
    final refreshToken = await _storage.read(key: 'refresh_token');
    
    _temporaryToken = await _storage.read(key: 'go_auth_token');
    final userJson = await _storage.read(key: 'go_auth_user');
    
    if (userJson != null) {
      try {
        _localUser = model.AuthUser.fromJson(jsonDecode(userJson));
      } catch (_) {}
    }

    if (_accessToken != null && refreshToken != null) {
      if (_isTokenExpired(_accessToken!)) {
        await refreshSession();
      }
    } else if (refreshToken != null) {
       await refreshSession();
    }

    _initialized = true;
    if (isAuthenticated) {
      _notifyGoAuthChange();
    }
  }
  
  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        return true;
      }
      final payload = json.decode(utf8.decode(base64Url.decode(base64.normalize(parts[1]))));
      if (payload is Map<String, dynamic> && payload.containsKey('exp')) {
        final exp = DateTime.fromMillisecondsSinceEpoch(payload['exp'] * 1000);
        return DateTime.now().isAfter(exp);
      }
    } catch (e) {
      return true;
    }
    return false; // Default to assumed valid if no exp
  }

  void _notifyGoAuthChange() {
    final event = AuthState(
      AuthChangeEvent.signedIn,
      Session(
        accessToken: _accessToken ?? '', 
        tokenType: 'bearer',
        user: currentUser!,
      ), 
    );
    _authEventController.add(event);
  }

  Future<void> ensureInitialized() async {
    if (!_initialized) await _init();
  }

  Future<bool> refreshSession() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data['access_token'], data['refresh_token']);
        return true;
      } else {
        await signOut(); // Refresh failed (revoked/expired), force logout
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<void> _saveTokens(String access, String refresh) async {
    _accessToken = access;
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
    await _storage.write(key: 'go_auth_token', value: access); 
    _temporaryToken = access;
  }

  User? get currentUser {
    if (_localUser != null) {
      return User(
        id: _localUser!.id,
        email: _localUser!.email,
        createdAt: _localUser!.createdAt,
        updatedAt: _localUser!.updatedAt,
      );
    }
    return null;
  }

  Session? get currentSession =>
      _accessToken != null && currentUser != null
          ? Session(
              accessToken: _accessToken!,
              tokenType: 'bearer',
              user: currentUser!,
            )
          : null;

  bool get isAuthenticated => accessToken != null;

  Stream<AuthState> get authStateChanges => _authEventController.stream;

  @Deprecated('Use registerWithGoBackend')
  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
  }

  Future<Map<String, dynamic>> signInWithGoBackend({
    required String email,
    required String password,
    required String altchaToken,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/login');
      // DEBUG: Log the API URL being used
      print('[AUTH] Login URL: $uri');
      print('[AUTH] API_BASE_URL from env: ${ApiConfig.baseUrl}');
      
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'altcha_token': altchaToken,
        }),
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        final accessToken = data['token'] ?? data['access_token'];
        final refreshToken = data['refresh_token'];
        
        if (accessToken == null || refreshToken == null) {
          throw AuthException('Invalid response from server: missing tokens');
        }
        
        await _saveTokens(accessToken as String, refreshToken as String);
        
        if (data['user'] != null) {
            final userJson = data['user'];
            try {
              _localUser = model.AuthUser.fromJson(userJson);
              await _storage.write(key: 'go_auth_user', value: jsonEncode(userJson));
            } catch (e) {
            }
        }
        
        if (data['profile'] != null) {
          final profileJson = data['profile'];
          await _storage.write(key: 'go_auth_profile_onboarding', value: profileJson['has_completed_onboarding'].toString());
        }

        // Store reactivation flag for welcome-back flow
        if (data['reactivated'] == true) {
          await _storage.write(key: 'account_reactivated', value: 'true');
          await _storage.write(key: 'account_previous_status', value: data['previous_status']?.toString() ?? '');
        } else {
          await _storage.delete(key: 'account_reactivated');
          await _storage.delete(key: 'account_previous_status');
        }

        _notifyGoAuthChange();
        return data;
      } else {
        throw AuthException(
          'Login failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Connection failed: $e');
    }
  }

  Future<Map<String, dynamic>> registerWithGoBackend({
    required String email,
    required String password,
    required String handle,
    required String displayName,
    required String altchaToken,
    required bool acceptTerms,
    required bool acceptPrivacy,
    bool emailNewsletter = false,
    bool emailContact = false,
    required int birthMonth,
    required int birthYear,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/register');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email, 
          'password': password,
          'handle': handle,
          'display_name': displayName,
          'altcha_token': altchaToken,
          'accept_terms': acceptTerms,
          'accept_privacy': acceptPrivacy,
          'email_newsletter': emailNewsletter,
          'email_contact': emailContact,
          'birth_month': birthMonth,
          'birth_year': birthYear,
        }),
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 201) {
        return data;
      } else {
        throw AuthException(
          'Registration failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Connection failed: $e');
    }
  }

  Future<void> signOut() async {
    _temporaryToken = null;
    _accessToken = null;
    _localUser = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'go_auth_token');
    await _storage.delete(key: 'go_auth_user');
    _authEventController.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  String? get accessToken => _accessToken ?? _temporaryToken ?? currentSession?.accessToken;

  Future<void> resetPassword(String email) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/forgot-password');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        throw AuthException(data['error'] ?? 'Failed to send reset email');
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Connection failed: $e');
    }
  }

  Future<void> updatePassword(String newPassword) async {
  }

  Future<void> markOnboardingCompleteLocally() async {
     await _storage.write(key: 'go_auth_profile_onboarding', value: 'true');
  }

  Future<bool> isOnboardingComplete() async {
    final val = await _storage.read(key: 'go_auth_profile_onboarding');
    return val == 'true';
  }
}
