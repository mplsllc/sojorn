// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/firebase_web_config.dart';
import '../theme/tokens.dart';
import '../routes/app_routes.dart';
import '../services/secure_chat_service.dart';
import '../theme/app_theme.dart';
import 'api_service.dart';

/// NotificationPreferences model
class NotificationPreferences {
  final bool pushEnabled;
  final bool pushLikes;
  final bool pushComments;
  final bool pushReplies;
  final bool pushMentions;
  final bool pushFollows;
  final bool pushFollowRequests;
  final bool pushMessages;
  final bool pushSaves;
  final bool pushBeacons;
  final bool emailEnabled;
  final String emailDigestFrequency;
  final bool quietHoursEnabled;
  final String? quietHoursStart;
  final String? quietHoursEnd;
  final bool showBadgeCount;

  NotificationPreferences({
    this.pushEnabled = true,
    this.pushLikes = true,
    this.pushComments = true,
    this.pushReplies = true,
    this.pushMentions = true,
    this.pushFollows = true,
    this.pushFollowRequests = true,
    this.pushMessages = true,
    this.pushSaves = true,
    this.pushBeacons = true,
    this.emailEnabled = false,
    this.emailDigestFrequency = 'never',
    this.quietHoursEnabled = false,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.showBadgeCount = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      pushEnabled: json['push_enabled'] ?? true,
      pushLikes: json['push_likes'] ?? true,
      pushComments: json['push_comments'] ?? true,
      pushReplies: json['push_replies'] ?? true,
      pushMentions: json['push_mentions'] ?? true,
      pushFollows: json['push_follows'] ?? true,
      pushFollowRequests: json['push_follow_requests'] ?? true,
      pushMessages: json['push_messages'] ?? true,
      pushSaves: json['push_saves'] ?? true,
      pushBeacons: json['push_beacons'] ?? true,
      emailEnabled: json['email_enabled'] ?? false,
      emailDigestFrequency: json['email_digest_frequency'] ?? 'never',
      quietHoursEnabled: json['quiet_hours_enabled'] ?? false,
      quietHoursStart: json['quiet_hours_start'],
      quietHoursEnd: json['quiet_hours_end'],
      showBadgeCount: json['show_badge_count'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'push_enabled': pushEnabled,
    'push_likes': pushLikes,
    'push_comments': pushComments,
    'push_replies': pushReplies,
    'push_mentions': pushMentions,
    'push_follows': pushFollows,
    'push_follow_requests': pushFollowRequests,
    'push_messages': pushMessages,
    'push_saves': pushSaves,
    'push_beacons': pushBeacons,
    'email_enabled': emailEnabled,
    'email_digest_frequency': emailDigestFrequency,
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_hours_start': quietHoursStart,
    'quiet_hours_end': quietHoursEnd,
    'show_badge_count': showBadgeCount,
  };

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? pushLikes,
    bool? pushComments,
    bool? pushReplies,
    bool? pushMentions,
    bool? pushFollows,
    bool? pushFollowRequests,
    bool? pushMessages,
    bool? pushSaves,
    bool? pushBeacons,
    bool? emailEnabled,
    String? emailDigestFrequency,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
    bool? showBadgeCount,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      pushLikes: pushLikes ?? this.pushLikes,
      pushComments: pushComments ?? this.pushComments,
      pushReplies: pushReplies ?? this.pushReplies,
      pushMentions: pushMentions ?? this.pushMentions,
      pushFollows: pushFollows ?? this.pushFollows,
      pushFollowRequests: pushFollowRequests ?? this.pushFollowRequests,
      pushMessages: pushMessages ?? this.pushMessages,
      pushSaves: pushSaves ?? this.pushSaves,
      pushBeacons: pushBeacons ?? this.pushBeacons,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      emailDigestFrequency: emailDigestFrequency ?? this.emailDigestFrequency,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      showBadgeCount: showBadgeCount ?? this.showBadgeCount,
    );
  }
}

/// Badge count model
class UnreadBadge {
  final int notificationCount;
  final int messageCount;
  final int totalCount;

  UnreadBadge({
    this.notificationCount = 0,
    this.messageCount = 0,
    this.totalCount = 0,
  });

  factory UnreadBadge.fromJson(Map<String, dynamic> json) {
    return UnreadBadge(
      notificationCount: json['notification_count'] ?? 0,
      messageCount: json['message_count'] ?? 0,
      totalCount: json['total_count'] ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UnreadBadge &&
      other.notificationCount == notificationCount &&
      other.messageCount == messageCount &&
      other.totalCount == totalCount;

  @override
  int get hashCode => Object.hash(notificationCount, messageCount, totalCount);
}

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _initialized = false;
  String? _currentToken;
  String? _cachedVapidKey;

  // Badge count stream for UI updates
  final StreamController<UnreadBadge> _badgeController = StreamController<UnreadBadge>.broadcast();
  Stream<UnreadBadge> get badgeStream => _badgeController.stream;
  UnreadBadge _currentBadge = UnreadBadge();
  UnreadBadge get currentBadge => _currentBadge;

  // Foreground notification stream for in-app banners
  final StreamController<RemoteMessage> _foregroundMessageController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get foregroundMessages => _foregroundMessageController.stream;

  // Global overlay entry for in-app notification banner
  OverlayEntry? _currentBannerOverlay;

  // Active context tracking to suppress notifications for what the user is already seeing
  String? activeConversationId;
  String? activePostId;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Skip FCM entirely on web when Firebase isn't configured (no API key)
    if (kIsWeb && !FirebaseWebConfig.isConfigured) {
      debugPrint('[FCM] Skipped — Firebase not configured for web (missing API key)');
      return;
    }

    try {
      debugPrint('[FCM] Initializing for platform: ${_resolveDeviceType()}');
      
      // Android 13+ requires explicit runtime permission request
      if (!kIsWeb && Platform.isAndroid) {
        final permissionStatus = await _requestAndroidNotificationPermission();
        if (permissionStatus != PermissionStatus.granted) {
          debugPrint('[FCM] Android notification permission not granted: $permissionStatus');
          return;
        }
      }
      
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FCM] Push notification permission denied');
        return;
      }

      final vapidKey = kIsWeb ? await _resolveVapidKey() : null;
      if (kIsWeb && (vapidKey == null || vapidKey.isEmpty)) {
        debugPrint('[FCM] Web push is missing FIREBASE_WEB_VAPID_KEY');
      }

      debugPrint('[FCM] Requesting token...');
      final token = await _messaging.getToken(
        vapidKey: vapidKey,
      );

      if (token != null) {
        _currentToken = token;
        debugPrint('[FCM] Token registered (${_resolveDeviceType()}): ${token.substring(0, 20)}...');
        await _upsertToken(token);
      } else {
        debugPrint('[FCM] WARNING: Token is null after getToken()');
      }

      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('[FCM] Token refreshed');
        _currentToken = newToken;
        _upsertToken(newToken);
      });

      // Handle messages when app is opened from notification
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('[FCM] onMessageOpenedApp triggered: ${msg.notification?.title}');
        _handleMessageOpen(msg);
      });
      
      // Handle foreground messages - show in-app banner
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('[FCM] Foreground message received: ${message.notification?.title}');
        _foregroundMessageController.add(message);
        _refreshBadgeCount();
      });

      // Check for initial message (app opened from terminated state)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[FCM] App opened from TERMINATED state via notification: ${initialMessage.notification?.title}');
        // Delay to allow navigation setup (extended to 1000ms for safety)
        Future.delayed(const Duration(milliseconds: 1000), () {
          _handleMessageOpen(initialMessage);
        });
      }
      
      // Initial badge count fetch
      await _refreshBadgeCount();
      
      debugPrint('[FCM] Initialization complete');
    } catch (e, stackTrace) {
      debugPrint('[FCM] Failed to initialize notifications: $e');
      debugPrint('[FCM] Stack trace: $stackTrace');
    }
  }

  /// Request POST_NOTIFICATIONS permission for Android 13+ (API 33+)
  Future<PermissionStatus> _requestAndroidNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      debugPrint('[FCM] Current Android permission status: $status');
      
      if (status.isDenied || status.isRestricted) {
        final result = await Permission.notification.request();
        debugPrint('[FCM] Android permission request result: $result');
        return result;
      }
      
      return status;
    } catch (e) {
      debugPrint('[FCM] Error requesting Android notification permission: $e');
      return PermissionStatus.granted;
    }
  }

  /// Remove the current device's FCM token (call on logout)
  Future<void> removeToken() async {
    if (_currentToken == null) {
      debugPrint('[FCM] No token to revoke');
      return;
    }
    
    try {
      debugPrint('[FCM] Revoking token from backend...');
      await ApiService.instance.callGoApi(
        '/notifications/device',
        method: 'DELETE',
        body: {
          'token': _currentToken,
        },
      );
      debugPrint('[FCM] Token revoked successfully from backend');
      
      await _messaging.deleteToken();
      debugPrint('[FCM] Token deleted from Firebase');
    } catch (e) {
      debugPrint('[FCM] Failed to revoke token: $e');
    } finally {
      _currentToken = null;
      _initialized = false;
      _currentBadge = UnreadBadge();
      _badgeController.add(_currentBadge);
    }
  }

  Future<void> _upsertToken(String token) async {
    try {
       debugPrint('[FCM] Syncing token with backend...');
       await ApiService.instance.callGoApi(
           '/notifications/device',
           method: 'POST',
           body: {
               'fcm_token': token,
               'platform': _resolveDeviceType()
           }
       );
       debugPrint('[FCM] Token synced with Go Backend successfully');
    } catch (e, stackTrace) {
       debugPrint('[FCM] Sync failed: $e');
       debugPrint('[FCM] Stack trace: $stackTrace');
    }
  }

  String _resolveDeviceType() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'desktop';
  }

  Future<String?> _resolveVapidKey() async {
    if (_cachedVapidKey != null && _cachedVapidKey!.isNotEmpty) {
      return _cachedVapidKey;
    }

    final envKey = FirebaseWebConfig.vapidKey;
    if (envKey != null && envKey.isNotEmpty) {
      _cachedVapidKey = envKey;
      return envKey;
    }
    return null;
  }

  // ============================================================================
  // Badge Count Management
  // ============================================================================

  Future<void> _refreshBadgeCount() async {
    try {
      final response = await ApiService.instance.callGoApi(
        '/notifications/badge',
        method: 'GET',
      );
      final newBadge = UnreadBadge.fromJson(response);
      if (newBadge != _currentBadge) {
        _currentBadge = newBadge;
        _badgeController.add(_currentBadge);
      }
    } catch (e) {
      debugPrint('[FCM] Failed to refresh badge count: $e');
    }
  }

  /// Call this after marking notifications as read
  Future<void> refreshBadge() => _refreshBadgeCount();

  // ============================================================================
  // Preferences Management
  // ============================================================================

  Future<NotificationPreferences> getPreferences() async {
    try {
      final response = await ApiService.instance.callGoApi(
        '/notifications/preferences',
        method: 'GET',
      );
      return NotificationPreferences.fromJson(response);
    } catch (e) {
      debugPrint('[FCM] Failed to get preferences: $e');
      return NotificationPreferences();
    }
  }

  Future<bool> updatePreferences(NotificationPreferences prefs) async {
    try {
      await ApiService.instance.callGoApi(
        '/notifications/preferences',
        method: 'PUT',
        body: prefs.toJson(),
      );
      return true;
    } catch (e) {
      debugPrint('[FCM] Failed to update preferences: $e');
      return false;
    }
  }

  // ============================================================================
  // Notification Actions
  // ============================================================================

  Future<void> markAsRead(String notificationId) async {
    try {
      await ApiService.instance.callGoApi(
        '/notifications/$notificationId/read',
        method: 'PUT',
      );
      await _refreshBadgeCount();
    } catch (e) {
      debugPrint('[FCM] Failed to mark as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await ApiService.instance.callGoApi(
        '/notifications/read-all',
        method: 'PUT',
      );
      _currentBadge = UnreadBadge();
      _badgeController.add(_currentBadge);
    } catch (e) {
      debugPrint('[FCM] Failed to mark all as read: $e');
    }
  }

  // ============================================================================
  // In-App Notification Banner
  // ============================================================================

  /// Show an in-app notification banner
  void showNotificationBanner(BuildContext context, RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;
    
    // Suppress if the user is already in this conversation
    if (activeConversationId != null && 
        data['conversation_id']?.toString() == activeConversationId) {
      debugPrint('[FCM] Suppressing banner for active conversation: $activeConversationId');
      return;
    }

    // Suppress if the user is already in this post/thread
    if (activePostId != null && 
        (data['post_id']?.toString() == activePostId || data['beacon_id']?.toString() == activePostId)) {
      debugPrint('[FCM] Suppressing banner for active post: $activePostId');
      return;
    }

    // Dismiss any existing banner
    _dismissCurrentBanner();

    final OverlayState overlay;
    try {
      overlay = Overlay.of(context);
    } catch (e) {
      debugPrint('[FCM] Cannot show banner — no Overlay available');
      return;
    }
    
    _currentBannerOverlay = OverlayEntry(
      builder: (context) => _NotificationBanner(
        message: message,
        onDismiss: _dismissCurrentBanner,
        onTap: () {
          _dismissCurrentBanner();
          _handleMessageOpen(message);
        },
      ),
    );

    overlay.insert(_currentBannerOverlay!);

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), _dismissCurrentBanner);
  }

  void _dismissCurrentBanner() {
    _currentBannerOverlay?.remove();
    _currentBannerOverlay = null;
  }

  // ============================================================================
  // Navigation Handling
  // ============================================================================

  Future<void> _handleMessageOpen(RemoteMessage message) async {
    final data = message.data;
    // Try to get type from data, fallback to notification title parsing if needed
    final type = data['type'] as String?;
    
    debugPrint('[FCM] Handling message open - type: $type, data: $data');

    // Use the router directly for reliability
    final router = AppRoutes.router;

    switch (type) {
      case 'chat':
      case 'new_message':
      case 'message':
        final conversationId = data['conversation_id'];
        if (conversationId != null) {
          _openConversation(conversationId.toString());
        } else {
          router.go(AppRoutes.secureChat);
        }
        break;

      case 'like':
      case 'quip_reaction':
      case 'save':
      case 'comment':
      case 'reply':
      case 'mention':
      case 'share':
        final postId = data['post_id'] ?? data['beacon_id'];
        final target = data['target'];
        if (postId != null) {
          _navigateToPost(postId.toString(), target?.toString());
        }
        break;

      case 'new_follower':
      case 'follow':
      case 'follow_request':
      case 'follow_accepted':
        final followerId = data['follower_id'];
        if (followerId != null) {
          router.push('${AppRoutes.userPrefix}/$followerId');
        } else {
          router.go(AppRoutes.profile);
        }
        break;

      case 'beacon_vouch':
      case 'beacon_report':
        final beaconId = data['beacon_id'] ?? data['post_id'];
        if (beaconId != null) {
          _navigateToPost(beaconId.toString(), 'beacon_map');
        } else {
          router.go(AppRoutes.beaconPrefix);
        }
        break;

      default:
        debugPrint('[FCM] Unknown notification type: $type');
        // Retrieve generic target if available
        final target = data['target'];
        if (target != null) {
           _handleGenericTarget(target.toString());
        }
        break;
    }
  }

  void _navigateToPost(String postId, String? target) {
    final router = AppRoutes.router;
    switch (target) {
      case 'beacon_map':
        router.go(AppRoutes.beaconPrefix);
        break;
      case 'quip_feed':
        router.go(AppRoutes.quips);
        break;
      case 'thread_view':
      case 'main_feed':
      default:
        router.push('${AppRoutes.postPrefix}/$postId');
        break;
    }
  }

  void _handleGenericTarget(String target) {
    final router = AppRoutes.router;
    switch (target) {
      case 'secure_chat':
        router.go(AppRoutes.secureChat);
        break;
      case 'profile':
        router.go(AppRoutes.profile);
        break;
      case 'beacon_map':
        router.go(AppRoutes.beaconPrefix);
        break;
      case 'quip_feed':
        router.go(AppRoutes.quips);
        break;
    }
  }

  void _openConversation(String conversationId) {
    AppRoutes.router.push('${AppRoutes.secureChat}/$conversationId');
  }

  void dispose() {
    _badgeController.close();
    _foregroundMessageController.close();
  }
}

// ============================================================================
// In-App Notification Banner Widget
// ============================================================================

class _NotificationBanner extends StatefulWidget {
  final RemoteMessage message;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _NotificationBanner({
    required this.message,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getNotificationIcon(String? type) {
    switch (type) {
      case 'like':
        return '❤️';
      case 'comment':
      case 'reply':
        return '💬';
      case 'mention':
        return '@';
      case 'follow':
      case 'new_follower':
        return '👤';
      case 'follow_request':
        return '🔔';
      case 'message':
      case 'chat':
      case 'new_message':
        return '✉️';
      case 'save':
        return '🔖';
      case 'beacon_vouch':
        return '✅';
      case 'beacon_report':
        return '⚠️';
      default:
        return '🔔';
    }
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.message.notification;
    final type = widget.message.data['type'] as String?;
    final mediaQuery = MediaQuery.of(context);

    return Positioned(
      top: mediaQuery.padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            color: SojornColors.transparent,
            child: GestureDetector(
              onTap: widget.onTap,
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity!.abs() > 500) {
                  widget.onDismiss();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brightNavy.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.brightNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          _getNotificationIcon(type),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            notification?.title ?? 'Sojorn',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (notification?.body != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              notification!.body!,
                              style: TextStyle(
                                color: AppTheme.textSecondary.withValues(alpha: 0.8),
                                fontSize: 13,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Dismiss button
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.close,
                          color: AppTheme.textSecondary.withValues(alpha: 0.3),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
