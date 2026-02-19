import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../providers/api_provider.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../home/full_screen_shell.dart';
import '../profile/viewable_profile_screen.dart';

/// Activity log model — user's own actions
class ActivityLogItem {
  final String activityType;
  final String entityId;
  final DateTime createdAt;
  final String body;
  final String imageUrl;
  final String targetName;
  final String targetHandle;
  final String targetAvatarUrl;
  final String groupName;
  final String groupId;
  final String emoji;

  const ActivityLogItem({
    required this.activityType,
    required this.entityId,
    required this.createdAt,
    required this.body,
    required this.imageUrl,
    required this.targetName,
    required this.targetHandle,
    required this.targetAvatarUrl,
    required this.groupName,
    required this.groupId,
    required this.emoji,
  });

  factory ActivityLogItem.fromJson(Map<String, dynamic> json) {
    return ActivityLogItem(
      activityType: json['activity_type'] as String? ?? '',
      entityId: json['entity_id'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      body: json['body'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      targetName: json['target_name'] as String? ?? '',
      targetHandle: json['target_handle'] as String? ?? '',
      targetAvatarUrl: json['target_avatar_url'] as String? ?? '',
      groupName: json['group_name'] as String? ?? '',
      groupId: json['group_id'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '',
    );
  }
}

/// The user's own activity log — everything they have done on Sojorn.
class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  List<ActivityLogItem> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  String _filter = 'all'; // all, posts, comments, groups, follows, beacons

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _items = [];
        _hasMore = true;
      }
    });

    try {
      final api = ref.read(apiServiceProvider);
      final raw = await api.getActivityLog(
        limit: 30,
        offset: refresh ? 0 : _items.length,
      );
      final fetched = raw.map(ActivityLogItem.fromJson).toList();
      if (mounted) {
        setState(() {
          if (refresh) {
            _items = fetched;
          } else {
            _items.addAll(fetched);
          }
          _hasMore = fetched.length == 30;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ActivityLogItem> get _filtered {
    switch (_filter) {
      case 'posts':
        return _items.where((i) => i.activityType == 'post' || i.activityType == 'reply').toList();
      case 'comments':
        return _items.where((i) => i.activityType == 'comment' || i.activityType == 'group_comment').toList();
      case 'groups':
        return _items.where((i) => i.activityType.startsWith('group_')).toList();
      case 'follows':
        return _items.where((i) => i.activityType == 'follow').toList();
      case 'beacons':
        return _items.where((i) => i.activityType == 'beacon').toList();
      default:
        return _items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _filtered;

    return FullScreenShell(
      titleText: 'Activity Log',
      body: Column(
        children: [
          _buildFilterRow(),
          Expanded(
            child: _error != null
                ? _buildError()
                : displayed.isEmpty && !_isLoading
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: () => _load(refresh: true),
                        child: ListView.builder(
                          itemCount: displayed.length + (_hasMore ? 1 : 0),
                          padding: EdgeInsets.zero,
                          itemBuilder: (context, index) {
                            if (index == displayed.length) {
                              if (!_isLoading) _load();
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final item = displayed[index];
                            final prevItem = index > 0 ? displayed[index - 1] : null;
                            final showHeader = prevItem == null ||
                                !_sameSection(prevItem.createdAt, item.createdAt);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showHeader) _buildDateHeader(item.createdAt),
                                _ActivityItem(item: item, onTap: () => _onTap(item)),
                              ],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
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

  Widget _buildFilterRow() {
    const filters = [
      ('all', 'All'),
      ('posts', 'Posts'),
      ('comments', 'Comments'),
      ('groups', 'Groups'),
      ('follows', 'Follows'),
      ('beacons', 'Beacons'),
    ];
    return Container(
      color: AppTheme.scaffoldBg,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                onSelected: (_) => setState(() => _filter = value),
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
    );
  }

  void _onTap(ActivityLogItem item) {
    switch (item.activityType) {
      case 'post':
      case 'reply':
      case 'beacon':
        if (item.entityId.isNotEmpty) {
          context.push('/posts/${item.entityId}');
        }
        break;
      case 'comment':
        // Navigate to the post this comment was on if we have it
        break;
      case 'follow':
        if (item.targetHandle.isNotEmpty) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => UnifiedProfileScreen(handle: item.targetHandle),
          ));
        }
        break;
      case 'group_post':
      case 'group_comment':
      case 'group_join':
        context.push(AppRoutes.clusters);
        break;
      default:
        break;
    }
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 56, color: AppTheme.error.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: AppTheme.error), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(onPressed: () => _load(refresh: true), child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 72, color: AppTheme.egyptianBlue.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text('No activity yet', style: AppTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Everything you do on Sojorn — posts, comments, follows, group activity — will show up here.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.navyText.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual Activity Item
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityItem extends StatelessWidget {
  final ActivityLogItem item;
  final VoidCallback? onTap;

  const _ActivityItem({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color iconColor, String verb) = _config();

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppTheme.egyptianBlue.withValues(alpha: 0.10),
              width: 1,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon badge
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(verb,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.navyText,
                        height: 1.3,
                      )),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.navyText.withValues(alpha: 0.6),
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (item.groupName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.group, size: 12, color: AppTheme.egyptianBlue.withValues(alpha: 0.6)),
                        const SizedBox(width: 3),
                        Text(
                          item.groupName,
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.egyptianBlue.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                  if (item.targetName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@${item.targetHandle.isNotEmpty ? item.targetHandle : item.targetName}',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.brightNavy.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    timeago.format(item.createdAt, locale: 'en_short'),
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.egyptianBlue.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _config() {
    switch (item.activityType) {
      case 'post':
        return (Icons.edit_note, AppTheme.brightNavy, 'You wrote a post');
      case 'reply':
        final target = item.targetName.isNotEmpty ? item.targetName : 'someone';
        return (Icons.reply, AppTheme.royalPurple, 'You replied to $target');
      case 'beacon':
        return (Icons.location_on, const Color(0xFFF57C00), 'You posted a beacon');
      case 'comment':
        final target = item.targetName.isNotEmpty ? item.targetName : "someone's post";
        return (Icons.chat_bubble_outline, AppTheme.egyptianBlue, "You commented on $target");
      case 'follow':
        final target = item.targetName.isNotEmpty ? item.targetName : 'someone';
        return (Icons.person_add_outlined, AppTheme.ksuPurple, 'You followed $target');
      case 'group_post':
        final g = item.groupName.isNotEmpty ? item.groupName : 'a group';
        return (Icons.post_add, AppTheme.brightNavy, 'You posted in $g');
      case 'group_comment':
        final g = item.groupName.isNotEmpty ? item.groupName : 'a group';
        return (Icons.chat_bubble_outline, AppTheme.egyptianBlue, 'You commented in $g');
      case 'group_join':
        final g = item.groupName.isNotEmpty ? item.groupName : 'a group';
        return (Icons.group_add_outlined, AppTheme.ksuPurple, 'You joined $g');
      default:
        return (Icons.history, AppTheme.navyText, item.activityType);
    }
  }
}
