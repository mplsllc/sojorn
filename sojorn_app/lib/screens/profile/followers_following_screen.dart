// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/media/signed_media_image.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../providers/api_provider.dart';
import 'viewable_profile_screen.dart';

/// Screen to manage followers and following with tabbed interface
class FollowersFollowingScreen extends ConsumerStatefulWidget {
  final String userId;
  final int initialTabIndex; // 0 = Followers, 1 = Following

  const FollowersFollowingScreen({
    super.key,
    required this.userId,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<FollowersFollowingScreen> createState() =>
      _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState
    extends ConsumerState<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<UserListItem> _followers = [];
  List<UserListItem> _following = [];
  bool _isLoadingFollowers = false;
  bool _isLoadingFollowing = false;
  String? _followersError;
  String? _followingError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadFollowers();
    _loadFollowing();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadFollowers() async {
    _setStateIfMounted(() {
      _isLoadingFollowers = true;
      _followersError = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.callGoApi(
        '/users/${widget.userId}/followers',
        method: 'GET',
        queryParams: {'limit': '50', 'offset': '0'},
      );

      final List<UserListItem> users = ((data['followers'] ?? []) as List)
          .map((json) => UserListItem.fromJson(json))
          .toList();

      _setStateIfMounted(() {
        _followers = users;
      });
    } catch (e) {
      _setStateIfMounted(() {
        _followersError = e.toString();
      });
    } finally {
      _setStateIfMounted(() {
        _isLoadingFollowers = false;
      });
    }
  }

  Future<void> _loadFollowing() async {
    _setStateIfMounted(() {
      _isLoadingFollowing = true;
      _followingError = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.callGoApi(
        '/users/${widget.userId}/following',
        method: 'GET',
        queryParams: {'limit': '50', 'offset': '0'},
      );

      final List<UserListItem> users = ((data['following'] ?? []) as List)
          .map((json) => UserListItem.fromJson(json))
          .toList();

      _setStateIfMounted(() {
        _following = users;
      });
    } catch (e) {
      _setStateIfMounted(() {
        _followingError = e.toString();
      });
    } finally {
      _setStateIfMounted(() {
        _isLoadingFollowing = false;
      });
    }
  }

  Future<void> _unfollowUser(String userId) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.callGoApi('/users/$userId/follow', method: 'DELETE');
      
      _setStateIfMounted(() {
        _following.removeWhere((u) => u.id == userId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unfollowed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unfollow: $e')),
        );
      }
    }
  }

  Future<void> _removeFollower(String userId) async {
    // This would require a backend endpoint to remove a follower
    // For now, show a placeholder message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remove follower feature coming soon')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Connections',
      body: Column(
        children: [
          // Tab Bar
          Container(
            color: AppTheme.cardSurface,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.ksuPurple,
              labelColor: AppTheme.navyText,
              unselectedLabelColor: AppTheme.navyText.withValues(alpha: 0.5),
              tabs: [
                Tab(text: 'Followers (${_followers.length})'),
                Tab(text: 'Following (${_following.length})'),
              ],
            ),
          ),
          
          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(
                  users: _followers,
                  isLoading: _isLoadingFollowers,
                  error: _followersError,
                  onRefresh: _loadFollowers,
                  isFollowersList: true,
                ),
                _buildUserList(
                  users: _following,
                  isLoading: _isLoadingFollowing,
                  error: _followingError,
                  onRefresh: _loadFollowing,
                  isFollowersList: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList({
    required List<UserListItem> users,
    required bool isLoading,
    required String? error,
    required Future<void> Function() onRefresh,
    required bool isFollowersList,
  }) {
    if (isLoading && users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.navyText.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Failed to load', style: AppTheme.bodyLarge),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRefresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFollowersList ? Icons.people_outline : Icons.person_add_outlined,
              size: 64,
              color: AppTheme.navyText.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              isFollowersList ? 'No followers yet' : 'Not following anyone yet',
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.navyText.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return _UserListTile(
            user: user,
            isFollowersList: isFollowersList,
            onTap: () => _navigateToProfile(user),
            onAction: isFollowersList
                ? () => _removeFollower(user.id)
                : () => _unfollowUser(user.id),
          );
        },
      ),
    );
  }

  void _navigateToProfile(UserListItem user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UnifiedProfileScreen(handle: user.handle),
      ),
    );
  }
}

// =============================================================================
// USER LIST ITEM MODEL
// =============================================================================

class UserListItem {
  final String id;
  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final int harmonyScore;
  final String? harmonyTier;
  final DateTime? followedAt;

  UserListItem({
    required this.id,
    required this.handle,
    this.displayName,
    this.avatarUrl,
    this.harmonyScore = 0,
    this.harmonyTier,
    this.followedAt,
  });

  factory UserListItem.fromJson(Map<String, dynamic> json) {
    return UserListItem(
      id: json['id'] ?? '',
      handle: json['handle'] ?? '',
      displayName: json['display_name'],
      avatarUrl: json['avatar_url'],
      harmonyScore: json['harmony_score'] ?? 0,
      harmonyTier: json['harmony_tier'],
      followedAt: json['followed_at'] != null
          ? DateTime.tryParse(json['followed_at'])
          : null,
    );
  }
}

// =============================================================================
// USER LIST TILE WIDGET
// =============================================================================

class _UserListTile extends StatelessWidget {
  final UserListItem user;
  final bool isFollowersList;
  final VoidCallback onTap;
  final VoidCallback onAction;

  const _UserListTile({
    required this.user,
    required this.isFollowersList,
    required this.onTap,
    required this.onAction,
  });

  Color _getTierColor(String? tier) {
    switch (tier?.toLowerCase()) {
      case 'gold':
        return const Color(0xFFFFD700);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'bronze':
        return const Color(0xFFCD7F32);
      default:
        return AppTheme.navyText.withValues(alpha: 0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SojornAvatar(
        displayName: user.displayName ?? user.handle,
        avatarUrl: user.avatarUrl,
        size: 48,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.displayName ?? user.handle,
              style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (user.harmonyTier != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getTierColor(user.harmonyTier).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                user.harmonyTier!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getTierColor(user.harmonyTier),
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '@${user.handle}',
        style: AppTheme.labelSmall.copyWith(color: AppTheme.navyText.withValues(alpha: 0.6)),
      ),
      trailing: isFollowersList
          ? null // Followers don't have action button for now
          : TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.navyText.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Unfollow'),
            ),
    );
  }
}
