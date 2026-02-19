import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/category.dart' as models;
import '../models/profile.dart';
import '../models/follow_request.dart';
import '../models/profile_privacy_settings.dart';
import '../models/post.dart';
import '../models/user_settings.dart';
import '../models/comment.dart';
import '../models/notification.dart';
import '../models/beacon.dart';
import '../models/group.dart';
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../models/search_results.dart';
import '../models/tone_analysis.dart';
import '../utils/security_utils.dart';
import '../utils/request_signing.dart';
import 'package:http/http.dart' as http;
/// ApiService - Single source of truth for all backend communication.
class ApiService {
  final AuthService _authService;
  final http.Client _httpClient;

  ApiService(this._authService) : _httpClient = http.Client();

  // Singleton pattern helper if needed, but usually passed via DI/Riverpod
  static ApiService? _instance;
  static ApiService get instance =>
      _instance ??= ApiService(AuthService.instance);

  /// Generic caller for specialized edge endpoints. Handles response parsing
  /// and normalization across different response formats.
  Future<Map<String, dynamic>> _callFunction(
    String functionName, {
    String method = 'POST',
    Map<String, dynamic>? queryParams,
    Object? body,
  }) async {
    // Proxy through Go API to avoid CORS issues and Mixed Content
    return await _callGoApi(
      '/functions/$functionName',
      method: method.toUpperCase(),
      queryParams: queryParams?.map((k, v) => MapEntry(k, v.toString())),
      body: body,
    );
  }

  /// Generic function caller for the new Go API on the VPS.
  /// Includes Retry-on-401 logic (Session Manager)
  Future<Map<String, dynamic>> callGoApi(String path,
      {String method = 'POST',
      Map<String, dynamic>? body,
      Map<String, String>? queryParams}) async {
    return _callGoApi(path,
        method: method, body: body, queryParams: queryParams);
  }

  Future<Map<String, dynamic>> _callGoApi(
    String path, {
    String method = 'POST',
    Map<String, String>? queryParams,
    Object? body,
    bool requireSignature = false,
  }) async {
    final sanitized = _sanitizePath(path);
    if (kDebugMode) debugPrint('[API] → $method $sanitized');
    try {
      var uri = Uri.parse('${ApiConfig.baseUrl}$path')
          .replace(queryParameters: queryParams);
      var headers = await _authHeaders();
      headers['Content-Type'] = 'application/json';

      // Add request signature for critical operations
      if (requireSignature && body != null) {
        final secretKey = _authService.currentUser?.id ?? 'default';
        headers = RequestSigning.addSignatureHeaders(
          headers,
          method,
          path,
          body as Map<String, dynamic>?,
          secretKey,
        );
      }

      http.Response response =
          await _performRequest(method, uri, headers, body);

      // INTERCEPTOR: Handle 401
      if (response.statusCode == 401) {
        if (kDebugMode) debugPrint('[API] 401 $sanitized — refreshing session');
        final refreshed = await _authService.refreshSession();
        if (refreshed) {
          headers = await _authHeaders();
          headers['Content-Type'] = 'application/json';
          if (kDebugMode) debugPrint('[API] retrying $sanitized');
          response = await _performRequest(method, uri, headers, body);
        } else {
          throw Exception('Session Expired');
        }
      }

      if (response.statusCode >= 400) {
        if (kDebugMode) debugPrint('[API] ✗ ${response.statusCode} $sanitized  body=${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
        throw Exception(
            'Go API error (${response.statusCode}): ${response.body}');
      }

      if (kDebugMode) debugPrint('[API] ✓ ${response.statusCode} $sanitized');
      if (response.body.isEmpty) return {};
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
      return {'data': data};
    } catch (e) {
      if (kDebugMode) debugPrint('[API] ✗ EXCEPTION $sanitized — $e');
      rethrow;
    }
  }

  Future<http.Response> _performRequest(
      String method, Uri uri, Map<String, String> headers, Object? body) async {
    switch (method.toUpperCase()) {
      case 'GET':
        return await _httpClient.get(uri, headers: headers);
      case 'PATCH':
        return await _httpClient.patch(uri,
            headers: headers, body: jsonEncode(body));
      case 'DELETE':
        return await _httpClient.delete(uri,
            headers: headers, body: jsonEncode(body));
      default:
        return await _httpClient.post(uri,
            headers: headers, body: jsonEncode(body));
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    // Ensure AuthService has loaded tokens from storage
    await _authService.ensureInitialized();

    final token = _authService.accessToken;

    if (token == null || token.isEmpty) {
      return {};
    }

    return {
      'Authorization': 'Bearer $token',
    };
  }

  /// Sanitize path for logging by removing sensitive IDs
  String _sanitizePath(String path) {
    return path.replaceAll(RegExp(r'/[a-zA-Z0-9_-]{20,}'), '/***');
  }

  /// Generate unique request ID for tracking
  String _generateRequestId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
  }

  List<Map<String, dynamic>> _normalizeListResponse(dynamic response) {
    if (response == null) return [];
    if (response is List<dynamic>) {
      return response
          .whereType<Map<String, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (response is Map<String, dynamic>) return [response];
    return [];
  }

  /// Simple GET request helper
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParams}) async {
    return _callGoApi(path, method: 'GET', queryParams: queryParams);
  }

  /// Simple POST request helper
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    return _callGoApi(path, method: 'POST', body: body);
  }

  /// Simple DELETE request helper
  Future<Map<String, dynamic>> delete(String path) async {
    return _callGoApi(path, method: 'DELETE');
  }


  Future<void> resendVerificationEmail(String email) async {
    await _callGoApi('/auth/resend-verification',
        method: 'POST', body: {'email': email});
  }

  // =========================================================================
  // Category & Onboarding
  // =========================================================================

  Future<List<models.Category>> getCategories() async {
    final data = await _callGoApi('/categories', method: 'GET');
    return (data['categories'] as List)
        .map((json) => models.Category.fromJson(json))
        .toList();
  }

  Future<List<models.Category>> getEnabledCategories() async {
    final categories = await getCategories();
    final enabledIds = await _getEnabledCategoryIds();

    if (enabledIds.isEmpty) {
      return categories.where((category) => !category.defaultOff).toList();
    }

    return categories
        .where((category) => enabledIds.contains(category.id))
        .toList();
  }

  Future<bool> hasProfile() async {
    final user = _authService.currentUser;
    if (user == null) return false;

    final data = await _callGoApi('/profile', method: 'GET');
    return data['profile'] != null;
  }

  Future<bool> hasCategorySelection() async {
    try {
      final enabledIds = await _getEnabledCategoryIds();
      return enabledIds.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> setUserCategorySettings({
    required List<models.Category> categories,
    required Set<String> enabledCategoryIds,
  }) async {
    final settings = categories
        .map((category) => {
              'category_id': category.id,
              'enabled': enabledCategoryIds.contains(category.id),
            })
        .toList();

    await _callGoApi(
      '/categories/settings',
      method: 'POST',
      body: {'settings': settings},
    );
  }

  Future<void> completeOnboarding() async {
    await _callGoApi('/complete-onboarding', method: 'POST');
    // Also update local storage so app knows immediately (AuthService)
    await _authService.markOnboardingCompleteLocally();
  }

  Future<Set<String>> _getEnabledCategoryIds() async {
    final data = await _callGoApi('/categories/settings', method: 'GET');
    final settings = data['settings'] as List? ?? [];
    return settings
        .where((s) => s['enabled'] == true)
        .map((s) => s['category_id'] as String)
        .toSet();
  }

  // =========================================================================
  // Profile & Auth
  // =========================================================================

  Future<Profile> createProfile({
    required String handle,
    required String displayName,
    String? bio,
  }) async {
    // Validate and sanitize inputs
    if (!SecurityUtils.isValidHandle(handle)) {
      throw ArgumentError('Invalid handle format');
    }
    if (!SecurityUtils.isValidEmail(_authService.currentUser?.email ?? '')) {
      throw ArgumentError('Invalid user email');
    }
    
    final sanitizedHandle = SecurityUtils.sanitizeText(handle);
    final sanitizedDisplayName = SecurityUtils.sanitizeText(displayName);
    final sanitizedBio = bio != null ? SecurityUtils.sanitizeText(bio) : null;
    
    // Legacy support: still calls generic 'signup' but via auth flow in AuthService usually.
    // Making this use the endpoint just in case called directly.
    // Adjust based on backend. If this requires token, it's fine.
    // A 'create profile' usually happens after 'auth register'.
    // If this is the 'onboarding' step for a user who exists but has no profile:
    final data = await _callGoApi(
      '/profile', // Changed from '/auth/signup' to '/profile'
      method: 'POST', // Changed from 'POST' to 'POST'
      body: {
        'handle': sanitizedHandle,
        'display_name': sanitizedDisplayName,
        if (sanitizedBio != null) 'bio': sanitizedBio,
      },
    );

    return Profile.fromJson(data['profile']);
  }

  Future<Map<String, dynamic>> getProfile({String? handle}) async {
    final data = await _callGoApi(
      '/profile',
      method: 'GET',
      queryParams: handle != null ? {'handle': handle} : null,
    );

    return {
      'profile': Profile.fromJson(data['profile'] as Map<String, dynamic>),
      'stats': ProfileStats.fromJson(data['stats'] as Map<String, dynamic>?),
      'is_following': data['is_following'] as bool? ?? false,
      'is_followed_by': data['is_followed_by'] as bool? ?? false,
      'is_friend': data['is_friend'] as bool? ?? false,
      'follow_status': data['follow_status'] as String?,
      'is_private': data['is_private'] as bool? ?? false,
    };
  }

  Future<Map<String, dynamic>> getProfileById(String userId) async {
    final data = await _callGoApi(
      '/profiles/$userId',
      method: 'GET',
    );

    return {
      'profile': Profile.fromJson(data['profile'] as Map<String, dynamic>),
      'stats': ProfileStats.fromJson(data['stats'] as Map<String, dynamic>?),
      'is_following': data['is_following'] as bool? ?? false,
      'is_followed_by': data['is_followed_by'] as bool? ?? false,
      'is_friend': data['is_friend'] as bool? ?? false,
      'follow_status': data['follow_status'] as String?,
      'is_private': data['is_private'] as bool? ?? false,
    };
  }

  Future<Profile> updateProfile({
    String? handle,
    String? displayName,
    String? bio,
    String? location,
    String? website,
    List<String>? interests,
    String? avatarUrl,
    String? coverUrl,
    String? identityKey,
    int? registrationId,
    String? encryptedPrivateKey,
  }) async {
    // Validate and sanitize inputs
    if (handle != null && !SecurityUtils.isValidHandle(handle)) {
      throw ArgumentError('Invalid handle format');
    }
    
    final sanitizedHandle = handle != null ? SecurityUtils.sanitizeText(handle) : null;
    final sanitizedDisplayName = displayName != null ? SecurityUtils.sanitizeText(displayName) : null;
    final sanitizedBio = bio != null ? SecurityUtils.sanitizeText(bio) : null;
    final sanitizedLocation = location != null ? SecurityUtils.sanitizeText(location) : null;
    final sanitizedWebsite = website != null ? SecurityUtils.sanitizeUrl(website) : null;
    final sanitizedInterests = interests?.map((i) => SecurityUtils.sanitizeText(i)).toList();
    final sanitizedAvatarUrl = avatarUrl != null ? SecurityUtils.sanitizeUrl(avatarUrl) : null;
    final sanitizedCoverUrl = coverUrl != null ? SecurityUtils.sanitizeUrl(coverUrl) : null;
    
    final data = await _callGoApi(
      '/profile',
      method: 'PATCH',
      body: {
        if (sanitizedHandle != null) 'handle': sanitizedHandle,
        if (sanitizedDisplayName != null) 'display_name': sanitizedDisplayName,
        if (sanitizedBio != null) 'bio': sanitizedBio,
        if (sanitizedLocation != null) 'location': sanitizedLocation,
        if (sanitizedWebsite != null) 'website': sanitizedWebsite,
        if (sanitizedInterests != null) 'interests': sanitizedInterests,
        if (sanitizedAvatarUrl != null) 'avatar_url': sanitizedAvatarUrl,
        if (sanitizedCoverUrl != null) 'cover_url': sanitizedCoverUrl,
        if (identityKey != null) 'identity_key': identityKey,
        if (registrationId != null) 'registration_id': registrationId,
        if (encryptedPrivateKey != null)
          'encrypted_private_key': encryptedPrivateKey,
      },
      requireSignature: true,
    );

    return Profile.fromJson(data['profile']);
  }

  Future<ProfilePrivacySettings> getPrivacySettings() async {
    try {
      final data = await _callGoApi('/settings/privacy', method: 'GET');
      return ProfilePrivacySettings.fromJson(data);
    } catch (_) {
      // Fallback defaults
      final userId = _authService.currentUser?.id ?? '';
      return ProfilePrivacySettings.defaults(userId);
    }
  }

  Future<ProfilePrivacySettings> updatePrivacySettings(
    ProfilePrivacySettings settings,
  ) async {
    final data = await _callGoApi(
      '/settings/privacy',
      method: 'PATCH',
      body: settings.toJson(),
    );
    return ProfilePrivacySettings.fromJson(data);
  }

  Future<UserSettings> getUserSettings() async {
    try {
      final data = await _callGoApi('/settings/user', method: 'GET');
      // If data is empty or assumes defaults
      return UserSettings.fromJson(data);
    } catch (_) {
      // Fallback
      final userId = _authService.currentUser?.id ?? '';
      return UserSettings(userId: userId, defaultPostTtl: null);
    }
  }

  Future<UserSettings> updateUserSettings(UserSettings settings) async {
    final data = await _callGoApi(
      '/settings/user',
      method: 'PATCH',
      body: settings.toJson(),
    );
    return UserSettings.fromJson(data);
  }

  // =========================================================================
  // Posts & Feed
  // =========================================================================

  Future<List<Post>> getProfilePosts({
    required String authorId,
    int limit = 20,
    int offset = 0,
    bool onlyChains = false,
  }) async {
    final data = await _callGoApi(
      '/users/$authorId/posts',
      method: 'GET',
      queryParams: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (onlyChains) 'chained': 'true',
      },
    );

    final posts = data['posts'];
    if (posts is List) {
      return posts
          .whereType<Map<String, dynamic>>()
          .map((json) => Post.fromJson(json))
          .toList();
    }
    return [];
  }

  Future<Post> getPostById(String postId) async {
    final data = await _callGoApi(
      '/posts/$postId',
      method: 'GET',
    );

    return Post.fromJson(data['post']);
  }

  Future<List<Post>> getAppreciatedPosts({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _callGoApi(
      '/users/me/liked',
      method: 'GET',
      queryParams: {'limit': '$limit', 'offset': '$offset'},
    );
    final posts = data['posts'] as List? ?? [];
    return posts.map((p) => Post.fromJson(p)).toList();
  }

  Future<List<Post>> getSavedPosts({
    required String userId,
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _callGoApi(
      '/users/$userId/saved',
      method: 'GET',
      queryParams: {'limit': '$limit', 'offset': '$offset'},
    );
    final posts = data['posts'] as List? ?? [];
    return posts.map((p) => Post.fromJson(p)).toList();
  }

  Future<List<Post>> getChainedPostsForAuthor({
    required String authorId,
    int limit = 20,
    int offset = 0,
  }) async {
    return getProfilePosts(
      authorId: authorId,
      limit: limit,
      offset: offset,
      onlyChains: true,
    );
  }

  Future<List<Post>> getChainPosts({
    required String parentPostId,
    int limit = 50,
  }) async {
    final data = await _callGoApi(
      '/posts/$parentPostId/chain',
      method: 'GET',
    );
    final posts = data['posts'] as List? ?? [];
    return posts.map((p) => Post.fromJson(p)).toList();
  }

  /// Get complete conversation thread with parent-child relationships
  /// Used for threaded conversations (Reddit-style)
  Future<List<Post>> getPostChain(String rootPostId) async {
    final data = await _callGoApi(
      '/posts/$rootPostId/thread',
      method: 'GET',
    );
    final posts = data['posts'] as List? ?? [];
    return posts.map((p) => Post.fromJson(p)).toList();
  }

  /// Get Focus-Context data for the new interactive block system
  /// Returns: Target Post, Direct Parent (if any), and Direct Children (1st layer only)
  Future<FocusContext> getPostFocusContext(String postId) async {
    final data = await _callGoApi(
      '/posts/$postId/focus-context',
      method: 'GET',
    );
    return FocusContext.fromJson(data);
  }

  // =========================================================================
  // Publishing - Unified Post/Beacon Flow
  // =========================================================================

  Future<Post> publishPost({
    String? categoryId,
    required String body,
    String bodyFormat = 'plain',
    bool allowChain = true,
    String? chainParentId,
    String? imageUrl,
    String? videoUrl,
    String? thumbnailUrl,
    int? durationMs,
    int? ttlHours,
    bool isBeacon = false,
    BeaconType? beaconType,
    double? lat,
    double? long,
    String? severity,
    bool userWarned = false,
    bool isNsfw = false,
    String? nsfwReason,
    String? visibility,
    String? overlayJson,
    String? audioOverlayUrl,
  }) async {
    // Validate and sanitize inputs
    if (body.isEmpty) {
      throw ArgumentError('Post body cannot be empty');
    }
    
    final sanitizedBody = SecurityUtils.limitText(SecurityUtils.sanitizeText(body), maxLength: 5000);
    final sanitizedImageUrl = imageUrl != null ? SecurityUtils.sanitizeUrl(imageUrl) : null;
    final sanitizedVideoUrl = videoUrl != null ? SecurityUtils.sanitizeUrl(videoUrl) : null;
    final sanitizedThumbnailUrl = thumbnailUrl != null ? SecurityUtils.sanitizeUrl(thumbnailUrl) : null;
    
    // Validate coordinates for beacons
    if (isBeacon && (lat == null || long == null)) {
      throw ArgumentError('Beacon posts require latitude and longitude');
    }
    
    if (lat != null && (lat < -90 || lat > 90)) {
      throw ArgumentError('Invalid latitude range');
    }
    
    if (long != null && (long < -180 || long > 180)) {
      throw ArgumentError('Invalid longitude range');
    }

    if (kDebugMode) {
    }

    final data = await _callGoApi(

      '/posts',
      method: 'POST',
      body: {
        if (categoryId != null) 'category_id': categoryId,
        'body': sanitizedBody,
        'body_format': bodyFormat,
        'allow_chain': allowChain,
        if (chainParentId != null) 'chain_parent_id': chainParentId,
        if (sanitizedImageUrl != null || (imageUrl != null && imageUrl.isNotEmpty)) 
          'image_url': sanitizedImageUrl ?? imageUrl,
        if (sanitizedVideoUrl != null || (videoUrl != null && videoUrl.isNotEmpty)) 
          'video_url': sanitizedVideoUrl ?? videoUrl,
        if (sanitizedThumbnailUrl != null || (thumbnailUrl != null && thumbnailUrl.isNotEmpty)) 
          'thumbnail_url': sanitizedThumbnailUrl ?? thumbnailUrl,

        if (durationMs != null) 'duration_ms': durationMs,
        if (ttlHours != null) 'ttl_hours': ttlHours,
        if (isBeacon) 'is_beacon': true,
        if (beaconType != null) 'beacon_type': beaconType.value,
        if (lat != null) 'beacon_lat': lat,
        if (long != null) 'beacon_long': long,
        if (severity != null) 'severity': severity,
        if (userWarned) 'user_warned': true,
        if (isNsfw) 'is_nsfw': true,
        if (nsfwReason != null) 'nsfw_reason': nsfwReason,
        if (visibility != null) 'visibility': visibility,
        if (overlayJson != null) 'overlay_json': overlayJson,
        if (audioOverlayUrl != null) 'audio_overlay_url': audioOverlayUrl,
      },
      requireSignature: true,
    );

    return Post.fromJson(data['post']);
  }

  Future<Comment> publishComment({
    required String postId,
    required String body,
  }) async {
    // Backward-compatible: create a chained post so threads render immediately.
    final post = await publishPost(
      body: body,
      chainParentId: postId,
      allowChain: true,
    );

    return Comment(
      id: post.id,
      postId: postId,
      authorId: post.authorId,
      body: post.body,
      status: CommentStatus.active,
      createdAt: post.createdAt,
      updatedAt: post.editedAt,
      author: post.author,
      voteCount: null,
    );
  }

  Future<void> editPost({
    required String postId,
    required String content,
  }) async {
    // Validate and sanitize input
    if (content.isEmpty) {
      throw ArgumentError('Content cannot be empty');
    }
    
    final sanitizedContent = SecurityUtils.limitText(SecurityUtils.sanitizeText(content), maxLength: 5000);
    
    await _callGoApi(
      '/posts/$postId',
      method: 'PATCH',
      body: {'body': sanitizedContent},
    );
  }

  Future<void> deletePost(String postId) async {
    await _callGoApi(
      '/posts/$postId',
      method: 'DELETE',
    );
  }

  Future<void> updatePostVisibility({
    required String postId,
    required String visibility,
  }) async {
    await _callGoApi(
      '/posts/$postId/visibility',
      method: 'PATCH',
      body: {'visibility': visibility},
    );
  }

  Future<void> updateAllPostVisibility(String visibility) async {
    // Legacy function proxy for bulk update
    await _callFunction(
      'manage-post',
      method: 'POST',
      body: {
        'action': 'bulk_update_privacy',
        'visibility': visibility,
      },
    );
  }

  Future<void> pinPost(String postId) async {
    await _callGoApi(
      '/posts/$postId/pin',
      method: 'POST',
      body: {'pinned': true},
    );
  }

  Future<void> unpinPost(String postId) async {
    await _callGoApi(
      '/posts/$postId/pin',
      method: 'POST',
      body: {'pinned': false}, // Assuming logic handles boolean toggles
    );
  }

  // =========================================================================
  // Beacons
  // =========================================================================

  /// Stateless content moderation check — sends plaintext to server AI,
  /// returns pass/fail. Server does NOT store the content.
  /// Returns null if allowed, or a reason string if blocked.
  Future<String?> moderateContent({String? text, String? imageUrl, String? context}) async {
    try {
      final data = await _callGoApi(
        '/moderate',
        method: 'POST',
        body: {
          if (text != null) 'text': text,
          if (imageUrl != null) 'image_url': imageUrl,
          if (context != null) 'context': context,
        },
      );
      final allowed = data['allowed'] as bool? ?? true;
      if (!allowed) {
        return data['reason'] as String? ?? 'Content policy violation';
      }
      return null; // Allowed
    } catch (e) {
      // If moderation endpoint fails, allow the message through
      // (fail-open to avoid blocking all messages on server issues)
      return null;
    }
  }

  /// Create an anonymous beacon pin on the map.
  /// Author identity is stripped — server stores it only for abuse tracking.
  Future<Post> createBeacon({
    required String body,
    required String beaconType,
    required double lat,
    required double long,
    String severity = 'medium',
    String? imageUrl,
    int? ttlHours,
  }) async {
    final data = await _callGoApi(
      '/beacons',
      method: 'POST',
      body: {
        'body': body,
        'beacon_type': beaconType,
        'lat': lat,
        'long': long,
        'severity': severity,
        if (imageUrl != null) 'image_url': imageUrl,
        if (ttlHours != null) 'ttl_hours': ttlHours,
      },
      requireSignature: true,
    );
    return Post.fromJson(data['beacon']);
  }

  Future<List<Post>> fetchNearbyBeacons({
    required double lat,
    required double long,
    int radius = 16000,
  }) async {
    try {
      final data = await _callGoApi(
        '/beacons/nearby',
        method: 'GET',
        queryParams: {
          'lat': lat.toString(),
          'long': long.toString(),
          'radius': radius.toString(),
        },
      );
      return (data['beacons'] as List)
          .map((json) => Post.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }


  Future<List<Post>> fetchOfficialAlerts({
    required double lat,
    required double long,
    int radius = 16000,
  }) async {
    try {
      final data = await _callGoApi(
        '/beacons/official',
        method: 'GET',
        queryParams: {
          'lat': lat.toString(),
          'long': long.toString(),
          'radius': radius.toString(),
        },
      );
      return (data['beacons'] as List)
          .map((json) => Post.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // =========================================================================
  // Beacon Ecosystem Search (beacons, board, public groups — never private)
  // =========================================================================

  Future<Map<String, dynamic>> beaconSearch({
    required String query,
    double? lat,
    double? lng,
    int? radius,
    String type = 'all',
    int limit = 20,
  }) async {
    var path = '/beacon/search?q=${Uri.encodeComponent(query)}&type=$type&limit=$limit';
    if (lat != null && lng != null) path += '&lat=$lat&long=$lng';
    if (radius != null) path += '&radius=$radius';
    return await _callGoApi(path, method: 'GET');
  }

  // =========================================================================
  // Neighborhood Board (standalone — NOT posts)
  // =========================================================================

  Future<Map<String, dynamic>> fetchBoardEntries({
    required double lat,
    required double long,
    int radius = 5000,
    String? topic,
    String sort = 'new',
  }) async {
    var path = '/board/nearby?lat=$lat&long=$long&radius=$radius&sort=$sort';
    if (topic != null && topic.isNotEmpty) path += '&topic=$topic';
    return await _callGoApi(path, method: 'GET');
  }

  Future<Map<String, dynamic>> createBoardEntry({
    required String body,
    String? imageUrl,
    required String topic,
    required double lat,
    required double long,
  }) async {
    return await _callGoApi('/board', body: {
      'body': body,
      if (imageUrl != null) 'image_url': imageUrl,
      'topic': topic,
      'lat': lat,
      'long': long,
    });
  }

  Future<Map<String, dynamic>> getBoardEntry(String entryId) async {
    return await _callGoApi('/board/$entryId', method: 'GET');
  }

  Future<Map<String, dynamic>> createBoardReply({
    required String entryId,
    required String body,
  }) async {
    return await _callGoApi('/board/$entryId/replies', body: {
      'body': body,
    });
  }

  Future<Map<String, dynamic>> toggleBoardVote({
    String? entryId,
    String? replyId,
  }) async {
    return await _callGoApi('/board/vote', body: {
      if (entryId != null) 'entry_id': entryId,
      if (replyId != null) 'reply_id': replyId,
    });
  }

  Future<void> removeBoardEntry(String id, String reason) async {
    await _callGoApi('/board/$id/remove', method: 'POST', body: {'reason': reason});
  }

  Future<void> flagBoardEntry(String id, String reason, {String? replyId}) async {
    await _callGoApi('/board/$id/flag', method: 'POST', body: {
      'reason': reason,
      if (replyId != null) 'reply_id': replyId,
    });
  }

  // Neighborhoods
  // =========================================================================

  Future<Map<String, dynamic>> detectNeighborhood({
    required double lat,
    required double long,
  }) async {
    return await _callGoApi('/neighborhoods/detect?lat=$lat&long=$long', method: 'GET');
  }

  Future<Map<String, dynamic>?> getCurrentNeighborhood() async {
    try {
      return await _callGoApi('/neighborhoods/current', method: 'GET');
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchNeighborhoodsByZip(String zip) async {
    final data = await _callGoApi('/neighborhoods/search?zip=$zip', method: 'GET');
    final list = data['neighborhoods'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> chooseNeighborhood(String neighborhoodId) async {
    return await _callGoApi('/neighborhoods/choose', method: 'POST', body: {
      'neighborhood_id': neighborhoodId,
    });
  }

  Future<Map<String, dynamic>?> getMyNeighborhood() async {
    try {
      return await _callGoApi('/neighborhoods/mine', method: 'GET');
    } catch (_) {
      return null;
    }
  }

  // Groups & Clusters
  // =========================================================================

  Future<List<Map<String, dynamic>>> fetchMyGroups() async {
    final data = await _callGoApi('/capsules/mine', method: 'GET');
    return (data['groups'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<List<Map<String, dynamic>>> discoverGroups({String? category, int limit = 50}) async {
    final params = <String, String>{'limit': '$limit'};
    if (category != null && category != 'all') params['category'] = category;
    final data = await _callGoApi('/capsules/discover', method: 'GET', queryParams: params);
    return (data['groups'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  
  Future<Map<String, dynamic>> createCapsule({
    required String name,
    String description = '',
    required String publicKey,
    required String encryptedGroupKey,
    String? settings,
  }) async {
    return await _callGoApi('/capsules', body: {
      'name': name,
      'description': description,
      'public_key': publicKey,
      'encrypted_group_key': encryptedGroupKey,
      if (settings != null) 'settings': settings,
    });
  }

  // Group Features (posts, chat, forum, members)
  // =========================================================================

  Future<List<Map<String, dynamic>>> fetchGroupPosts(String groupId, {int limit = 20, int offset = 0}) async {
    final data = await _callGoApi('/capsules/$groupId/posts', method: 'GET',
        queryParams: {'limit': '$limit', 'offset': '$offset'});
    return (data['posts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> createGroupPost(String groupId, {required String body, String? imageUrl}) async {
    return await _callGoApi('/capsules/$groupId/posts', body: {
      'body': body,
      if (imageUrl != null) 'image_url': imageUrl,
    });
  }

  Future<Map<String, dynamic>> toggleGroupPostLike(String groupId, String postId) async {
    return await _callGoApi('/capsules/$groupId/posts/$postId/like', method: 'POST');
  }

  Future<List<Map<String, dynamic>>> fetchGroupPostComments(String groupId, String postId) async {
    final data = await _callGoApi('/capsules/$groupId/posts/$postId/comments', method: 'GET');
    return (data['comments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> createGroupPostComment(String groupId, String postId, {required String body}) async {
    return await _callGoApi('/capsules/$groupId/posts/$postId/comments', body: {'body': body});
  }

  Future<List<Map<String, dynamic>>> fetchGroupMessages(String groupId, {int limit = 50, int offset = 0}) async {
    final data = await _callGoApi('/capsules/$groupId/messages', method: 'GET',
        queryParams: {'limit': '$limit', 'offset': '$offset'});
    return (data['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> sendGroupMessage(String groupId, {required String body}) async {
    return await _callGoApi('/capsules/$groupId/messages', body: {'body': body});
  }

  Future<List<Map<String, dynamic>>> fetchGroupThreads(String groupId, {int limit = 30, int offset = 0}) async {
    final data = await _callGoApi('/capsules/$groupId/threads', method: 'GET',
        queryParams: {'limit': '$limit', 'offset': '$offset'});
    return (data['threads'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> createGroupThread(String groupId, {required String title, String body = ''}) async {
    return await _callGoApi('/capsules/$groupId/threads', body: {'title': title, 'body': body});
  }

  Future<Map<String, dynamic>> fetchGroupThread(String groupId, String threadId) async {
    return await _callGoApi('/capsules/$groupId/threads/$threadId', method: 'GET');
  }

  Future<Map<String, dynamic>> createGroupThreadReply(String groupId, String threadId, {required String body}) async {
    return await _callGoApi('/capsules/$groupId/threads/$threadId/replies', body: {'body': body});
  }

  Future<List<Map<String, dynamic>>> fetchGroupMembers(String groupId) async {
    final data = await _callGoApi('/capsules/$groupId/members', method: 'GET');
    return (data['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<void> removeGroupMember(String groupId, String memberId) async {
    await _callGoApi('/capsules/$groupId/members/$memberId', method: 'DELETE');
  }

  Future<void> updateMemberRole(String groupId, String memberId, {required String role}) async {
    await _callGoApi('/capsules/$groupId/members/$memberId', method: 'PATCH', body: {'role': role});
  }

  
  Future<void> updateGroup(String groupId, {String? name, String? description, String? settings}) async {
    await _callGoApi('/capsules/$groupId', method: 'PATCH', body: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (settings != null) 'settings': settings,
    });
  }

  Future<void> deleteGroup(String groupId) async {
    await _callGoApi('/capsules/$groupId', method: 'DELETE');
  }

  Future<void> inviteToGroup(String groupId, {required String userId}) async {
    await _callGoApi('/capsules/$groupId/invite-member', body: {'user_id': userId});
  }

  Future<List<Map<String, dynamic>>> searchUsersForInvite(String groupId, String query) async {
    final data = await _callGoApi('/capsules/$groupId/search-users', method: 'GET',
        queryParams: {'q': query});
    return (data['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  // =========================================================================
  // Social Actions
  // =========================================================================

  Future<List<FollowRequest>> getFollowRequests() async {
    final data = await _callGoApi('/users/requests');
    final requests = data['requests'] as List<dynamic>? ?? [];
    return requests.map((e) => FollowRequest.fromJson(e)).toList();
  }

  Future<void> acceptFollowRequest(String requesterId) async {
    await _callGoApi(
      '/users/$requesterId/accept',
      method: 'POST',
    );
  }

  Future<void> rejectFollowRequest(String requesterId) async {
    await _callGoApi(
      '/users/$requesterId/reject',
      method: 'DELETE',
    );
  }

  Future<void> blockUser(String userId) async {
    await _callGoApi(
      '/users/$userId/block',
      method: 'POST',
    );
  }

  Future<void> unblockUser(String userId) async {
    await _callGoApi(
      '/users/$userId/block',
      method: 'DELETE',
    );
  }

  Future<void> hidePost(String postId) async {
    await _callGoApi('/posts/$postId/hide', method: 'POST');
  }

  Future<void> appreciatePost(String postId) async {
    await _callGoApi(
      '/posts/$postId/like',
      method: 'POST',
    );
  }

  Future<void> unappreciatePost(String postId) async {
    await _callGoApi(
      '/posts/$postId/like',
      method: 'DELETE',
    );
  }

  // =========================================================================
  // Chat
  // =========================================================================

  Future<List<dynamic>> getConversations() async {
    try {
      final data = await _callGoApi('/conversations', method: 'GET');
      return data['conversations'] as List? ?? [];
    } catch (e) {
      // Fallback or empty if API not yet ready
      return [];
    }
  }

  Future<Map<String, dynamic>> getConversationById(
      String conversationId) async {
    return {};
  }

  Future<String> getOrCreateConversation(String otherUserId) async {
    final data = await _callGoApi('/conversation',
        method: 'GET', queryParams: {'other_user_id': otherUserId});
    return data['conversation_id'] as String;
  }

  Future<Map<String, dynamic>> sendEncryptedMessage({
    required String conversationId,
    required String ciphertext, // Go expects string (base64)
    String? receiverId,
    String? iv,
    String? keyVersion,
    String? messageHeader,
    int messageType = 1,
  }) async {
    final data = await _callGoApi('/messages', method: 'POST', body: {
      'conversation_id': conversationId,
      if (receiverId != null) 'receiver_id': receiverId,
      'ciphertext': ciphertext,
      if (iv != null) 'iv': iv,
      if (keyVersion != null) 'key_version': keyVersion,
      if (messageHeader != null) 'message_header': messageHeader,
      'message_type': messageType
    });
    return data;
  }

  Future<List<dynamic>> getConversationMessages(String conversationId,
      {int limit = 50, int offset = 0}) async {
    final data = await _callGoApi('/conversations/$conversationId/messages',
        method: 'GET', queryParams: {'limit': '$limit', 'offset': '$offset'});
    return data['messages'] as List? ?? [];
  }

  Future<List<dynamic>> getMutualFollows() async {
    final data = await _callGoApi('/mutual-follows', method: 'GET');
    return data['profiles'] as List? ?? [];
  }

  Future<bool> deleteConversation(String conversationId) async {
    try {
      await _callGoApi('/conversations/$conversationId', method: 'DELETE');
      return true;
    } catch (e) {
      if (kDebugMode) print('[API] Failed to delete conversation: $e');
      return false;
    }
  }

  Future<bool> deleteMessage(String messageId) async {
    try {
      await _callGoApi('/messages/$messageId', method: 'DELETE');
      return true;
    } catch (e) {
      if (kDebugMode) print('[API] Failed to delete message: $e');
      return false;
    }
  }

  // =========================================================================
  // E2EE / Keys (Missing Methods)
  // =========================================================================

  Future<Map<String, dynamic>> getKeyBundle(String userId) async {
    final data = await callGoApi('/keys/$userId', method: 'GET');
    // Key bundle fetched - contents not logged for security
    // Go returns nested structure. We normalize to flat keys here.
    if (data.containsKey('identity_key') && data['identity_key'] is Map) {
      final identityKey = data['identity_key'] as Map<String, dynamic>;
      final signedPrekey = data['signed_prekey'] as Map<String, dynamic>?;
      final oneTimePrekey = data['one_time_prekey'] as Map<String, dynamic>?;
      
      return {
        'identity_key_public': identityKey['public_key'],
        'signed_prekey_public': signedPrekey?['public_key'],
        'signed_prekey_id': signedPrekey?['key_id'],
        'signed_prekey_signature': signedPrekey?['signature'],
        'registration_id': identityKey['key_id'],
        'one_time_prekey': oneTimePrekey?['public_key'],
        'one_time_prekey_id': oneTimePrekey?['key_id'],
      };
    }
    return data;
  }

  Future<void> publishKeys({
    required String identityKeyPublic,
    required int registrationId,
    String? preKey,
    String? signedPrekeyPublic,
    int? signedPrekeyId,
    String? signedPrekeySignature,
    List<dynamic>? oneTimePrekeys,
    String? identityKey,
    String? signature,
    String? signedPreKey,
  }) async {
    final actualIdentityKey = identityKey ?? identityKeyPublic;
    final actualSignature = signature ?? signedPrekeySignature ?? '';
    final actualSignedPreKey = signedPreKey ?? signedPrekeyPublic ?? '';

    await callGoApi('/keys', method: 'POST', body: {
      'identity_key_public': actualIdentityKey,
      'signed_prekey_public': actualSignedPreKey,
      'signed_prekey_id': signedPrekeyId ?? 1,
      'signed_prekey_signature': actualSignature,
      'one_time_prekeys': oneTimePrekeys ?? [],
      'registration_id': registrationId,
    });
  }

  // =========================================================================
  // Media / Search / Analysis (Missing Methods)
  // =========================================================================

  Future<String> getSignedMediaUrl(String path) async {
    if (path.startsWith('http')) return path;
    try {
      final data = await callGoApi('/media/sign', method: 'GET', queryParams: {'path': path});
      return data['url'] as String? ?? path;
    } catch (_) {
      return path;
    }
  }

  Future<Map<String, dynamic>> toggleReaction(String postId, String emoji) async {
    final data = await callGoApi(
      '/posts/$postId/reactions/toggle',
      method: 'POST',
      body: {'emoji': emoji},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  Future<SearchResults> search(String query) async {
    // Validate and sanitize search query
    if (query.isEmpty) {
      return SearchResults(users: [], tags: [], posts: []);
    }
    
    final sanitizedQuery = SecurityUtils.limitText(SecurityUtils.sanitizeText(query), maxLength: 100);
    
    if (!SecurityUtils.isValidInput(sanitizedQuery)) {
      if (kDebugMode) print('[API] Invalid search query input: $query');
      return SearchResults(users: [], tags: [], posts: []);
    }
    
    try {
      if (kDebugMode) print('[API] Searching for: $sanitizedQuery');
      final data = await callGoApi(
        '/search',
        method: 'GET',
        queryParams: {'q': sanitizedQuery},
      );
      // if (kDebugMode) print('[API] Search raw response: ${jsonEncode(data)}');
      return SearchResults.fromJson(data);
    } catch (e, stack) {
      if (kDebugMode) {
      }
      // Return empty results on error
      return SearchResults(users: [], tags: [], posts: []);
    }
  }

  Future<ToneCheckResult> checkTone(String text, {String? imageUrl}) async {
    // Validate and sanitize inputs
    if (text.isEmpty) {
      return ToneCheckResult(
          flagged: false,
          category: null,
          flags: [],
          reason: 'Empty text provided');
    }
    
    final sanitizedText = SecurityUtils.limitText(SecurityUtils.sanitizeText(text), maxLength: 2000);
    final sanitizedImageUrl = imageUrl != null ? SecurityUtils.sanitizeUrl(imageUrl) : null;
    
    // Check for XSS in text
    if (SecurityUtils.containsXSS(sanitizedText)) {
      return ToneCheckResult(
          flagged: true,
          category: ModerationCategory.nsfw,
          flags: ['xss_detected'],
          reason: 'Potentially dangerous content detected');
    }
    
    try {
      final data = await callGoApi(
        '/analysis/tone',
        method: 'POST',
        body: {
          'text': sanitizedText,
          if (sanitizedImageUrl != null) 'image_url': sanitizedImageUrl,
        },
      );
      return ToneCheckResult.fromJson(data);
    } catch (_) {
      // Fallback: allow if analysis fails
      return ToneCheckResult(
          flagged: false,
          category: null,
          flags: [],
          reason: 'Analysis unavailable');
    }
  }

  // =========================================================================
  // Notifications & Feed (Missing Methods)
  // =========================================================================

  Future<List<Post>> getPersonalFeed({
    int limit = 20,
    int offset = 0,
    String? filterType,
  }) async {
    final queryParams = {
      'limit': '$limit',
      'offset': '$offset',
    };
    if (filterType != null) {
      queryParams['type'] = filterType;
    }
    
    final data = await _callGoApi(
      '/feed/personal',
      method: 'GET',
      queryParams: queryParams,
    );
    if (data['posts'] != null) {
      return (data['posts'] as List)
          .map((json) => Post.fromJson(json))
          .toList();
    }
    return [];
  }

  Future<List<Post>> getSojornFeed({int limit = 20, int offset = 0}) async {
    return getPersonalFeed(limit: limit, offset: offset);
  }

  Future<List<AppNotification>> getNotifications({
    int limit = 20,
    int offset = 0,
    bool includeArchived = false,
  }) async {
    final data = await callGoApi(
      '/notifications',
      method: 'GET',
      queryParams: {
        'limit': '$limit',
        'offset': '$offset',
        'include_archived': '$includeArchived',
      },
    );
    final list = data['notifications'] as List? ?? [];
    return list
        .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  Future<void> markNotificationsAsRead(List<String> ids) async {
    await callGoApi(
      '/notifications/read',
      method: 'POST',
      body: {'ids': ids},
    );
  }

  Future<void> archiveNotifications(List<String> ids) async {
    await callGoApi(
      '/notifications/archive',
      method: 'POST',
      body: {'ids': ids},
    );
  }

  Future<void> archiveAllNotifications() async {
    await callGoApi(
      '/notifications/archive-all',
      method: 'POST',
    );
  }

  // =========================================================================
  // Post Actions (Missing Methods)
  // =========================================================================

  Future<void> savePost(String postId) async {
    await callGoApi(
      '/posts/$postId/save',
      method: 'POST',
    );
  }

  Future<void> unsavePost(String postId) async {
    await callGoApi(
      '/posts/$postId/save',
      method: 'DELETE',
    );
  }

  // =========================================================================
  // Beacon Actions
  // =========================================================================

  Future<void> vouchBeacon(String beaconId) async {
    await callGoApi(
      '/beacons/$beaconId/vouch',
      method: 'POST',
    );
  }

  Future<void> reportBeacon(String beaconId) async {
    await callGoApi(
      '/beacons/$beaconId/report',
      method: 'POST',
    );
  }

  Future<void> removeBeaconVote(String beaconId) async {
    await callGoApi(
      '/beacons/$beaconId/vouch',
      method: 'DELETE',
    );
  }

  // =========================================================================
  // Key Backup & Recovery
  // =========================================================================

  /// Upload an encrypted backup blob to cloud storage
  /// [encryptedBlob] - The base64 encoded encrypted backup data
  /// [salt] - The base64 encoded salt used for key derivation
  /// [nonce] - The base64 encoded nonce used for encryption
  /// [mac] - The base64 encoded auth tag
  Future<Map<String, dynamic>> uploadBackup({
    required String encryptedBlob,
    required String salt,
    required String nonce,
    required String mac,
    required String deviceName,
    int version = 1,
  }) async {
    return await _callGoApi(
      '/backup/upload',
      method: 'POST',
      body: {
        'encrypted_blob': encryptedBlob,
        'salt': salt,
        'nonce': nonce,
        'mac': mac,
        'device_name': deviceName,
        'version': version,
      },
    );
  }

  /// Download the latest backup from cloud storage
  Future<Map<String, dynamic>?> downloadBackup([String? backupId]) async {
    try {
      final path = backupId != null ? '/backup/download/$backupId' : '/backup/download';
      final data = await _callGoApi(path, method: 'GET');
      return data;
    } catch (e) {
      if (e.toString().contains('404')) {
        return null;
      }
      rethrow;
    }
  }

  /// List all backups
  Future<List<Map<String, dynamic>>> listBackups() async {
    final data = await _callGoApi('/backup/list', method: 'GET');
    return (data['backups'] as List).cast<Map<String, dynamic>>();
  }
  
  /// Delete a backup
  Future<void> deleteBackup(String backupId) async {
    await _callGoApi('/backup/$backupId', method: 'DELETE');
  }

  /// Get sync code for device pairing
  Future<Map<String, dynamic>> generateSyncCode({
    required String deviceName,
    required String deviceFingerprint,
  }) async {
    return await _callGoApi(
      '/backup/sync/generate-code',
      method: 'POST',
      body: {
        'device_name': deviceName,
        'device_fingerprint': deviceFingerprint,
      },
    );
  }

  /// Verify sync code
  Future<Map<String, dynamic>> verifySyncCode({
    required String code,
    required String deviceName,
    required String deviceFingerprint,
  }) async {
    return await _callGoApi(
      '/backup/sync/verify-code',
      method: 'POST',
      body: {
        'code': code,
        'device_name': deviceName,
        'device_fingerprint': deviceFingerprint,
      },
    );
  }

  // Follow System
  // =========================================================================

  /// Follow a user
  Future<void> followUser(String targetUserId) async {
    await _callGoApi('/users/$targetUserId/follow', method: 'POST');
  }

  /// Unfollow a user
  Future<void> unfollowUser(String targetUserId) async {
    await _callGoApi('/users/$targetUserId/unfollow', method: 'POST');
  }

  /// Check if current user follows target user
  Future<bool> isFollowing(String targetUserId) async {
    final data = await _callGoApi('/users/$targetUserId/is-following', method: 'GET');
    return data['is_following'] as bool? ?? false;
  }

  /// Get mutual followers between current user and target user
  Future<List<Map<String, dynamic>>> getMutualFollowers(String targetUserId) async {
    final data = await _callGoApi('/users/$targetUserId/mutual-followers', method: 'GET');
    return (data['mutual_followers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Get suggested users to follow
  Future<List<Map<String, dynamic>>> getSuggestedUsers({int limit = 10}) async {
    final data = await _callGoApi('/users/suggested', method: 'GET', queryParams: {'limit': '$limit'});
    return (data['suggestions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Get list of followers for a user
  Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    final data = await _callGoApi('/users/$userId/followers', method: 'GET');
    return (data['followers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  /// Get list of users that a user follows
  Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    final data = await _callGoApi('/users/$userId/following', method: 'GET');
    return (data['following'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  // Groups System
  // =========================================================================

  /// List all groups with optional category filter
  Future<List<Group>> listGroups({String? category, int page = 0, int limit = 20}) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (category != null) {
      queryParams['category'] = category;
    }

    final data = await _callGoApi('/groups', method: 'GET', queryParams: queryParams);
    final groups = (data['groups'] as List?) ?? [];
    return groups.map((g) => Group.fromJson(g)).toList();
  }

  /// Get groups the user is a member of
  Future<List<Group>> getMyGroups() async {
    final data = await _callGoApi('/groups/mine', method: 'GET');
    final groups = (data['groups'] as List?) ?? [];
    return groups.map((g) => Group.fromJson(g)).toList();
  }

  /// Get suggested groups for the user
  Future<List<SuggestedGroup>> getSuggestedGroups({int limit = 10}) async {
    final data = await _callGoApi('/groups/suggested', method: 'GET', 
      queryParams: {'limit': limit.toString()});
    final suggestions = (data['suggestions'] as List?) ?? [];
    return suggestions.map((s) => SuggestedGroup.fromJson(s)).toList();
  }

  /// Get group details by ID
  Future<Group> getGroup(String groupId) async {
    final data = await _callGoApi('/groups/$groupId', method: 'GET');
    return Group.fromJson(data['group']);
  }

  /// Create a new group
  Future<Map<String, dynamic>> createGroup({
    required String name,
    String? description,
    required GroupCategory category,
    bool isPrivate = false,
    String? avatarUrl,
    String? bannerUrl,
  }) async {
    final body = {
      'name': name,
      'description': description ?? '',
      'category': category.value,
      'is_private': isPrivate,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (bannerUrl != null) 'banner_url': bannerUrl,
    };

    return await _callGoApi('/groups', method: 'POST', body: body);
  }

  /// Join a group or request to join (for private groups)
  Future<Map<String, dynamic>> joinGroup(String groupId, {String? message}) async {
    final body = <String, dynamic>{};
    if (message != null) {
      body['message'] = message;
    }

    return await _callGoApi('/groups/$groupId/join', method: 'POST', body: body);
  }

  /// Leave a group
  Future<void> leaveGroup(String groupId) async {
    await _callGoApi('/groups/$groupId/leave', method: 'POST');
  }

  /// Get group members
  Future<List<GroupMember>> getGroupMembers(String groupId, {int page = 0, int limit = 50}) async {
    final data = await _callGoApi('/groups/$groupId/members', method: 'GET',
      queryParams: {'page': page.toString(), 'limit': limit.toString()});
    final members = (data['members'] as List?) ?? [];
    return members.map((m) => GroupMember.fromJson(m)).toList();
  }

  /// Get pending join requests (admin only)
  Future<List<JoinRequest>> getPendingRequests(String groupId) async {
    final data = await _callGoApi('/groups/$groupId/requests', method: 'GET');
    final requests = (data['requests'] as List?) ?? [];
    return requests.map((r) => JoinRequest.fromJson(r)).toList();
  }

  /// Approve a join request (admin only)
  Future<void> approveJoinRequest(String groupId, String requestId) async {
    await _callGoApi('/groups/$groupId/requests/$requestId/approve', method: 'POST');
  }

  /// Reject a join request (admin only)
  Future<void> rejectJoinRequest(String groupId, String requestId) async {
    await _callGoApi('/groups/$groupId/requests/$requestId/reject', method: 'POST');
  }
}
