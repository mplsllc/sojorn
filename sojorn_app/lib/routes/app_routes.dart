// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

// ── Eager (critical path) ─────────────────────────────────────────────
import '../screens/home/feed_personal_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/auth/auth_gate.dart';

// ── Eager (admin – small, behind role check) ──────────────────────────
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_scaffold.dart';
import '../screens/admin/admin_user_base_screen.dart';
import '../screens/admin/moderation_queue_screen.dart';
import '../screens/admin/admin_content_tools_screen.dart';

// ── Deferred (code-split for web) ─────────────────────────────────────
import '../screens/beacon/beacon_screen.dart' deferred as beacon_lib;
import '../screens/quips/create/quip_creation_flow.dart' deferred as quip_create_lib;
import '../screens/quips/feed/quips_feed_screen.dart' deferred as quips_feed_lib;
import '../screens/profile/viewable_profile_screen.dart' deferred as profile_lib;
import '../screens/profile/blocked_users_screen.dart' deferred as blocked_lib;
import '../screens/secure_chat/secure_chat_full_screen.dart' deferred as secure_chat_lib;
import '../screens/secure_chat/secure_chat_loader_screen.dart' deferred as chat_loader_lib;
import '../screens/post/threaded_conversation_screen.dart' deferred as threaded_lib;
import '../screens/clusters/clusters_screen.dart' deferred as clusters_lib;
import '../screens/clusters/group_screen.dart' deferred as group_screen_lib;
import '../screens/discover/discover_screen.dart' deferred as discover_lib;

/// App routing config (GoRouter).
class AppRoutes {
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  static const String home = '/';
  static const String homeAlias = '/home';
  static const String userPrefix = '/u';
  static const String postPrefix = '/p';
  static const String beaconPrefix = '/beacon';
  static const String quips = '/quips';
  static const String profile = '/profile';
  static const String secureChat = '/secure-chat';
  static const String quipCreate = '/quips/create';
  static const String clusters = '/clusters';

  static final AuthRefreshNotifier _authRefreshNotifier =
      AuthRefreshNotifier(AuthService.instance.authStateChanges);

  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: homeAlias,
    refreshListenable: _authRefreshNotifier,
    redirect: _adminRedirect,
    routes: [
      GoRoute(
        path: home,
        redirect: (_, __) => homeAlias,
      ),
      GoRoute(
        path: '$userPrefix/:username',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => _deferred(
          profile_lib.loadLibrary,
          () => profile_lib.UnifiedProfileScreen(
            handle: state.pathParameters['username'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: quipCreate,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => _deferred(
          quip_create_lib.loadLibrary,
          () => quip_create_lib.QuipCreationFlow(),
        ),
      ),
      GoRoute(
        path: secureChat,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => _deferred(
          secure_chat_lib.loadLibrary,
          () => secure_chat_lib.SecureChatFullScreen(),
        ),
        routes: [
          GoRoute(
            path: ':id',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, state) => _deferred(
              chat_loader_lib.loadLibrary,
              () => chat_loader_lib.SecureChatLoaderScreen(
                conversationId: state.pathParameters['id'] ?? '',
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '$postPrefix/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => _deferred(
          threaded_lib.loadLibrary,
          () => threaded_lib.ThreadedConversationScreen(
            rootPostId: state.pathParameters['id'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: clusters,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => _deferred(
          clusters_lib.loadLibrary,
          () => clusters_lib.ClustersScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AuthGate(
          authenticatedChild: HomeShell(navigationShell: navigationShell),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: homeAlias,
                builder: (_, __) => const FeedPersonalScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: quips,
                builder: (_, state) => _deferred(
                  quips_feed_lib.loadLibrary,
                  () => quips_feed_lib.QuipsFeedScreen(
                    initialPostId: state.uri.queryParameters['postId'],
                  ),
                ),
              ),

            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/beacon',
                builder: (_, __) => _deferred(
                  beacon_lib.loadLibrary,
                  () => beacon_lib.BeaconScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: profile,
                builder: (_, __) => _deferred(
                  profile_lib.loadLibrary,
                  () => profile_lib.UnifiedProfileScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'blocked',
                    builder: (_, __) => _deferred(
                      blocked_lib.loadLibrary,
                      () => blocked_lib.BlockedUsersScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Branch 4: Discover (desktop shell only — mobile uses a sheet)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                builder: (_, __) => _deferred(
                  discover_lib.loadLibrary,
                  () => discover_lib.DiscoverScreen(),
                ),
              ),
            ],
          ),
          // Branch 5: Messages (desktop shell only — mobile uses a sheet)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/messages',
                builder: (_, __) => _deferred(
                  secure_chat_lib.loadLibrary,
                  () => secure_chat_lib.SecureChatFullScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) {
          final index = _adminIndexForPath(state.uri.path);
          return AdminScaffold(selectedIndex: index, child: child);
        },
        routes: [
          GoRoute(
            path: '/admin',
            builder: (_, __) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: '/admin/moderation',
            builder: (_, __) => const ModerationQueueScreen(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (_, __) => const AdminUserBaseScreen(),
          ),
          GoRoute(
            path: '/admin/content-tools',
            builder: (_, __) => const AdminContentToolsScreen(),
          ),
        ],
      ),
    ],
  );

  static int _adminIndexForPath(String path) {
    if (path.startsWith('/admin/moderation')) return 1;
    if (path.startsWith('/admin/users')) return 2;
    if (path.startsWith('/admin/content-tools')) return 3;
    return 0;
  }

  static FutureOr<String?> _adminRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final path = state.uri.path;
    if (!path.startsWith('/admin')) return null;

    final user = AuthService.instance.currentUser;
    if (user == null) return homeAlias;

    try {
      final data = await ApiService.instance.callGoApi('/profile', method: 'GET');
      final profile = data['profile'];
      if (profile is Map<String, dynamic>) {
        final role = profile['role'] as String?;
        if (role == 'admin' || role == 'moderator') {
          return null;
        }
      }
    } catch (_) {}

    return homeAlias;
  }

  /// Navigate to a user profile by username
  static void navigateToProfile(BuildContext context, String username) {
    context.push('/u/$username');
  }

  /// Get shareable URL for a user profile
  /// Returns: https://sojorn.net/u/username
  static String getProfileUrl(
    String username, {
    String baseUrl = 'https://sojorn.net',
  }) {
    return '$baseUrl/u/$username';
  }

  /// Get shareable URL for a quip
  /// Returns: https://sojorn.net/quips?postId=postid
  static String getQuipUrl(
    String postId, {
    String baseUrl = 'https://sojorn.net',
  }) {
    return '$baseUrl/quips?postId=$postId';
  }

  /// Get shareable URL for a post
  /// Returns: https://sojorn.net/p/postid
  static String getPostUrl(
    String postId, {
    String baseUrl = 'https://sojorn.net',
  }) {
    return '$baseUrl/p/$postId';
  }


  /// Get shareable URL for a beacon location
  /// Returns: https://sojorn.net/beacon?lat=...&long=...
  static String getBeaconUrl(
    double lat,
    double long, {
    String baseUrl = 'https://sojorn.net',
  }) {
    return '$baseUrl/beacon?lat=${lat.toStringAsFixed(6)}&long=${long.toStringAsFixed(6)}';
  }

  /// Navigate to a beacon location
  static void navigateToBeacon(BuildContext context, LatLng location) {
    final url =
        '/beacon?lat=${location.latitude.toStringAsFixed(6)}&long=${location.longitude.toStringAsFixed(6)}';
    context.push(url);
  }

  /// Navigate to secure chat
  static void navigateToSecureChat(BuildContext context) {
    context.push(secureChat);
  }

  /// Navigate to clusters/capsules discovery
  static void navigateToClusters(BuildContext context) {
    context.push(clusters);
  }
}

class AuthRefreshNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _subscription;

  AuthRefreshNotifier(Stream<AuthState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// ── Deferred loading helper ───────────────────────────────────────────
/// Wraps a deferred import in a FutureBuilder that shows a loading
/// spinner until the JS chunk is fetched, then builds the real screen.
Widget _deferred(Future<void> Function() load, Widget Function() build) {
  return FutureBuilder<void>(
    future: load(),
    builder: (_, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      if (snap.hasError) {
        return const Scaffold(
          body: Center(
            child: Text('Failed to load. Please go back and try again.'),
          ),
        );
      }
      return build();
    },
  );
}
