// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/media/signed_media_image.dart';
import '../../widgets/media/sojorn_avatar.dart';
import 'viewable_profile_screen.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Following screen with community management features
/// Shows followed users with tabs and sorting options
class FollowingScreen extends ConsumerStatefulWidget {
  const FollowingScreen({super.key});

  @override
  ConsumerState<FollowingScreen> createState() => _FollowingScreenState();
}

// Tab filter options
enum FollowingTab {
  all('All'),
  vouched('Vouched'),
  newFollows('New');

  final String displayName;
  const FollowingTab(this.displayName);
}

// Sort options for following list
enum FollowingSort {
  highestHarmony('Highest Harmony'),
  lastActive('Last Active'),
  recentlyFollowed('Recently Followed');

  final String displayName;
  const FollowingSort(this.displayName);
}

class _FollowingScreenState extends ConsumerState<FollowingScreen> {
  FollowingTab _activeTab = FollowingTab.all;
  FollowingSort _activeSort = FollowingSort.highestHarmony;
  List<FollowedUser> _followedUsers = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadFollowing() async {
    _setStateIfMounted(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // For now, we'll use a mock implementation since we need an API endpoint
      await Future.delayed(const Duration(milliseconds: 500));
      _setStateIfMounted(() {
        _followedUsers = _generateMockData();
      });
    } catch (e) {
      _setStateIfMounted(() {
        _error = e.toString();
      });
    } finally {
      _setStateIfMounted(() {
        _isLoading = false;
      });
    }
  }

  List<FollowedUser> _generateMockData() {
    return [
      FollowedUser(
        id: '1',
        handle: 'alice',
        displayName: 'Alice Johnson',
        avatarUrl: null,
        harmonyScore: 92,
        tier: 'trusted',
        lastActive: DateTime.now().subtract(const Duration(hours: 1)),
        latestPostBody: 'Just published my latest thoughts on...',
        latestPostCreatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        followedAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
      FollowedUser(
        id: '2',
        handle: 'bob',
        displayName: 'Bob Smith',
        avatarUrl: null,
        harmonyScore: 78,
        tier: 'established',
        lastActive: DateTime.now().subtract(const Duration(hours: 3)),
        latestPostBody: 'Working on something exciting!',
        latestPostCreatedAt: DateTime.now().subtract(const Duration(hours: 4)),
        followedAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
      FollowedUser(
        id: '3',
        handle: 'carol',
        displayName: 'Carol Williams',
        avatarUrl: null,
        harmonyScore: 85,
        tier: 'trusted',
        lastActive: DateTime.now().subtract(const Duration(minutes: 30)),
        latestPostBody: 'Check out this amazing discovery...',
        latestPostCreatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        followedAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      FollowedUser(
        id: '4',
        handle: 'dave',
        displayName: 'Dave Brown',
        avatarUrl: null,
        harmonyScore: 45,
        tier: 'new',
        lastActive: DateTime.now().subtract(const Duration(days: 1)),
        latestPostBody: 'Hello sojorn! This is my first post.',
        latestPostCreatedAt: DateTime.now().subtract(const Duration(days: 2)),
        followedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      FollowedUser(
        id: '5',
        handle: 'eve',
        displayName: 'Eve Davis',
        avatarUrl: null,
        harmonyScore: 88,
        tier: 'trusted',
        lastActive: DateTime.now().subtract(const Duration(minutes: 15)),
        latestPostBody: 'The sunset today was absolutely beautiful.',
        latestPostCreatedAt:
            DateTime.now().subtract(const Duration(minutes: 20)),
        followedAt: DateTime.now().subtract(const Duration(days: 60)),
      ),
    ];
  }

  List<FollowedUser> _getFilteredAndSortedUsers() {
    List<FollowedUser> filtered = _followedUsers;

    switch (_activeTab) {
      case FollowingTab.all:
        break;
      case FollowingTab.vouched:
        filtered = filtered.where((u) => u.tier == 'trusted').toList();
        break;
      case FollowingTab.newFollows:
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        filtered =
            filtered.where((u) => u.followedAt.isAfter(weekAgo)).toList();
        break;
    }

    switch (_activeSort) {
      case FollowingSort.highestHarmony:
        filtered.sort((a, b) => b.harmonyScore.compareTo(a.harmonyScore));
        break;
      case FollowingSort.lastActive:
        filtered.sort((a, b) => b.lastActive.compareTo(a.lastActive));
        break;
      case FollowingSort.recentlyFollowed:
        filtered.sort((a, b) => b.followedAt.compareTo(a.followedAt));
        break;
    }

    return filtered;
  }

  Color _getTierColor(String tier) {
    switch (tier) {
      case 'trusted':
        return AppTheme.tierTrusted;
      case 'established':
        return AppTheme.tierEstablished;
      default:
        return AppTheme.tierNew;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _getFilteredAndSortedUsers();

    return AppScaffold(
      title: 'Following',
      body: Column(
        children: [
          _buildTabBar(),
          _buildSortDropdown(),
          Expanded(
            child: _error != null
                ? _buildErrorState()
                : _isLoading && _followedUsers.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : filteredUsers.isEmpty
                        ? _buildEmptyState()
                        : _buildUserList(filteredUsers),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(
          bottom: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.3)),
        ),
      ),
      child: TabBar(
        tabs: FollowingTab.values.map((tab) {
          return Tab(text: tab.displayName);
        }).toList(),
        labelColor: AppTheme.navyBlue,
        unselectedLabelColor: AppTheme.egyptianBlue.withValues(alpha: 0.5),
        indicatorColor: AppTheme.royalPurple,
        indicatorWeight: 3,
        onTap: (index) {
          setState(() {
            _activeTab = FollowingTab.values[index];
          });
        },
      ),
    );
  }

  Widget _buildSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBg,
        border: Border(
          bottom: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Sort by:',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.egyptianBlue,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<FollowingSort>(
            value: _activeSort,
            icon: Icon(
              Icons.arrow_drop_down,
              color: AppTheme.royalPurple,
            ),
            elevation: 2,
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.navyBlue,
            ),
            underline: Container(
              height: 1,
              color: AppTheme.royalPurple.withValues(alpha: 0.3),
            ),
            onChanged: (FollowingSort? newValue) {
              if (newValue != null) {
                setState(() {
                  _activeSort = newValue;
                });
              }
            },
            items: FollowingSort.values.map((sort) {
              return DropdownMenuItem<FollowingSort>(
                value: sort,
                child: Text(sort.displayName),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList(List<FollowedUser> users) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return _UserListItem(
          user: user,
          tierColor: _getTierColor(user.tier),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UnifiedProfileScreen(handle: user.handle),
              ),
            );
          },
          onPostTap: () {},
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _error ?? 'Something went wrong',
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacingMd),
          ElevatedButton(
            onPressed: _loadFollowing,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    switch (_activeTab) {
      case FollowingTab.all:
        message = "You're not following anyone yet.";
        break;
      case FollowingTab.vouched:
        message = 'No vouched users in your following list.';
        break;
      case FollowingTab.newFollows:
        message = 'No new follows in the last 7 days.';
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: AppTheme.egyptianBlue.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Text(
            message,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.egyptianBlue,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Model representing a followed user with their latest post preview
class FollowedUser {
  final String id;
  final String handle;
  final String displayName;
  final String? avatarUrl;
  final int harmonyScore;
  final String tier;
  final DateTime lastActive;
  final String? latestPostBody;
  final DateTime? latestPostCreatedAt;
  final DateTime followedAt;

  const FollowedUser({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarUrl,
    required this.harmonyScore,
    required this.tier,
    required this.lastActive,
    this.latestPostBody,
    this.latestPostCreatedAt,
    required this.followedAt,
  });
}

/// Individual user list item in the following screen
class _UserListItem extends StatelessWidget {
  final FollowedUser user;
  final Color tierColor;
  final VoidCallback onTap;
  final VoidCallback onPostTap;

  const _UserListItem({
    required this.user,
    required this.tierColor,
    required this.onTap,
    required this.onPostTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SojornAvatar(
              displayName: user.displayName,
              avatarUrl: user.avatarUrl,
              size: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.displayName,
                        style: TextStyle(
                          color: AppTheme.navyBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: tierColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '@${user.handle}',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.egyptianBlue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (user.latestPostBody != null &&
                      user.latestPostBody!.isNotEmpty)
                    GestureDetector(
                      onTap: onPostTap,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.scaffoldBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.egyptianBlue.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _truncateText(user.latestPostBody!, 100),
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.navyText,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.latestPostCreatedAt != null
                                  ? timeago.format(user.latestPostCreatedAt!)
                                  : '',
                              style: AppTheme.labelSmall.copyWith(
                                color: AppTheme.egyptianBlue.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: AppTheme.egyptianBlue.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Active ${timeago.format(user.lastActive)}',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.egyptianBlue.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.shield,
                        size: 12,
                        color: tierColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${user.harmonyScore}',
                        style: AppTheme.labelSmall.copyWith(
                          color: tierColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppTheme.egyptianBlue.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}
