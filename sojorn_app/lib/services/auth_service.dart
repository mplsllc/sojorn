// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  /// Single-flight guard: only one refresh at a time.
  Completer<bool>? _refreshCompleter;
  final _authEventController = StreamController<AuthState>.broadcast();
  Timer? _refreshTimer;

  AuthService._internal() {
    _init();
  }

  Future<void> _init() async {
    if (_initialized) return;
    if (kDebugMode) debugPrint('[AUTH] Initializing auth service...');

    _accessToken = await _storage.read(key: 'access_token');
    final refreshToken = await _storage.read(key: 'refresh_token');

    _temporaryToken = await _storage.read(key: 'go_auth_token');
    final userJson = await _storage.read(key: 'go_auth_user');

    if (userJson != null) {
      try {
        _localUser = model.AuthUser.fromJson(jsonDecode(userJson));
        if (kDebugMode) debugPrint('[AUTH] Loaded cached user: ${_localUser?.email ?? _localUser?.id}');
      } catch (_) {
        if (kDebugMode) debugPrint('[AUTH] Failed to parse cached user JSON');
      }
    }

    if (_accessToken != null && refreshToken != null) {
      if (_isTokenExpired(_accessToken!)) {
        if (kDebugMode) debugPrint('[AUTH] Access token expired, refreshing...');
        await refreshSession();
      } else {
        if (kDebugMode) debugPrint('[AUTH] Access token valid');
      }
    } else if (refreshToken != null) {
      if (kDebugMode) debugPrint('[AUTH] No access token but have refresh token, refreshing...');
       await refreshSession();
    } else {
      if (kDebugMode) debugPrint('[AUTH] No tokens found — user not authenticated');
    }

    _initialized = true;
    if (isAuthenticated) {
      if (kDebugMode) debugPrint('[AUTH] Init complete — authenticated as ${_localUser?.email ?? currentUser?.id}');
      _notifyGoAuthChange();
    } else {
      if (kDebugMode) debugPrint('[AUTH] Init complete — not authenticated');
    }
  }
  
  bool get isAccessTokenExpired =>
      _accessToken == null || _isTokenExpired(_accessToken!);

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
    // Single-flight: if a refresh is already in progress, piggyback on it.
    if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      if (kDebugMode) debugPrint('[AUTH] Refresh already in flight — waiting');
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final result = await _doRefresh();
      _refreshCompleter!.complete(result);
      return result;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      // Reset so future refresh attempts aren't stuck on a stale completer.
      _refreshCompleter = null;
    }
  }

  Future<bool> _doRefresh() async {
    if (kDebugMode) debugPrint('[AUTH] Attempting token refresh...');
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) {
      if (kDebugMode) debugPrint('[AUTH] No refresh token available');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data['access_token'], data['refresh_token']);
        if (kDebugMode) debugPrint('[AUTH] Token refresh successful');
        return true;
      } else {
        if (kDebugMode) debugPrint('[AUTH] Token refresh failed (${response.statusCode}) — signing out');
        await signOut();
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AUTH] Token refresh error: $e — signing out');
      await signOut();
      return false;
    }
  }

  Future<void> _saveTokens(String access, String refresh) async {
    _accessToken = access;
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
    await _storage.write(key: 'go_auth_token', value: access);
    _temporaryToken = access;
    _scheduleProactiveRefresh(access);
  }

  /// Parses the JWT exp claim and schedules a silent refresh 2 minutes before
  /// the token expires, avoiding the extra 401 round-trip on short-lived JWTs.
  void _scheduleProactiveRefresh(String token) {
    _refreshTimer?.cancel();
    try {
      final parts = token.split('.');
      if (parts.length != 3) return;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64.normalize(parts[1]))),
      );
      if (payload is Map<String, dynamic> && payload.containsKey('exp')) {
        final exp = DateTime.fromMillisecondsSinceEpoch(payload['exp'] * 1000);
        // Refresh 2 minutes before expiry (or immediately if <2 min left)
        final refreshAt = exp.subtract(const Duration(minutes: 2));
        final delay = refreshAt.difference(DateTime.now());
        if (delay.isNegative) return; // Already near/past expiry — let 401 handler do it
        _refreshTimer = Timer(delay, () async {
          await refreshSession();
        });
      }
    } catch (_) {
      // Silently ignore parse errors — 401 handler is the fallback
    }
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
      if (kDebugMode) debugPrint('[AUTH] Login attempt for $email');
      if (kDebugMode) debugPrint('[AUTH] Login URL: $uri');
      
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
        if (kDebugMode) debugPrint('[AUTH] Login successful');
        final accessToken = data['token'] ?? data['access_token'];
        final refreshToken = data['refresh_token'];

        if (accessToken == null || refreshToken == null) {
          if (kDebugMode) debugPrint('[AUTH] Login response missing tokens!');
          throw AuthException('Invalid response from server: missing tokens');
        }

        await _saveTokens(accessToken as String, refreshToken as String);

        if (data['user'] != null) {
            final userJson = data['user'];
            try {
              _localUser = model.AuthUser.fromJson(userJson);
              await _storage.write(key: 'go_auth_user', value: jsonEncode(userJson));
              if (kDebugMode) debugPrint('[AUTH] User saved: ${_localUser?.email}');
            } catch (e) {
              if (kDebugMode) debugPrint('[AUTH] Failed to parse user from login response: $e');
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
    if (kDebugMode) debugPrint('[AUTH] Signing out — clearing all tokens');
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _temporaryToken = null;
    _accessToken = null;
    _localUser = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'go_auth_token');
    await _storage.delete(key: 'go_auth_user');
    _authEventController.add(const AuthState(AuthChangeEvent.signedOut, null));
    if (kDebugMode) debugPrint('[AUTH] Sign out complete');
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
