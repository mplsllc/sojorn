// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/notification.dart';
import '../../providers/api_provider.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/media/signed_media_image.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../profile/viewable_profile_screen.dart';
import '../post/post_detail_screen.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';
import '../home/full_screen_shell.dart';
import '../../widgets/desktop/desktop_slide_panel.dart';
import 'activity_log_screen.dart';

/// Notifications screen showing user activity
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  int _activeTabIndex = 0; // 0 = Active, 1 = Archived
  String _filter = 'all'; // 'all','unread','likes','comments','follows','groups','archived'
  final Set<String> _locallyArchivedIds = {};
  StreamSubscription<AuthState>? _authSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('[NOTIF] initState — authenticated=${AuthService.instance.isAuthenticated}');
    final auth = AuthService.instance;
    if (!auth.isAuthenticated) {
      _authSub = auth.authStateChanges.listen((event) {
        if (event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.tokenRefreshed) {
          _loadNotifications();
          _startPolling();
        }
      });
    } else {
      _loadNotifications();
      _startPolling();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _pollTimer?.cancel();
    NotificationService.instance.refreshBadge();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && !_isLoading) {
        _loadNotifications(refresh: true, silent: true);
      }
    });
  }

  List<AppNotification> get _filteredNotifications {
    switch (_filter) {
      case 'unread':
        return _notifications.where((n) => !n.isRead).toList();
      case 'likes':
        return _notifications
            .where((n) =>
                n.type == NotificationType.like ||
                n.type == NotificationType.quip_reaction ||
                n.type == NotificationType.group_like)
            .toList();
      case 'comments':
        return _notifications
            .where((n) =>
                n.type == NotificationType.comment ||
                n.type == NotificationType.reply ||
                n.type == NotificationType.mention ||
                n.type == NotificationType.group_comment ||
                n.type == NotificationType.group_thread ||
                n.type == NotificationType.group_reply)
            .toList();
      case 'follows':
        return _notifications
            .where((n) =>
                n.type == NotificationType.follow ||
                n.type == NotificationType.follow_accepted ||
                n.type == NotificationType.follow_request)
            .toList();
      case 'groups':
        return _notifications.where((n) => n.isGroupNotification).toList();
      default:
        return _notifications;
    }
  }

  void _setFilter(String filter) {
    final wasArchived = _filter == 'archived';
    final isArchived = filter == 'archived';
    setState(() {
      _filter = filter;
      if (isArchived != wasArchived) {
        _activeTabIndex = isArchived ? 1 : 0;
        _notifications = [];
        _hasMore = true;
      }
    });
    if (isArchived != wasArchived) {
      _loadNotifications(refresh: true);
    }
  }

  Future<void> _loadNotifications({bool refresh = false, bool silent = false}) async {
    if (_isLoading) return;
    if (!AuthService.instance.isAuthenticated) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
        if (refresh) {
          _notifications = [];
          _hasMore = true;
        }
      });
    } else if (refresh) {
      // Silent refresh — don't show loader, but do reset state
      _notifications = [];
      _hasMore = true;
    }

    try {
      final apiService = ref.read(apiServiceProvider);
      final showArchived = _activeTabIndex == 1;
      final notifications = await apiService.getNotifications(
        limit: 20,
        offset: refresh || silent ? 0 : _notifications.length,
        includeArchived: showArchived,
      );

      if (mounted) {
        final filtered = notifications
            .where((item) => !_locallyArchivedIds.contains(item.id))
            .toList();
        debugPrint('[NOTIF] Loaded ${filtered.length} notifications (refresh=$refresh, silent=$silent, tab=${_activeTabIndex == 0 ? "Active" : "Archived"})');

        setState(() {
          if (refresh || silent) {
            _notifications = filtered;
          } else {
            _notifications.addAll(filtered);
          }
          _hasMore = notifications.length == 20;
          if (!silent) _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[NOTIF] Load failed: $e');
      if (mounted && !silent) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    } finally {
      if (mounted && !silent && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _markAsRead(AppNotification notification) async {
    if (notification.isRead) return;
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.markNotificationsAsRead([notification.id]);
      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere((item) => item.id == notification.id);
          if (index != -1) {
            _notifications[index] = notification.copyWith(isRead: true);
          }
        });
        NotificationService.instance.refreshBadge();
      }
    } catch (_) {}
  }

  Future<void> _archiveAllNotifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive All'),
        content: const Text('Move all notifications to your archive?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Archive All', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.archiveAllNotifications();
      if (mounted) {
        setState(() {
          _locallyArchivedIds.addAll(_notifications.map((n) => n.id));
          _notifications = [];
          _hasMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications archived'), duration: Duration(seconds: 2)),
        );
        NotificationService.instance.refreshBadge();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to archive: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _approveFollowRequest(AppNotification notification) async {
    final requesterId = notification.followerIdFromMetadata ?? notification.actor?.id;
    if (requesterId == null) return;
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.acceptFollowRequest(requesterId);
      await _archiveNotification(notification);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _rejectFollowRequest(AppNotification notification) async {
    final requesterId = notification.followerIdFromMetadata ?? notification.actor?.id;
    if (requesterId == null) return;
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.rejectFollowRequest(requesterId);
      await _archiveNotification(notification);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _handleNotificationTap(AppNotification notification) async {
    await _markAsRead(notification);

    switch (notification.type) {
      case NotificationType.follow:
      case NotificationType.follow_accepted:
        if (notification.actor != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => UnifiedProfileScreen(handle: notification.actor!.handle),
          ));
        }
        break;

      case NotificationType.like:
      case NotificationType.comment:
      case NotificationType.reply:
      case NotificationType.mention:
      case NotificationType.save:
      case NotificationType.share:
      case NotificationType.beacon_vouch:
        if (notification.postId != null) {
          try {
            final apiService = ref.read(apiServiceProvider);
            final post = await apiService.getPostById(notification.postId!);
            if (mounted) {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to load post: ${e.toString().replaceAll('Exception: ', '')}'),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          }
        }
        break;

      case NotificationType.message:
        if (notification.metadata?['conversation_id'] != null) {
          context.push('/secure-chat/${notification.metadata!['conversation_id']}');
        } else {
          context.push('/secure-chat');
        }
        break;

      case NotificationType.group_post:
      case NotificationType.group_comment:
      case NotificationType.group_like:
      case NotificationType.group_invite:
      case NotificationType.group_thread:
      case NotificationType.group_reply:
        context.push(AppRoutes.clusters);
        break;

      case NotificationType.nsfw_warning:
      case NotificationType.content_removed:
        // Navigate to post if available, otherwise show info dialog
        if (notification.postId != null) {
          try {
            final apiService = ref.read(apiServiceProvider);
            final post = await apiService.getPostById(notification.postId!);
            if (mounted) {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
              );
            }
          } catch (_) {}
        }
        break;

      default:
        break;
    }
  }

  Future<bool> _archiveNotification(AppNotification notification) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.archiveNotifications([notification.id]);
      if (mounted) {
        setState(() {
          _locallyArchivedIds.add(notification.id);
          _notifications.removeWhere((n) => n.id == notification.id);
        });
        NotificationService.instance.refreshBadge();
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to archive: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return false;
    }
  }

  // ─── Date section helpers ─────────────────────────────────────────────────

  bool _sameSection(DateTime a, DateTime b) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    String sectionFor(DateTime d) {
      final date = DateTime(d.year, d.month, d.day);
      if (!date.isBefore(today)) return 'today';
      if (!date.isBefore(yesterday)) return 'yesterday';
      if (!date.isBefore(weekAgo)) return 'this_week';
      return 'earlier';
    }

    return sectionFor(a) == sectionFor(b);
  }

  Widget _buildDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    final date = DateTime(dt.year, dt.month, dt.day);

    String label;
    if (!date.isBefore(today)) {
      label = 'Today';
    } else if (!date.isBefore(yesterday)) {
      label = 'Yesterday';
    } else if (!date.isBefore(weekAgo)) {
      label = 'This Week';
    } else {
      label = 'Earlier';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      color: AppTheme.scaffoldBg,
      width: double.infinity,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.navyText.withValues(alpha: 0.45),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canArchiveAll = _filter != 'archived' && _notifications.isNotEmpty;
    final displayed = _filteredNotifications;

    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final notifBody = Column(
        children: [
          _buildFilterRow(canArchiveAll),
          Expanded(
            child: _error != null
                ? _ErrorState(
                    message: _error!,
                    onRetry: () => _loadNotifications(refresh: true),
                  )
                : displayed.isEmpty && !_isLoading
                    ? const _EmptyState()
                    : RefreshIndicator(
                        onRefresh: () => _loadNotifications(refresh: true),
                        child: ListView.builder(
                          itemCount: displayed.length + (_hasMore ? 1 : 0),
                          padding: const EdgeInsets.only(bottom: 24),
                          itemBuilder: (context, index) {
                            if (index == displayed.length) {
                              if (!_isLoading) _loadNotifications();
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }

                            final notification = displayed[index];
                            final prev = index > 0 ? displayed[index - 1] : null;
                            final showHeader = prev == null ||
                                !_sameSection(prev.createdAt, notification.createdAt);

                            final item = _filter != 'archived'
                                ? Dismissible(
                                    key: Key('notif_${notification.id}'),
                                    direction: DismissDirection.endToStart,
                                    onDismissed: (_) => _archiveNotification(notification),
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      color: AppTheme.royalPurple.withValues(alpha: 0.8),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Text('Archive',
                                              style: TextStyle(
                                                  color: SojornColors.basicWhite,
                                                  fontWeight: FontWeight.bold)),
                                          SizedBox(width: 8),
                                          Icon(Icons.archive, color: SojornColors.basicWhite),
                                        ],
                                      ),
                                    ),
                                    child: _NotificationItem(
                                      notification: notification,
                                      onTap: notification.type == NotificationType.follow_request
                                          ? null
                                          : () => _handleNotificationTap(notification),
                                      onApprove: notification.type == NotificationType.follow_request
                                          ? () => _approveFollowRequest(notification)
                                          : null,
                                      onReject: notification.type == NotificationType.follow_request
                                          ? () => _rejectFollowRequest(notification)
                                          : null,
                                    ),
                                  )
                                : _NotificationItem(
                                    notification: notification,
                                    onTap: notification.type == NotificationType.follow_request
                                        ? null
                                        : () => _handleNotificationTap(notification),
                                  );

                            if (showHeader) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDateHeader(notification.createdAt),
                                  item,
                                ],
                              );
                            }
                            return item;
                          },
                        ),
                      ),
          ),
        ],
      );

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppTheme.scaffoldBg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Notifications', style: TextStyle(color: AppTheme.navyText, fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: notifBody,
      );
    }

    return FullScreenShell(
      titleText: 'Notifications',
      body: notifBody,
    );
  }

  Widget _buildFilterRow(bool canArchiveAll) {
    const filters = [
      ('all', 'All'),
      ('unread', 'Unread'),
      ('likes', 'Likes'),
      ('comments', 'Comments'),
      ('groups', 'Groups'),
      ('follows', 'Follows'),
      ('archived', 'Archived'),
    ];
    return Container(
      color: AppTheme.scaffoldBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: filters.map((f) {
                final (value, label) = f;
                final isSelected = _filter == value;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? Colors.white : AppTheme.navyText)),
                    selected: isSelected,
                    onSelected: (_) => _setFilter(value),
                    backgroundColor: AppTheme.cardSurface,
                    selectedColor: AppTheme.brightNavy,
                    showCheckmark: false,
                    side: BorderSide(
                        color: isSelected
                            ? AppTheme.brightNavy
                            : AppTheme.navyText.withValues(alpha: 0.15)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    final isDesktop = MediaQuery.of(context).size.width >= 900;
                    if (isDesktop) {
                      openDesktopSlidePanel(context, width: 480, child: const ActivityLogScreen());
                    } else {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ActivityLogScreen(),
                      ));
                    }
                  },
                  icon: Icon(Icons.history, size: 15,
                      color: AppTheme.egyptianBlue.withValues(alpha: 0.7)),
                  label: Text('My Activity',
                      style: AppTheme.textTheme.labelMedium?.copyWith(
                          color: AppTheme.egyptianBlue.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size.zero,
                  ),
                ),
                if (canArchiveAll)
                  TextButton(
                    onPressed: _archiveAllNotifications,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                    child: Text('Archive All',
                        style: AppTheme.textTheme.labelMedium?.copyWith(
                            color: AppTheme.egyptianBlue, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual notification item
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationItem extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _NotificationItem({
    required this.notification,
    this.onTap,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (notification.type == NotificationType.follow_request) {
      return _FollowRequestItem(
        notification: notification,
        onApprove: onApprove,
        onReject: onReject,
      );
    }

    // System/moderation notifications get a different layout (no actor avatar)
    if (notification.type == NotificationType.nsfw_warning ||
        notification.type == NotificationType.content_removed) {
      return _SystemNotificationItem(notification: notification, onTap: onTap);
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: notification.isRead
              ? SojornColors.transparent
              : AppTheme.royalPurple.withValues(alpha: 0.04),
          border: Border(
            bottom: BorderSide(
              color: AppTheme.egyptianBlue.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildActorAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.message,
                    style: AppTheme.textTheme.bodyMedium?.copyWith(
                      fontWeight: notification.isRead ? FontWeight.w400 : FontWeight.w600,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                  if (notification.postBody != null &&
                      notification.postBody!.isNotEmpty &&
                      notification.postImageUrl == null) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.postBody!,
                      style: AppTheme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.navyText.withValues(alpha: 0.55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Group name pill for group notifications
                  if (notification.isGroupNotification) ...[
                    const SizedBox(height: 3),
                    _GroupPill(groupName: notification.metadata?['group_name'] as String? ?? 'Group'),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    timeago.format(notification.createdAt, locale: 'en_short'),
                    style: AppTheme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.egyptianBlue.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (notification.postImageUrl != null) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: SignedMediaImage(
                    url: notification.postImageUrl!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ] else if (!notification.isRead) ...[
              const SizedBox(width: 10),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.royalPurple,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActorAvatar() {
    final actor = notification.actor;
    final avatarUrl = actor?.avatarUrl;
    final displayName = actor?.displayName ?? '?';

    final (IconData badgeIcon, Color badgeColor) = switch (notification.type) {
      NotificationType.like => (Icons.favorite, const Color(0xFFE53935)),
      NotificationType.quip_reaction => (Icons.favorite, const Color(0xFFE53935)),
      NotificationType.group_like => (Icons.favorite, const Color(0xFFE53935)),
      NotificationType.comment => (Icons.chat_bubble, AppTheme.egyptianBlue),
      NotificationType.group_comment => (Icons.chat_bubble, AppTheme.egyptianBlue),
      NotificationType.reply => (Icons.reply, AppTheme.royalPurple),
      NotificationType.group_reply => (Icons.reply, AppTheme.royalPurple),
      NotificationType.mention => (Icons.alternate_email, AppTheme.brightNavy),
      NotificationType.follow => (Icons.person_add, AppTheme.ksuPurple),
      NotificationType.follow_request => (Icons.person_add, AppTheme.ksuPurple),
      NotificationType.follow_accepted => (Icons.check_circle, AppTheme.brightNavy),
      NotificationType.save => (Icons.bookmark, AppTheme.ksuPurple),
      NotificationType.message => (Icons.message, AppTheme.egyptianBlue),
      NotificationType.share => (Icons.share, AppTheme.brightNavy),
      NotificationType.beacon_vouch => (Icons.location_on, const Color(0xFFF57C00)),
      NotificationType.beacon_report => (Icons.flag, AppTheme.error),
      NotificationType.group_post => (Icons.post_add, AppTheme.brightNavy),
      NotificationType.group_invite => (Icons.group_add, AppTheme.ksuPurple),
      NotificationType.group_thread => (Icons.forum_outlined, AppTheme.egyptianBlue),
      _ => (Icons.notifications, AppTheme.egyptianBlue),
    };

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SojornAvatar(
            displayName: displayName,
            avatarUrl: avatarUrl,
            size: 44,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.scaffoldBg, width: 1.5),
              ),
              child: Icon(badgeIcon, size: 10, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small group name pill shown on group notifications
// ─────────────────────────────────────────────────────────────────────────────

class _GroupPill extends StatelessWidget {
  final String groupName;
  const _GroupPill({required this.groupName});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.group, size: 11, color: AppTheme.egyptianBlue.withValues(alpha: 0.55)),
        const SizedBox(width: 3),
        Text(
          groupName,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.egyptianBlue.withValues(alpha: 0.65),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// System / moderation notification (no actor, just icon + message)
// ─────────────────────────────────────────────────────────────────────────────

class _SystemNotificationItem extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onTap;

  const _SystemNotificationItem({required this.notification, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isWarning = notification.type == NotificationType.nsfw_warning;
    final iconColor = isWarning ? const Color(0xFFF57C00) : AppTheme.error;
    final icon = isWarning ? Icons.visibility_off_outlined : Icons.remove_circle_outline;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.04),
          border: Border(
            bottom: BorderSide(
              color: AppTheme.egyptianBlue.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.message,
                    style: AppTheme.textTheme.bodyMedium?.copyWith(
                      fontWeight: notification.isRead ? FontWeight.w400 : FontWeight.w600,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    timeago.format(notification.createdAt, locale: 'en_short'),
                    style: AppTheme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.egyptianBlue.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Follow request item
// ─────────────────────────────────────────────────────────────────────────────

class _FollowRequestItem extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _FollowRequestItem({
    required this.notification,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final actor = notification.actor;
    final avatarUrl = actor?.avatarUrl;
    final displayName = actor?.displayName ?? 'Someone';
    final handle = actor?.handle;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: notification.isRead
            ? SojornColors.transparent
            : AppTheme.royalPurple.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.egyptianBlue.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SojornAvatar(displayName: displayName, avatarUrl: avatarUrl, size: 40),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTheme.textTheme.bodyMedium?.copyWith(
                    fontWeight: notification.isRead ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
                if (handle != null && handle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('@$handle',
                      style: AppTheme.textTheme.labelSmall
                          ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.7))),
                ],
                const SizedBox(height: AppTheme.spacingXs),
                Text('requested to follow you',
                    style: AppTheme.textTheme.bodySmall
                        ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.8))),
                const SizedBox(height: AppTheme.spacingSm),
                Row(
                  children: [
                    TextButton(
                      onPressed: onReject,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Delete'),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    ElevatedButton(
                      onPressed: onApprove,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalPurple,
                        foregroundColor: AppTheme.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Confirm'),
                    ),
                    const Spacer(),
                    Text(
                      timeago.format(notification.createdAt, locale: 'en_short'),
                      style: AppTheme.textTheme.labelSmall
                          ?.copyWith(color: AppTheme.egyptianBlue.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error / empty states
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 56, color: AppTheme.error.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(message,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
              textAlign: TextAlign.center),
          const SizedBox(height: AppTheme.spacingMd),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 80, color: AppTheme.egyptianBlue.withValues(alpha: 0.3)),
            const SizedBox(height: AppTheme.spacingLg),
            Text('No notifications yet', style: AppTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: AppTheme.spacingMd),
            Text(
              "You'll see likes, comments, follows, group activity, and more here.",
              style: AppTheme.textTheme.bodyMedium
                  ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingLg),
            Text(
              'Try following people, joining groups, or making a post to get started.',
              style: AppTheme.textTheme.bodySmall
                  ?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.5)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
