import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../screens/profile/viewable_profile_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'post_view_mode.dart';
import '../sojorn_snackbar.dart';
import '../media/signed_media_image.dart';
import '../../routes/app_routes.dart';

String _resolveAvatarUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return 'https://img.sojorn.net/${url.replaceFirst(RegExp('^/'), '')}';
}

/// Post header with author info and timestamp.
///
/// Design: Clean, minimal header for flat post design.
/// Author name uses labelLarge (ExtraBold) as visual anchor.
/// ViewMode controls visual density.
class PostHeader extends ConsumerStatefulWidget {
  final Post post;
  final double? avatarSize;
  final PostViewMode mode;

  const PostHeader({
    super.key,
    required this.post,
    this.avatarSize,
    this.mode = PostViewMode.feed,
  });

  @override
  ConsumerState<PostHeader> createState() => _PostHeaderState();
}

class _PostHeaderState extends ConsumerState<PostHeader> {
  late String _visibility;

  bool get _isOwner {
    final currentUserId = AuthService.instance.currentUser?.id;
    return currentUserId == widget.post.authorId;
  }

  @override
  void initState() {
    super.initState();
    _visibility = widget.post.visibility;
  }

  @override
  void didUpdateWidget(covariant PostHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.visibility != widget.post.visibility) {
      _visibility = widget.post.visibility;
    }
  }

  Future<void> _showPrivacySheet() async {
    if (!_isOwner) return;
    String selected = _visibility;

    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Post privacy'),
                  const SizedBox(height: 8),
                  _PrivacyOption(
                    label: 'Public',
                    value: 'public',
                    groupValue: selected,
                    onChanged: (value) => setModalState(() => selected = value),
                  ),
                  _PrivacyOption(
                    label: 'Followers',
                    value: 'followers',
                    groupValue: selected,
                    onChanged: (value) => setModalState(() => selected = value),
                  ),
                  _PrivacyOption(
                    label: 'Only me',
                    value: 'private',
                    groupValue: selected,
                    onChanged: (value) => setModalState(() => selected = value),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null || result == _visibility) return;

    try {
      await ref.read(apiServiceProvider).updatePostVisibility(
            postId: widget.post.id,
            visibility: result,
          );
      if (!mounted) return;
      setState(() => _visibility = result);
      sojornSnackbar.showSuccess(
        context: context,
        message: 'Post privacy updated',
      );
    } catch (e) {
      if (!mounted) return;
      sojornSnackbar.showError(
        context: context,
        message: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.post.author?.handle ?? 'unknown';
    final displayName = widget.post.author?.displayName ?? 'Unknown';
    final avatarUrl = _resolveAvatarUrl(widget.post.author?.avatarUrl);
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final size = widget.avatarSize ?? 36.0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar - clean circle
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _getAvatarColor(handle),
              borderRadius: BorderRadius.circular(size * 0.3),
            ),
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(size * 0.28),
                    child: SignedMediaImage(
                      url: avatarUrl,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      initial,
                      style: AppTheme.textTheme.labelMedium?.copyWith(
                        color: SojornColors.basicWhite,
                        fontWeight: FontWeight.w600,
                        fontSize: size * 0.4,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: AppTheme.spacingSm),

          // Author info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author Name - Visual anchor, ExtraBold Navy Blue
                Text(
                  displayName,
                  style: AppTheme.textTheme.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Handle + timestamp - clean metadata
                Wrap(
                  spacing: 4.0,
                  runSpacing: 0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '@$handle',
                      style: AppTheme.textTheme.labelSmall,
                    ),
                    Text(
                      '·',
                      style: AppTheme.textTheme.labelSmall,
                    ),
                    Text(
                      timeago.format(widget.post.createdAt,
                          locale: 'en_short'),
                      style: AppTheme.textTheme.labelSmall,
                    ),
                    _PrivacyIcon(
                      visibility: _visibility,
                      onTap: _isOwner ? _showPrivacySheet : null,
                    ),
                    if (widget.post.isEdited) ...[
                      Text(
                        '·',
                        style: AppTheme.textTheme.labelSmall,
                      ),
                      Text(
                        '(edited)',
                        style: AppTheme.textTheme.labelSmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: AppTheme.royalPurple.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getAvatarColor(String handle) {
    final hash = handle.hashCode;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.45, 0.55).toColor();
  }
}

class _PrivacyIcon extends StatelessWidget {
  final String visibility;
  final VoidCallback? onTap;

  const _PrivacyIcon({required this.visibility, this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = switch (visibility) {
      'followers' => Icons.group_outlined,
      'private' => Icons.lock_outline,
      _ => Icons.public,
    };

    return InkResponse(
      onTap: onTap,
      radius: 14,
      child: Icon(
        icon,
        size: 12,
        color: AppTheme.navyText.withValues(alpha: 0.6),
      ),
    );
  }
}

class _PrivacyOption extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onChanged;

  const _PrivacyOption({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      title: Text(label),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
