import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/notification.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/media/signed_media_image.dart';
import '../profile/viewable_profile_screen.dart';
import '../post/post_detail_screen.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';
import '../../providers/notification_provider.dart';
import '../home/full_screen_shell.dart';

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
  int _activeTabIndex = 0; // 0 for Active, 1 for Archived
  final Set<String> _locallyArchivedIds = {};
  StreamSubscription<AuthState>? _authSub;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    final auth = AuthService.instance;
    if (!auth.isAuthenticated) {
      _authSub = auth.authStateChanges.listen((event) {
        if (event.event == AuthChangeEvent.signedIn ||
            event.event == AuthChangeEvent.tokenRefreshed) {
          _loadNotifications();
        }
      });
    } else {
      _loadNotifications();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _tabController?.dispose();
    NotificationService.instance.refreshBadge();
    super.dispose();
  }

  void _subscribeToNotifications() {
    // Migrate to Go WebSockets or Polling
  }

  Future<void> _handleNewNotification(Map<String, dynamic> record) async {
    // Fetch the full notification with actor and post data
    try {
      final apiService = ref.read(apiServiceProvider);
      final notifications = await apiService.getNotifications(limit: 1, offset: 0);

      if (notifications.isNotEmpty && mounted) {
        final newNotification = notifications.first;
        if (_activeTabIndex != 1 && // If not in Archived tab
            (newNotification.archivedAt != null ||
                _locallyArchivedIds.contains(newNotification.id))) {
          return;
        }
        // Only add if not already in the list
        if (!_notifications.any((n) => n.id == newNotification.id)) {
          setState(() {
            _notifications.insert(0, newNotification);
          });
        }
      }
    } catch (e) {
      // Silently fail - we'll get it on next refresh
    }
  }

  Future<void> _loadNotifications({bool refresh = false}) async {
    if (_isLoading) return;

    // Ensure we have a valid session before loading
    if (!AuthService.instance.isAuthenticated) return;

    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _notifications = [];
        _hasMore = true;
      }
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final showArchived = _activeTabIndex == 1;
      final notifications = await apiService.getNotifications(
        limit: 20,
        offset: refresh ? 0 : _notifications.length,
        includeArchived: showArchived,
      );

      if (mounted) {
        // Backend handles active vs archived filtering
        final filtered = notifications
            .where((item) => !_locallyArchivedIds.contains(item.id))
            .toList();

        setState(() {
          if (refresh) {
            _notifications = filtered;
          } else {
            _notifications.addAll(filtered);
          }
          _hasMore = notifications.length == 20;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
          final index =
              _notifications.indexWhere((item) => item.id == notification.id);
          if (index != -1) {
            _notifications[index] = notification.copyWith(isRead: true);
          }
        });
        
        // Clear the badge count on the bell icon immediately
        NotificationService.instance.refreshBadge();
      }
    } catch (e) {
      // Silently fail - not critical
    }
  }

  Future<void> _archiveAllNotifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive All'),
        content: const Text('Are you sure you want to move all notifications to your archive?'),
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
          const SnackBar(
            content: Text('Notifications moved to archive'),
            duration: Duration(seconds: 2),
          ),
        );
        
        // Clear the badge count on the bell icon immediately
        NotificationService.instance.refreshBadge();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to archive notifications: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _approveFollowRequest(AppNotification notification) async {
    final requesterId =
        notification.followerIdFromMetadata ?? notification.actor?.id;
    if (requesterId == null) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.acceptFollowRequest(requesterId);
      await _archiveNotification(notification);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve request: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _rejectFollowRequest(AppNotification notification) async {
    final requesterId =
        notification.followerIdFromMetadata ?? notification.actor?.id;
    if (requesterId == null) return;

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.rejectFollowRequest(requesterId);
      await _archiveNotification(notification);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete request: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _handleNotificationTap(AppNotification notification) async {
    // Only mark as read, do NOT archive automatically on tap. 
    // This allows the user to see the notification again later if they don't archive it.
    await _markAsRead(notification);

    // Navigate based on notification type
    switch (notification.type) {
      case NotificationType.follow:
      case NotificationType.follow_accepted:
        // Navigate to the follower's profile
        if (notification.actor != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UnifiedProfileScreen(handle: notification.actor!.handle),
            ),
          );
        }
        break;

      case NotificationType.like:
      case NotificationType.comment:
      case NotificationType.reply:
      case NotificationType.mention:
        // Fetch the post and navigate to post detail
        if (notification.postId != null) {
          try {
            final apiService = ref.read(apiServiceProvider);
            final post = await apiService.getPostById(notification.postId!);

            if (mounted) {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(post: post),
                ),
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
        // For messages, navigate to chat screen
        if (notification.metadata?['conversation_id'] != null) {
          context.push('/secure-chat/${notification.metadata!['conversation_id']}');
        } else {
          context.push('/secure-chat');
        }
        break;
      case NotificationType.follow_request:
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
        
        // Update badge count
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

  @override
  Widget build(BuildContext context) {
    final canArchiveAll = _activeTabIndex == 0 && _notifications.isNotEmpty;

    return DefaultTabController(
      length: 2,
      child: FullScreenShell(
        titleText: 'Activity',
        bottom: TabBar(
          onTap: (index) {
            if (index != _activeTabIndex) {
              setState(() {
                _activeTabIndex = index;
              });
              _loadNotifications(refresh: true);
            }
          },
          indicatorColor: AppTheme.egyptianBlue,
          labelColor: AppTheme.egyptianBlue,
          unselectedLabelColor: AppTheme.egyptianBlue.withValues(alpha: 0.5),
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Archived'),
          ],
        ),
        body: _error != null
            ? _ErrorState(
                message: _error!,
                onRetry: () => _loadNotifications(refresh: true),
              )
            : _notifications.isEmpty && !_isLoading
                ? const _EmptyState()
                : Column(
                    children: [
                      if (canArchiveAll)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8, top: 4),
                            child: TextButton(
                              onPressed: _archiveAllNotifications,
                              child: Text(
                                'Archive All',
                                style: AppTheme.textTheme.labelMedium?.copyWith(
                                  color: AppTheme.egyptianBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Expanded(child: RefreshIndicator(
                    onRefresh: () => _loadNotifications(refresh: true),
                    child: ListView.builder(
                      itemCount: _notifications.length + (_hasMore ? 1 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (context, index) {
                        if (index == _notifications.length) {
                          if (!_isLoading) {
                            _loadNotifications();
                          }
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final notification = _notifications[index];
                        if (_activeTabIndex == 0) {
                          return Dismissible(
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
                                  Text(
                                    'Archive',
                                    style: TextStyle(
                                      color: SojornColors.basicWhite,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
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
                          );
                        } else {
                          return _NotificationItem(
                            notification: notification,
                            onTap: notification.type == NotificationType.follow_request
                                ? null
                                : () => _handleNotificationTap(notification),
                          );
                        }
                      },
                    ),
                  )),
                    ],
                  ),
      ),
    );
  }
}

/// Individual notification item widget
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

    return InkWell(
      onTap: onTap,
      child: Container(
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
            _buildAvatar(),
            const SizedBox(width: AppTheme.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.message,
                          style: AppTheme.textTheme.bodyMedium?.copyWith(
                            fontWeight: notification.isRead
                              ? FontWeight.w400
                              : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.royalPurple,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingXs),
                  if (notification.postBody != null) ...[
                    Text(
                      notification.postBody!,
                      style: AppTheme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.navyText.withValues(alpha: 0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppTheme.spacingXs),
                  ],
                  Text(
                    timeago.format(notification.createdAt, locale: 'en_short'),
                    style: AppTheme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.egyptianBlue.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    IconData iconData;
    Color iconColor;

    switch (notification.type) {
      case NotificationType.like:
        iconData = Icons.favorite;
        iconColor = AppTheme.brightNavy;
        break;
      case NotificationType.reply:
        iconData = Icons.subdirectory_arrow_right;
        iconColor = AppTheme.royalPurple;
        break;
      case NotificationType.follow:
        iconData = Icons.person_add;
        iconColor = AppTheme.ksuPurple;
        break;
      case NotificationType.follow_accepted:
        iconData = Icons.check_circle;
        iconColor = AppTheme.brightNavy;
        break;
      case NotificationType.comment:
        iconData = Icons.comment;
        iconColor = AppTheme.egyptianBlue;
        break;
      case NotificationType.mention:
        iconData = Icons.alternate_email;
        iconColor = AppTheme.brightNavy;
        break;
      case NotificationType.follow_request:
        iconData = Icons.person_add;
        iconColor = AppTheme.ksuPurple;
        break;
      case NotificationType.message:
        iconData = Icons.message;
        iconColor = AppTheme.egyptianBlue;
        break;
      case NotificationType.save:
        iconData = Icons.bookmark;
        iconColor = AppTheme.ksuPurple;
        break;
      default:
        iconData = Icons.notifications;
        iconColor = AppTheme.egyptianBlue;
        break;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: iconColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 20,
      ),
    );
  }
}

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
          CircleAvatar(
            radius: 20,
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? ClipOval(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: SignedMediaImage(
                        url: avatarUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                : Text(
                    displayName.isNotEmpty
                        ? displayName.substring(0, 1).toUpperCase()
                        : '?',
                    style: AppTheme.textTheme.labelMedium,
                  ),
          ),
          const SizedBox(width: AppTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTheme.textTheme.bodyMedium?.copyWith(
                    fontWeight: notification.isRead
                      ? FontWeight.w400
                      : FontWeight.w600,
                  ),
                ),
                if (handle != null && handle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$handle',
                    style: AppTheme.textTheme.labelSmall?.copyWith(
                      color: AppTheme.navyText.withValues(alpha: 0.7),
                    ),
                  ),
                ],
                const SizedBox(height: AppTheme.spacingXs),
                Text(
                  'requested to follow you',
                  style: AppTheme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.navyText.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: AppTheme.spacingSm),
                Row(
                  children: [
                    TextButton(
                      onPressed: onReject,
                      child: const Text('Delete'),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    ElevatedButton(
                      onPressed: onApprove,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalPurple,
                        foregroundColor: AppTheme.white,
                      ),
                      child: const Text('Confirm'),
                    ),
                    const Spacer(),
                    Text(
                      timeago.format(notification.createdAt, locale: 'en_short'),
                      style: AppTheme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.egyptianBlue.withValues(alpha: 0.7),
                      ),
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacingMd),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
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
            Icon(
              Icons.notifications_none,
              size: 80,
              color: AppTheme.egyptianBlue.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            Text(
              'No notifications yet',
              style: AppTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingMd),
            Text(
              "You'll see notifications here when someone appreciates your posts, chains them, or follows you.",
              style: AppTheme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.navyText.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
