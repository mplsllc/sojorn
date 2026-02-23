// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/profile.dart';
import '../../models/profile_widgets.dart';
import 'package:go_router/go_router.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../theme/tokens.dart';
import '../media/signed_media_image.dart';
import '../media/sojorn_avatar.dart';

/// Renders a list of profile widgets based on a ProfileLayout.
/// Used both on the profile editor preview and the public profile view.
class ProfileWidgetRenderer extends StatelessWidget {
  final ProfileLayout layout;
  final bool isOwnProfile;
  final ProfileStats? stats;
  final String? profileId;

  const ProfileWidgetRenderer({
    super.key,
    required this.layout,
    this.isOwnProfile = false,
    this.stats,
    this.profileId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ProfileTheme.getThemeByName(layout.theme);
    final enabledWidgets = layout.widgets
        .where((w) => w.isEnabled)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    if (enabledWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: theme.backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: SojornSpacing.md, vertical: SojornSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: enabledWidgets
            .map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: SojornSpacing.sm),
                  child: _buildWidget(context, w, theme),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildWidget(BuildContext context, ProfileWidget widget, ProfileTheme theme) {
    switch (widget.type) {
      case ProfileWidgetType.quote:
        return _QuoteWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.customText:
        return _CustomTextWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.pinnedPosts:
        return _PinnedPostsWidget(config: widget.config, theme: theme, profileId: profileId);
      case ProfileWidgetType.musicWidget:
        return _MusicWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.photoGrid:
        return _PhotoGridWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.socialLinks:
        return _SocialLinksWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.bio:
        return _BioWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.stats:
        return _StatsWidget(config: widget.config, theme: theme, stats: stats);
      case ProfileWidgetType.beaconActivity:
        return _BeaconActivityWidget(config: widget.config, theme: theme, profileId: profileId);
      case ProfileWidgetType.featuredFriends:
        return _FeaturedFriendsWidget(config: widget.config, theme: theme, profileId: profileId);
      case ProfileWidgetType.featuredGroups:
        return _FeaturedGroupsWidget(config: widget.config, theme: theme, profileId: profileId);
    }
  }
}

// ─── Quote Widget ───────────────────────────────────────────────────────────

class _QuoteWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _QuoteWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final text = config['text'] as String? ?? 'Add a quote...';
    final author = config['author'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border(
          left: BorderSide(color: theme.accentColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"$text"',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 15,
                fontStyle: FontStyle.italic,
                height: 1.5,
              )),
          if (author.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('— $author',
                style: TextStyle(
                  color: theme.textColor.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ],
      ),
    );
  }
}

// ─── Custom Text Widget ─────────────────────────────────────────────────────

class _CustomTextWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _CustomTextWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final title = config['title'] as String? ?? '';
    final body = config['body'] as String? ?? 'Write something...';

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
          ],
          Text(body,
              style: TextStyle(
                color: theme.textColor.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.5,
              )),
        ],
      ),
    );
  }
}

// ─── Bio Widget ─────────────────────────────────────────────────────────────

class _BioWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _BioWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final bio = config['text'] as String? ?? '';
    if (bio.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: theme.backgroundColor,
      ),
      child: Text(bio,
          style: TextStyle(
            color: theme.textColor,
            fontSize: 14,
            height: 1.5,
          )),
    );
  }
}

// ─── Social Links Widget ────────────────────────────────────────────────────

class _SocialLinksWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _SocialLinksWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final links = (config['links'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (links.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: theme.backgroundColor,
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: links.map((link) {
          final label = link['label'] as String? ?? 'Link';
          final platform = link['platform'] as String? ?? '';
          return Chip(
            avatar: Icon(_platformIcon(platform), size: 14, color: theme.accentColor),
            label: Text(label, style: TextStyle(fontSize: 12, color: theme.textColor)),
            backgroundColor: theme.accentColor.withValues(alpha: 0.08),
            side: BorderSide.none,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        }).toList(),
      ),
    );
  }

  static IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
      case 'x':
        return Icons.alternate_email;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'youtube':
        return Icons.play_circle_outline;
      case 'tiktok':
        return Icons.music_note;
      case 'github':
        return Icons.code;
      case 'linkedin':
        return Icons.work_outline;
      case 'website':
        return Icons.language;
      default:
        return Icons.link;
    }
  }
}

// ─── Stats Widget ───────────────────────────────────────────────────────────

class _StatsWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  final ProfileStats? stats;
  const _StatsWidget({required this.config, required this.theme, this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();

    final showPosts = config['show_posts'] as bool? ?? true;
    final showFollowers = config['show_followers'] as bool? ?? true;
    final showFollowing = config['show_following'] as bool? ?? true;

    final items = <_StatItem>[];
    if (showPosts) items.add(_StatItem(label: 'Posts', value: stats!.posts));
    if (showFollowers) items.add(_StatItem(label: 'Followers', value: stats!.followers));
    if (showFollowing) items.add(_StatItem(label: 'Following', value: stats!.following));

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: theme.accentColor.withValues(alpha: 0.06),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items.map((item) {
          return Expanded(
            child: Column(
              children: [
                Text(
                  _formatCount(item.value),
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: TextStyle(
                    color: theme.textColor.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

class _StatItem {
  final String label;
  final int value;
  const _StatItem({required this.label, required this.value});
}

// ─── Photo Grid Widget ──────────────────────────────────────────────────────

class _PhotoGridWidget extends ConsumerWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _PhotoGridWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = (config['photos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (photos.isEmpty) return const SizedBox.shrink();

    final displayPhotos = photos.take(6).toList();
    final columns = displayPhotos.length <= 3 ? displayPhotos.length : 3;

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: theme.backgroundColor,
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8, top: 4),
            child: Row(
              children: [
                Icon(Icons.photo_library, size: 16, color: theme.accentColor),
                const SizedBox(width: 6),
                Text('Photos',
                    style: TextStyle(
                      color: theme.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
                if (photos.length > 6) ...[
                  const Spacer(),
                  Text('+${photos.length - 6} more',
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: displayPhotos.length,
            itemBuilder: (ctx, i) {
              final url = displayPhotos[i]['url'] as String? ?? '';
              if (url.isEmpty) return const SizedBox.shrink();
              return ClipRRect(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                child: SignedMediaImage(
                  url: url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Pinned Posts Widget ────────────────────────────────────────────────────

class _PinnedPostsWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  final String? profileId;
  const _PinnedPostsWidget({required this.config, required this.theme, this.profileId});

  @override
  State<_PinnedPostsWidget> createState() => _PinnedPostsWidgetState();
}

class _PinnedPostsWidgetState extends State<_PinnedPostsWidget> {
  List<Map<String, dynamic>>? _pinnedPosts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPinnedPosts();
  }

  Future<void> _loadPinnedPosts() async {
    // Check config for static pinned post IDs
    final postIds = (widget.config['post_ids'] as List?)?.cast<String>() ?? [];
    if (postIds.isEmpty || widget.profileId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final data = await ApiService.instance.callGoApi(
        '/profiles/${widget.profileId}/pinned-posts',
        method: 'GET',
      );
      final posts = (data['posts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) {
        setState(() {
          _pinnedPosts = posts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(SojornSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SojornRadii.card),
          color: widget.theme.backgroundColor,
          border: Border.all(color: widget.theme.primaryColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: widget.theme.accentColor)),
            const SizedBox(width: 10),
            Text('Loading pinned posts...', style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.5), fontSize: 12)),
          ],
        ),
      );
    }

    if (_pinnedPosts == null || _pinnedPosts!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: widget.theme.backgroundColor,
        border: Border.all(color: widget.theme.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin, size: 16, color: widget.theme.accentColor),
              const SizedBox(width: 6),
              Text('Pinned',
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ..._pinnedPosts!.take(3).map((post) => _buildPinnedPostPreview(post)),
        ],
      ),
    );
  }

  Widget _buildPinnedPostPreview(Map<String, dynamic> post) {
    final content = post['content'] as String? ?? '';
    final imageUrl = post['image_url'] as String?;
    final postId = post['id'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          if (postId.isNotEmpty) {
            context.push('/posts/$postId');
          }
        },
        borderRadius: BorderRadius.circular(SojornRadii.md),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SojornRadii.md),
            color: widget.theme.accentColor.withValues(alpha: 0.04),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  content,
                  style: TextStyle(
                    color: widget.theme.textColor.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (imageUrl != null) ...[
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(SojornRadii.sm),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Image.network(imageUrl, fit: BoxFit.cover),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Music Widget ───────────────────────────────────────────────────────────

class _MusicWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _MusicWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final tracks = (config['tracks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final title = config['title'] as String? ?? 'Now Playing';

    if (tracks.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.accentColor.withValues(alpha: 0.12),
            theme.primaryColor.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_note, size: 16, color: theme.accentColor),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ...tracks.take(5).map((track) => _buildTrackRow(track)),
        ],
      ),
    );
  }

  Widget _buildTrackRow(Map<String, dynamic> track) {
    final name = track['name'] as String? ?? 'Unknown';
    final artist = track['artist'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(SojornRadii.sm),
            ),
            child: Icon(Icons.play_arrow, size: 18, color: theme.accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(color: theme.textColor, fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (artist.isNotEmpty)
                  Text(artist,
                      style: TextStyle(color: theme.textColor.withValues(alpha: 0.5), fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Featured Friends Widget ────────────────────────────────────────────────

class _FeaturedFriendsWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  final String? profileId;
  const _FeaturedFriendsWidget({required this.config, required this.theme, this.profileId});

  @override
  State<_FeaturedFriendsWidget> createState() => _FeaturedFriendsWidgetState();
}

class _FeaturedFriendsWidgetState extends State<_FeaturedFriendsWidget> {
  List<Map<String, dynamic>>? _friends;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    // Config can have explicit friend_ids or we fetch top friends
    final friendIds = (widget.config['friend_ids'] as List?)?.cast<String>() ?? [];

    if (widget.profileId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final data = await ApiService.instance.callGoApi(
        '/profiles/${widget.profileId}/friends',
        method: 'GET',
        queryParams: {
          'limit': '8',
          if (friendIds.isNotEmpty) 'ids': friendIds.join(','),
        },
      );
      final friends = (data['friends'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) {
        setState(() {
          _friends = friends;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(SojornSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SojornRadii.card),
          color: widget.theme.backgroundColor,
          border: Border.all(color: widget.theme.primaryColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: widget.theme.accentColor)),
            const SizedBox(width: 10),
            Text('Loading...', style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.5), fontSize: 12)),
          ],
        ),
      );
    }

    if (_friends == null || _friends!.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: widget.theme.backgroundColor,
        border: Border.all(color: widget.theme.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people, size: 16, color: widget.theme.accentColor),
              const SizedBox(width: 6),
              Text('Friends',
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
              const Spacer(),
              Text('${_friends!.length}',
                  style: TextStyle(
                    color: widget.theme.textColor.withValues(alpha: 0.4),
                    fontSize: 12,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _friends!.take(8).map((friend) {
              final displayName = friend['display_name'] as String? ?? '?';
              final avatarUrl = friend['avatar_url'] as String?;
              final handle = friend['handle'] as String? ?? '';
              return GestureDetector(
                onTap: () {
                  if (handle.isNotEmpty) {
                    AppRoutes.navigateToProfile(context, handle);
                  }
                },
                child: Column(
                  children: [
                    SojornAvatar(displayName: displayName, avatarUrl: avatarUrl, size: 44),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 52,
                      child: Text(
                        displayName.split(' ').first,
                        style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.7), fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Beacon Activity Widget ─────────────────────────────────────────────────

class _BeaconActivityWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  final String? profileId;
  const _BeaconActivityWidget({required this.config, required this.theme, this.profileId});

  @override
  State<_BeaconActivityWidget> createState() => _BeaconActivityWidgetState();
}

class _BeaconActivityWidgetState extends State<_BeaconActivityWidget> {
  Map<String, dynamic>? _activityData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    if (widget.profileId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final data = await ApiService.instance.callGoApi(
        '/profiles/${widget.profileId}/beacon-activity',
        method: 'GET',
      );
      if (mounted) {
        setState(() {
          _activityData = data;
          _loading = false;
        });
      }
    } catch (_) {
      // Fallback: use config data if API not available yet
      if (mounted) {
        setState(() {
          _activityData = widget.config;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(SojornSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SojornRadii.card),
          color: widget.theme.backgroundColor,
          border: Border.all(color: widget.theme.primaryColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: widget.theme.accentColor)),
            const SizedBox(width: 10),
            Text('Loading beacons...', style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.5), fontSize: 12)),
          ],
        ),
      );
    }

    final totalBeacons = _activityData?['total_beacons'] as int? ?? 0;
    final resolvedBeacons = _activityData?['resolved_beacons'] as int? ?? 0;
    final topCategory = _activityData?['top_category'] as String?;

    if (totalBeacons == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: widget.theme.backgroundColor,
        border: Border.all(color: widget.theme.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: widget.theme.accentColor),
              const SizedBox(width: 6),
              Text('Beacon Activity',
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _BeaconStatTile(
                label: 'Reports',
                value: totalBeacons.toString(),
                icon: Icons.add_alert,
                theme: widget.theme,
              ),
              const SizedBox(width: 12),
              _BeaconStatTile(
                label: 'Resolved',
                value: resolvedBeacons.toString(),
                icon: Icons.check_circle_outline,
                theme: widget.theme,
              ),
              if (topCategory != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.theme.accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(SojornRadii.md),
                    ),
                    child: Column(
                      children: [
                        Text(
                          topCategory,
                          style: TextStyle(color: widget.theme.accentColor, fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('Top Category',
                            style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.4), fontSize: 9)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BeaconStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final ProfileTheme theme;
  const _BeaconStatTile({required this.label, required this.value, required this.icon, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(SojornRadii.md),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: theme.accentColor),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(color: theme.textColor, fontSize: 15, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: theme.textColor.withValues(alpha: 0.4), fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

// ─── Featured Groups Widget ─────────────────────────────────────────────────

class _FeaturedGroupsWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  final String? profileId;
  const _FeaturedGroupsWidget({required this.config, required this.theme, this.profileId});

  @override
  State<_FeaturedGroupsWidget> createState() => _FeaturedGroupsWidgetState();
}

class _FeaturedGroupsWidgetState extends State<_FeaturedGroupsWidget> {
  List<Map<String, dynamic>>? _groups;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (widget.profileId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final data = await ApiService.instance.callGoApi(
        '/profiles/${widget.profileId}/groups',
        method: 'GET',
        queryParams: {'limit': '6'},
      );
      final groups = (data['groups'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) {
        setState(() {
          _groups = groups;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(SojornSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SojornRadii.card),
          color: widget.theme.backgroundColor,
          border: Border.all(color: widget.theme.primaryColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: widget.theme.accentColor)),
            const SizedBox(width: 10),
            Text('Loading...', style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.5), fontSize: 12)),
          ],
        ),
      );
    }

    if (_groups == null || _groups!.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: widget.theme.backgroundColor,
        border: Border.all(color: widget.theme.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups, size: 16, color: widget.theme.accentColor),
              const SizedBox(width: 6),
              Text('Groups',
                  style: TextStyle(
                    color: widget.theme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
              const Spacer(),
              Text('${_groups!.length}',
                  style: TextStyle(
                    color: widget.theme.textColor.withValues(alpha: 0.4),
                    fontSize: 12,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          ..._groups!.take(6).map((group) {
            final name = group['name'] as String? ?? 'Group';
            final memberCount = group['member_count'] as int? ?? 0;
            final avatarUrl = group['avatar_url'] as String?;
            final groupId = group['id'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () {
                  if (groupId.isNotEmpty) {
                    context.push('/groups/$groupId');
                  }
                },
                borderRadius: BorderRadius.circular(SojornRadii.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SojornAvatar(displayName: name, avatarUrl: avatarUrl, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: TextStyle(color: widget.theme.textColor, fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text('$memberCount members',
                                style: TextStyle(color: widget.theme.textColor.withValues(alpha: 0.45), fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
