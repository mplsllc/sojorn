// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../models/quip_text_overlay.dart';
import '../../../widgets/media/signed_media_image.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../theme/tokens.dart';

import 'quips_feed_screen.dart';

class QuipVideoItem extends StatefulWidget {
  final Quip quip;
  final VideoPlayerController? controller;
  final bool isActive;
  final Map<String, int> reactions;
  final Set<String> myReactions;
  final int commentCount;
  final bool isUserPaused;
  final Function(String emoji) onReact;
  final Function(Offset tapPosition) onOpenReactionPicker;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onTogglePause;
  final VoidCallback onNotInterested;
  final bool isFollowing;
  final VoidCallback? onFollow;
  final VoidCallback? onScrollUp;
  final VoidCallback? onScrollDown;
  final int currentIndex;
  final int totalCount;

  const QuipVideoItem({
    super.key,
    required this.quip,
    required this.controller,
    required this.isActive,
    this.reactions = const {},
    this.myReactions = const {},
    this.commentCount = 0,
    required this.isUserPaused,
    this.isFollowing = false,
    required this.onReact,
    required this.onOpenReactionPicker,
    required this.onComment,
    required this.onShare,
    required this.onTogglePause,
    required this.onNotInterested,
    this.onFollow,
    this.onScrollUp,
    this.onScrollDown,
    this.currentIndex = 0,
    this.totalCount = 0,
  });

  @override
  State<QuipVideoItem> createState() => _QuipVideoItemState();
}

class _QuipVideoItemState extends State<QuipVideoItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heartController;
  late final Animation<double> _heartScale;
  late final Animation<double> _heartOpacity;
  Offset _heartPosition = Offset.zero;
  bool _showHeart = false;
  bool _isCaptionExpanded = false;
  bool _isMuted = false;

  // Cached overlay data — parsed once, not on every build
  late String _audioLabel;
  late List<QuipOverlayItem> _overlayItems;

  static const _quickReactEmoji = '❤️';

  @override
  void initState() {
    super.initState();
    _cacheOverlayData();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heartScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.4), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_heartController);
    _heartOpacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartController);
  }

  @override
  void didUpdateWidget(QuipVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quip.overlayJson != widget.quip.overlayJson) {
      _cacheOverlayData();
    }
  }

  void _cacheOverlayData() {
    _audioLabel = _computeAudioLabel();
    _overlayItems = _parseOverlayItems();
  }

  String _computeAudioLabel() {
    final json = widget.quip.overlayJson;
    if (json != null && json.isNotEmpty) {
      try {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        final soundId = decoded['sound_id'];
        if (soundId is String && soundId.isNotEmpty) {
          return soundId.split('/').last.split('.').first;
        }
      } catch (_) {}
    }
    return 'Original Sound';
  }

  List<QuipOverlayItem> _parseOverlayItems() {
    final json = widget.quip.overlayJson;
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return (decoded['overlays'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(QuipOverlayItem.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _handleDoubleTap(TapDownDetails details) {
    // Double-tap quick-reacts with ❤️ (only if not already reacted)
    if (!widget.myReactions.contains(_quickReactEmoji)) {
      widget.onReact(_quickReactEmoji);
    }
    setState(() {
      _heartPosition = details.localPosition;
      _showHeart = true;
    });
    _heartController.forward(from: 0).then((_) {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  void _navigateToProfile() {
    context.push('/u/${widget.quip.username}');
  }

  void _showMoreSheet() {
    final isAdmin = AuthService.instance.isAdmin;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoreOptionsSheet(
        quipId: widget.quip.id,
        onNotInterested: widget.onNotInterested,
        isAdmin: isAdmin,
        onAdminRemove: isAdmin ? () => _handleAdminRemoveQuip() : null,
      ),
    );
  }

  Future<void> _handleAdminRemoveQuip() async {
    try {
      await ApiService.instance.adminWarnUser(
        postId: widget.quip.id,
        userId: '', // quips are anonymous — no user to warn
        message: 'Quip removed by moderator',
        contentType: 'quip',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quip removed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onNotInterested();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Audio label is cached in _audioLabel — do not call jsonDecode here

  Widget _buildVideo() {
    final ctrl = widget.controller;
    final initialized = ctrl?.value.isInitialized ?? false;

    if (initialized) {
      final size = ctrl!.value.size;
      return Container(
        color: SojornColors.basicBlack,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(ctrl),
            ),
          ),
        ),
      );
    }

    if (widget.quip.thumbnailUrl.isNotEmpty) {
      return SignedMediaImage(
        url: widget.quip.thumbnailUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: SojornColors.basicBlack),
        loadingBuilder: (_) => Container(color: SojornColors.basicBlack),
      );
    }

    return Container(color: SojornColors.basicBlack);
  }

  Widget _buildProgressBar() {
    final ctrl = widget.controller;
    if (ctrl == null || !ctrl.value.isInitialized) return const SizedBox.shrink();
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: VideoProgressIndicator(
        ctrl,
        allowScrubbing: isDesktop,
        padding: EdgeInsets.zero,
        colors: const VideoProgressColors(
          playedColor: Color(0xCCFFFFFF),
          bufferedColor: Color(0x44FFFFFF),
          backgroundColor: Color(0x22FFFFFF),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = widget.quip.avatarUrl;
    final letter = widget.quip.username.isNotEmpty
        ? widget.quip.username[0].toUpperCase()
        : '?';

    Widget inner;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      inner = SignedMediaImage(
        url: avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackAvatarInner(letter),
        loadingBuilder: (_) => _fallbackAvatarInner(letter),
      );
    } else {
      inner = _fallbackAvatarInner(letter);
    }

    return Tooltip(
      message: '@${widget.quip.username}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _navigateToProfile,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: SojornColors.basicWhite, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: inner,
              ),
            ),
          ),
          // Follow badge — tapping follows/unfollows the author
          if (widget.onFollow != null)
            Positioned(
              bottom: -6,
              left: 0,
              right: 0,
              child: Center(
                child: Tooltip(
                  message: widget.isFollowing ? 'Following @${widget.quip.username}' : 'Follow @${widget.quip.username}',
                  child: GestureDetector(
                    onTap: widget.onFollow,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: widget.isFollowing
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF2979FF),
                        shape: BoxShape.circle,
                        border: Border.all(color: SojornColors.basicWhite, width: 1.5),
                      ),
                      child: Icon(
                        widget.isFollowing ? Icons.check : Icons.add,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackAvatarInner(String letter) {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: SojornColors.basicWhite,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSideActions() {
    final commentLabel =
        widget.commentCount > 0 ? _formatCount(widget.commentCount) : null;
    final totalReactions =
        widget.reactions.values.fold(0, (sum, c) => sum + c);
    final reactionLabel =
        totalReactions > 0 ? _formatCount(totalReactions) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAvatar(),
        const SizedBox(height: 24),
        // Reaction button — tap to quick-react ❤️, long-press to open full picker
        Tooltip(
          message: 'React',
          child: _buildActionBtn(
            child: _buildReactionIcon(),
            onTap: () => widget.onReact(_quickReactEmoji),
            onLongPressAt: widget.onOpenReactionPicker,
            label: reactionLabel,
          ),
        ),
        const SizedBox(height: 20),
        // Comment
        Tooltip(
          message: 'Comments',
          child: _buildActionBtn(
            child: const Icon(Icons.chat_bubble_outline,
                color: SojornColors.basicWhite, size: 28),
            onTap: widget.onComment,
            label: commentLabel,
          ),
        ),
        const SizedBox(height: 20),
        // Share
        Tooltip(
          message: 'Share',
          child: _buildActionBtn(
            child: const Icon(Icons.send_outlined,
                color: SojornColors.basicWhite, size: 28),
            onTap: widget.onShare,
          ),
        ),
        const SizedBox(height: 20),
        // More (three dots)
        Tooltip(
          message: 'More options',
          child: _buildActionBtn(
            child: const Icon(Icons.more_horiz,
                color: SojornColors.basicWhite, size: 28),
            onTap: _showMoreSheet,
          ),
        ),
        const SizedBox(height: 32),
        // Up/Down navigation arrows
        if (widget.onScrollUp != null || widget.onScrollDown != null) ...[
          _buildArrowBtn(Icons.keyboard_arrow_up, widget.onScrollUp),
          const SizedBox(height: 8),
          _buildArrowBtn(Icons.keyboard_arrow_down, widget.onScrollDown),
        ],
      ],
    );
  }

  Widget _buildArrowBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  /// Shows the user's own top reaction, the post's top reaction, or a generic
  /// add-reaction icon — in the right sidebar.
  Widget _buildReactionIcon() {
    String? reactionId;
    if (widget.myReactions.isNotEmpty) {
      reactionId = widget.myReactions.first;
    } else if (widget.reactions.isNotEmpty) {
      reactionId = widget.reactions.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
    }

    if (reactionId == null) {
      return const Icon(Icons.add_reaction_outlined,
          color: SojornColors.basicWhite, size: 30);
    }

    // Emoji
    if (!reactionId.startsWith('https://') &&
        !reactionId.startsWith('assets/') &&
        !reactionId.startsWith('asset:')) {
      return Text(reactionId, style: const TextStyle(fontSize: 30));
    }

    // CDN URL
    if (reactionId.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: reactionId,
        width: 30,
        height: 30,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Icon(Icons.add_reaction_outlined,
            color: SojornColors.basicWhite, size: 30),
        errorWidget: (_, __, ___) => const Icon(Icons.add_reaction_outlined,
            color: SojornColors.basicWhite, size: 30),
      );
    }

    // Local asset
    final assetPath = reactionId.startsWith('asset:')
        ? reactionId.replaceFirst('asset:', '')
        : reactionId;
    if (assetPath.endsWith('.svg')) {
      return SvgPicture.asset(assetPath,
          width: 30,
          height: 30,
          colorFilter: const ColorFilter.mode(
              SojornColors.basicWhite, BlendMode.srcIn));
    }
    return Image.asset(assetPath, width: 30, height: 30, fit: BoxFit.contain);
  }

  Widget _buildActionBtn({
    required Widget child,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Function(Offset globalPos)? onLongPressAt,
    String? label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          onLongPress: onLongPressAt == null ? onLongPress : null,
          onLongPressStart: onLongPressAt != null
              ? (details) => onLongPressAt(details.globalPosition)
              : null,
          behavior: HitTestBehavior.opaque,
          child: Padding(padding: const EdgeInsets.all(4), child: child),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: SojornColors.basicWhite,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: Color(0x8A000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUserInfo() {
    final audioLabel =
        '\u266b $_audioLabel \u2022 @${widget.quip.username}';
    final hasCaption = widget.quip.caption.isNotEmpty;

    return Positioned(
      left: 16,
      right: 80,
      bottom: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Username
          GestureDetector(
            onTap: _navigateToProfile,
            child: Text(
              '@${widget.quip.username}',
              style: const TextStyle(
                color: SojornColors.basicWhite,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                shadows: [
                  Shadow(
                    color: Color(0x8A000000),
                    offset: Offset(0, 1),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          // Caption with "...more" expand
          if (hasCaption) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(
                  () => _isCaptionExpanded = !_isCaptionExpanded),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: SojornColors.basicWhite,
                    fontSize: 13,
                    shadows: [
                      Shadow(
                        color: Color(0x8A000000),
                        offset: Offset(0, 1),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  children: [
                    TextSpan(text: widget.quip.caption),
                    if (!_isCaptionExpanded &&
                        widget.quip.caption.length > 60)
                      const TextSpan(
                        text: ' ...more',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                  ],
                ),
                maxLines: _isCaptionExpanded ? null : 2,
                overflow: _isCaptionExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Audio ticker row
          Row(
            children: [
              Flexible(
                child: Text(
                  audioLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SojornColors.basicWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        color: Color(0x73000000),
                        offset: Offset(0, 1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPauseOverlay() {
    if (!widget.isActive || !widget.isUserPaused) return const SizedBox.shrink();
    return Center(
      child: Icon(
        Icons.play_arrow_rounded,
        color: Colors.white.withValues(alpha: 0.6),
        size: 64,
      ),
    );
  }

  Widget _buildHeartBurst() {
    if (!_showHeart) return const SizedBox.shrink();
    return Positioned(
      left: _heartPosition.dx - 50,
      top: _heartPosition.dy - 50,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _heartController,
          builder: (_, __) => Opacity(
            opacity: _heartOpacity.value,
            child: Transform.scale(
              scale: _heartScale.value,
              child: const Icon(Icons.favorite, color: Colors.white, size: 100),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildOverlayWidgets(BoxConstraints constraints) {
    if (_overlayItems.isEmpty) return [];
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;

    return _overlayItems.map((item) {
        final absX = item.position.dx * w;
        final absY = item.position.dy * h;
        final isSticker = item.type == QuipOverlayType.sticker;

        Widget child;
        if (isSticker) {
          final isEmoji = item.content.runes.length == 1 || item.content.length <= 2;
          if (isEmoji) {
            child = Text(item.content,
                style: TextStyle(fontSize: 42 * item.scale));
          } else {
            child = Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: SojornColors.basicWhite, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.black.withValues(alpha: 0.3),
              ),
              child: Text(
                item.content,
                style: TextStyle(
                  color: SojornColors.basicWhite,
                  fontSize: 20 * item.scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }
        } else {
          child = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              item.content,
              style: TextStyle(
                color: item.color,
                fontSize: 24 * item.scale,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          );
        }

        return Positioned(
          left: absX - 50,
          top: absY - 20,
          child: Transform.rotate(angle: item.rotation, child: child),
        );
      }).toList();
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTogglePause,
      onDoubleTapDown: _handleDoubleTap,
      onDoubleTap: () {}, // consume event so single-tap doesn't fire on double-tap
      child: Container(
        color: SojornColors.basicBlack,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              _buildVideo(),
              // Quip overlays (text + stickers, non-interactive in feed)
              ..._buildOverlayWidgets(constraints),
              // Gradient scrim: strong at bottom for text legibility
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x55000000), // subtle top vignette
                      Colors.transparent,
                      Colors.transparent,
                      Color(0xB0000000), // strong bottom scrim
                    ],
                    stops: [0, 0.15, 0.55, 1],
                  ),
                ),
              ),
              // User info — bottom-left
              _buildUserInfo(),
              // Side actions — right
              Positioned(
                right: 12,
                bottom: 90,
                child: _buildSideActions(),
              ),
              // Pause overlay
              _buildPauseOverlay(),
              // Double-tap heart burst
              _buildHeartBurst(),
              // Video count indicator — top-left on desktop
              if (widget.totalCount > 0 && MediaQuery.of(context).size.width >= 900)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: BorderRadius.circular(SojornRadii.sm),
                    ),
                    child: Text(
                      '${widget.currentIndex + 1} / ${widget.totalCount}',
                      style: const TextStyle(
                        color: SojornColors.basicWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              // Mute/unmute button — bottom-right
              Positioned(
                right: 12,
                bottom: 16,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _isMuted = !_isMuted);
                    widget.controller?.setVolume(_isMuted ? 0.0 : 1.0);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0x66000000),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: SojornColors.basicWhite,
                      size: 18,
                    ),
                  ),
                ),
              ),
              // Thin video progress bar at very bottom
              _buildProgressBar(),
              // Buffering spinner
              if (!(widget.controller?.value.isInitialized ?? false))
                const Center(
                  child: CircularProgressIndicator(color: SojornColors.basicWhite),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown when the user taps the "..." (more) button on a quip.
class _MoreOptionsSheet extends StatelessWidget {
  final String quipId;
  final VoidCallback onNotInterested;
  final bool isAdmin;
  final VoidCallback? onAdminRemove;

  const _MoreOptionsSheet({
    required this.quipId,
    required this.onNotInterested,
    this.isAdmin = false,
    this.onAdminRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildOption(
            context,
            icon: Icons.thumb_down_outlined,
            label: 'Not Interested',
            onTap: () {
              Navigator.pop(context);
              onNotInterested();
            },
          ),
          _buildOption(
            context,
            icon: Icons.flag_outlined,
            label: 'Report',
            color: const Color(0xFFFF5252),
            onTap: () {
              Navigator.pop(context);
              // TODO: Wire to SanctuarySheet.showForPostId(context, quipId)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report submitted. Thank you.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          if (isAdmin && onAdminRemove != null)
            _buildOption(
              context,
              icon: Icons.delete_sweep_outlined,
              label: 'Remove (Admin)',
              color: const Color(0xFFFF5252),
              onTap: () {
                Navigator.pop(context);
                onAdminRemove!();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
