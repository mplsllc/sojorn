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
import '../../widgets/media/sojorn_avatar.dart';
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
  int _activeTabIndex = 0; // 0 = Active, 1 = Archived
  String _filter = 'all'; // 'all','unread','likes','comments','follows','archived'
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

  List<AppNotification> get _filteredNotifications {
    switch (_filter) {
      case 'unread':
        return _notifications.where((n) => !n.isRead).toList();
      case 'likes':
        return _notifications.where((n) => n.type == NotificationType.like || n.type == NotificationType.quip_reaction).toList();
      case 'comments':
        return _notifications.where((n) => n.type == NotificationType.comment || n.type == NotificationType.reply || n.type == NotificationType.mention).toList();
      case 'follows':
        return _notifications.where((n) => n.type == NotificationType.follow || n.type == NotificationType.follow_accepted || n.type == NotificationType.follow_request).toList();
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
    final canArchiveAll = _filter != 'archived' && _notifications.isNotEmpty;
    final displayed = _filteredNotifications;

    return FullScreenShell(
      titleText: 'Activity',
      body: Column(
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
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemBuilder: (context, index) {
                            if (index == displayed.length) {
                              if (!_isLoading) _loadNotifications();
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final notification = displayed[index];
                            if (_filter != 'archived') {
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
                                      Text('Archive',
                                          style: TextStyle(color: SojornColors.basicWhite, fontWeight: FontWeight.bold)),
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
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(bool canArchiveAll) {
    const filters = [
      ('all', 'All'),
      ('unread', 'Unread'),
      ('likes', 'Likes'),
      ('comments', 'Comments'),
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
                    checkmarkColor: Colors.white,
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
          if (canArchiveAll)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 2),
                child: TextButton(
                  onPressed: _archiveAllNotifications,
                  child: Text('Archive All',
                      style: AppTheme.textTheme.labelMedium?.copyWith(
                          color: AppTheme.egyptianBlue, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ],
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
                  if (notification.postBody != null && notification.postImageUrl == null) ...[
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

    // Type badge config
    final (IconData badgeIcon, Color badgeColor) = switch (notification.type) {
      NotificationType.like => (Icons.favorite, const Color(0xFFE53935)),
      NotificationType.quip_reaction => (Icons.favorite, const Color(0xFFE53935)),
      NotificationType.comment => (Icons.chat_bubble, AppTheme.egyptianBlue),
      NotificationType.reply => (Icons.reply, AppTheme.royalPurple),
      NotificationType.mention => (Icons.alternate_email, AppTheme.brightNavy),
      NotificationType.follow => (Icons.person_add, AppTheme.ksuPurple),
      NotificationType.follow_request => (Icons.person_add, AppTheme.ksuPurple),
      NotificationType.follow_accepted => (Icons.check_circle, AppTheme.brightNavy),
      NotificationType.save => (Icons.bookmark, AppTheme.ksuPurple),
      NotificationType.message => (Icons.message, AppTheme.egyptianBlue),
      NotificationType.share => (Icons.share, AppTheme.brightNavy),
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
          // Type badge in bottom-right corner
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
          SojornAvatar(
            displayName: displayName,
            avatarUrl: avatarUrl,
            size: 40,
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
