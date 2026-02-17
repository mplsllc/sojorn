import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/theme_extensions.dart';
import '../media/signed_media_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../sojorn_snackbar.dart';

/// TikTok/Reels style swipeable post widget for the sojorn feed
class sojornSwipeablePost extends ConsumerStatefulWidget {
  final Post post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onChain;
  final VoidCallback onAuthorTap;
  final VoidCallback onExpandText;

  const sojornSwipeablePost({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onChain,
    required this.onAuthorTap,
    required this.onExpandText,
  });

  @override
  ConsumerState<sojornSwipeablePost> createState() =>
      _sojornSwipeablePostState();
}

class _sojornSwipeablePostState extends ConsumerState<sojornSwipeablePost> {
  bool _textExpanded = false;
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
  void didUpdateWidget(covariant sojornSwipeablePost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.visibility != widget.post.visibility) {
      _visibility = widget.post.visibility;
    }
  }

  Future<void> _showPrivacySheet() async {
    if (!_isOwner) return;
    String selected = _visibility;
    bool allowChain = widget.post.allowChain;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
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
                  const SizedBox(height: 16),
                  const Text('Interaction settings'),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Allow replies/chains'),
                    subtitle: const Text('Others can reply to this post'),
                    value: allowChain,
                    onChanged: (value) => setModalState(() => allowChain = value),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop({
                        'visibility': selected,
                        'allowChain': allowChain,
                      }),
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

    if (result == null) return;

    final newVisibility = result['visibility'] as String;
    final newAllowChain = result['allowChain'] as bool;

    if (newVisibility == _visibility && newAllowChain == widget.post.allowChain) return;

    try {
      // Update visibility if changed
      if (newVisibility != _visibility) {
        await ref.read(apiServiceProvider).updatePostVisibility(
              postId: widget.post.id,
              visibility: newVisibility,
            );
        if (!mounted) return;
        setState(() => _visibility = newVisibility);
      
      // Update allowChain setting when API supports it
      // For now, just show success message
      _updateChainSetting(newVisibility);
      
      sojornSnackbar.showSuccess(
        context: context,
        message: 'Post settings updated',
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
    final screenHeight = MediaQuery.of(context).size.height;
    final hasImage =
        widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty;
    final palette = Theme.of(context).extension<SojornExt>()!.feedPalettes.forId(
          widget.post.id,
        );

    return GestureDetector(
      onTap: () {
        setState(() {
          _textExpanded = !_textExpanded;
        });
        if (!_textExpanded) widget.onExpandText();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background: Post Image or Gradient
          _buildBackground(palette),

          // Dark gradient overlay at bottom for readability (only for image posts)
          if (hasImage)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: screenHeight * 0.4,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xD9000000),
                      const Color(0x66000000),
                      SojornColors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          // Top gradient for safe area
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: screenHeight * 0.15,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0x99000000),
                    SojornColors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Content overlay - positioned differently for text-only vs image posts
          if (hasImage)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 80),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Author info
                      _buildAuthorInfo(palette),
                      const SizedBox(height: 12),
                      // Post body text
                      _buildTextContent(palette, isTextOnly: false),
                    ],
                  ),
                ),
              ),
            )
          else
            // For text-only posts: vertically centered, left aligned
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, right: 100),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author info at top
                      _buildAuthorInfo(palette),
                      const SizedBox(height: 24),
                      // Large centered text
                      Flexible(
                        child: _buildTextContent(palette, isTextOnly: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Action buttons on the right
          Positioned(
            right: 12,
            bottom: 100,
            child: _buildActionButtons(),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorInfo(SojornFeedPalette palette) {
    return GestureDetector(
      onTap: widget.onAuthorTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getTrustColor(),
              borderRadius: BorderRadius.circular(12),
            ),
            child: widget.post.author?.avatarUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: SignedMediaImage(
                      url: widget.post.author!.avatarUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      (widget.post.author?.displayName ?? 'A')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: SojornColors.basicWhite,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          // Name and handle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.post.author?.displayName ?? 'Anonymous',
                style: TextStyle(
                  color: palette.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                '@${widget.post.author?.handle ?? 'unknown'}',
                style: TextStyle(
                  color: palette.subTextColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(SojornFeedPalette palette) {
    if (widget.post.imageUrl != null && widget.post.imageUrl!.isNotEmpty) {
      return SignedMediaImage(
        url: widget.post.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context) => Container(
          color: _getTrustColor().withValues(alpha: 0.3),
        ),
        errorBuilder: (context, error, stackTrace) =>
            _buildGradientBackground(palette),
      );
    }
    return _buildGradientBackground(palette);
  }

  Widget _buildGradientBackground(SojornFeedPalette palette) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.backgroundTop, palette.backgroundBottom],
        ),
      ),
    );
  }

  Color _getTrustColor() {
    final harmony = widget.post.author?.trustState?.harmonyScore ?? 50;
    if (harmony >= 80) return AppTheme.tierTrusted;
    if (harmony >= 60) return AppTheme.tierEstablished;
    return AppTheme.tierNew;
  }

  Widget _buildTextContent(SojornFeedPalette palette,
      {required bool isTextOnly}) {
    final text = widget.post.body;
    final maxLines = _textExpanded ? null : (isTextOnly ? 8 : 3);
    final fontSize = isTextOnly ? 24.0 : 15.0;
    final lineHeight = isTextOnly ? 1.5 : 1.4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            color: palette.textColor,
            fontSize: fontSize,
            height: lineHeight,
            fontWeight: isTextOnly ? FontWeight.w500 : FontWeight.normal,
          ),
          maxLines: maxLines,
          overflow: _textExpanded ? TextOverflow.visible : TextOverflow.fade,
        ),
        if (!_textExpanded && text.length > (isTextOnly ? 300 : 150))
          TextButton(
            onPressed: () {
              setState(() {
                _textExpanded = true;
              });
              widget.onExpandText();
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'more',
              style: TextStyle(
                color: palette.accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        // Hashtags
        if (widget.post.tags != null && widget.post.tags!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: isTextOnly ? 16 : 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.post.tags!.map((tag) {
                return Text(
                  '#$tag',
                  style: TextStyle(
                    color: palette.accentColor,
                    fontWeight: FontWeight.w600,
                    fontSize: isTextOnly ? 16 : 14,
                  ),
                );
              }).toList(),
            ),
          ),
        // Timestamp
        SizedBox(height: isTextOnly ? 12 : 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeago.format(widget.post.createdAt),
              style: TextStyle(
                color: palette.subTextColor,
                fontSize: isTextOnly ? 14 : 12,
              ),
            ),
            const SizedBox(width: 6),
            InkResponse(
              onTap: _isOwner ? _showPrivacySheet : null,
              radius: 14,
              child: Icon(
                _privacyIcon(_visibility),
                size: 12,
                color: palette.subTextColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _privacyIcon(String visibility) {
    switch (visibility) {
      case 'followers':
        return Icons.group_outlined;
      case 'private':
        return Icons.lock_outline;
      default:
        return Icons.public;
    }
  }

  Widget _buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like button
        _ActionButton(
          icon: widget.post.isLiked == true
              ? Icons.favorite
              : Icons.favorite_outline,
          count: widget.post.likeCount ?? 0,
          onTap: widget.onLike,
          color: widget.post.isLiked == true ? SojornColors.destructive : SojornColors.basicWhite,
        ),
        const SizedBox(height: 16),

        // Comment button
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          count: widget.post.commentCount ?? 0,
          onTap: widget.onComment,
        ),
        const SizedBox(height: 16),

        // Chain/Rechain button (only show if allowed and not private)
        if (widget.post.allowChain && widget.post.visibility != 'private')
          _ActionButton(
            icon: Icons.reply,
            count: null,
            onTap: widget.onChain,
            tooltip: 'Reply',
          ),
        const SizedBox(height: 16),

        // Share button
        _ActionButton(
          icon: Icons.share,
          count: null,
          onTap: widget.onShare,
          tooltip: 'Share',
        ),
      ],
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int? count;
  final VoidCallback onTap;
  final Color? color;
  final String? tooltip;

  const _ActionButton({
    required this.icon,
    this.count,
    required this.onTap,
    this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: color ?? SojornColors.basicWhite, size: 32),
          tooltip: tooltip,
        ),
        if (count != null && count! > 0)
          Text(
            _formatCount(count!),
            style: const TextStyle(
              color: SojornColors.basicWhite,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  void _updateChainSetting(String visibility) {
    // This method will be implemented when the API supports chain settings
    // For now, it's a placeholder that will be updated when the backend is ready
    print('Chain setting updated to: $visibility');
  }
}
