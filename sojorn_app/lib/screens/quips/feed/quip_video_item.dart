import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../models/quip_text_overlay.dart';
import '../../../widgets/media/signed_media_image.dart';
import '../../../widgets/video_player_with_comments.dart';
import '../../../models/post.dart';
import '../../../models/profile.dart';
import '../../../theme/tokens.dart';

import 'quips_feed_screen.dart';

class QuipVideoItem extends StatelessWidget {
  final Quip quip;
  final VideoPlayerController? controller;
  final bool isActive;
  final bool isLiked;
  final int likeCount;
  final bool isUserPaused;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onTogglePause;

  const QuipVideoItem({
    super.key,
    required this.quip,
    required this.controller,
    required this.isActive,
    required this.isLiked,
    required this.likeCount,
    required this.isUserPaused,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onTogglePause,
  });

  /// Convert Quip to Post for use with VideoPlayerWithComments
  Post _toPost() {
    return Post(
      id: quip.id,
      authorId: quip.username, // This would need to be the actual user ID
      body: quip.caption,
      status: PostStatus.active,
      detectedTone: ToneLabel.neutral,
      contentIntegrityScore: 0.8,
      createdAt: DateTime.now(), // Would need actual timestamp
      videoUrl: quip.videoUrl,
      thumbnailUrl: quip.thumbnailUrl,
      likeCount: likeCount,
      commentCount: 0, // Would need to be fetched separately
      author: Profile(
        id: quip.username,
        handle: quip.username,
        displayName: quip.displayName ?? '',
        createdAt: DateTime.now(),
      ),
    );
  }

  Widget _buildVideo() {
    final initialized = controller?.value.isInitialized ?? false;
    if (initialized) {
      final size = controller!.value.size;
      return Container(
        color: SojornColors.basicBlack,
        child: Center(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: VideoPlayer(controller!),
            ),
          ),
        ),
      );
    }

    if (quip.thumbnailUrl.isNotEmpty) {
      return SignedMediaImage(
        url: quip.thumbnailUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: SojornColors.basicBlack),
        loadingBuilder: (context) {
          return Container(
            color: SojornColors.basicBlack,
            child: const Center(
              child: CircularProgressIndicator(color: SojornColors.basicWhite),
            ),
          );
        },
      );
    }

    return Container(color: SojornColors.basicBlack);
  }

  Widget _buildActions() {
    final actions = [
      _QuipAction(
        icon: isLiked ? Icons.favorite : Icons.favorite_border,
        label: likeCount > 0 ? likeCount.toString() : '',
        onTap: onLike,
        color: isLiked ? SojornColors.destructive : SojornColors.basicWhite,
      ),
      _QuipAction(
        icon: Icons.chat_bubble_outline,
        onTap: onComment,
      ),
      _QuipAction(
        icon: Icons.send_outlined,
        onTap: onShare,
      ),
      _QuipAction(
        icon: Icons.more_horiz,
        onTap: () {},
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: actions
          .map((action) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: action,
              ))
          .toList(),
    );
  }

  Widget _buildOverlay() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '@${quip.username}',
            style: const TextStyle(
              color: SojornColors.basicWhite,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              shadows: [
                Shadow(
                  color: const Color(0x8A000000),
                  offset: Offset(0, 1),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            quip.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SojornColors.basicWhite,
              fontSize: 14,
              shadows: [
                Shadow(
                  color: const Color(0x8A000000),
                  offset: Offset(0, 1),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Icon(Icons.music_note, color: SojornColors.basicWhite, size: 18),
              SizedBox(width: 6),
              Text(
                'Original Audio',
                style: TextStyle(
                  color: SojornColors.basicWhite,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      color: const Color(0x73000000),
                      offset: Offset(0, 1),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Parses overlay_json and returns a list of non-interactive overlay widgets
  /// rendered on top of the video during feed playback.
  List<Widget> _buildOverlayWidgets(BoxConstraints constraints) {
    final json = quip.overlayJson;
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final items = (decoded['overlays'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(QuipOverlayItem.fromJson)
          .toList();

      final w = constraints.maxWidth;
      final h = constraints.maxHeight;

      return items.map((item) {
        final absX = item.position.dx * w;
        final absY = item.position.dy * h;
        final isSticker = item.type == QuipOverlayType.sticker;

        Widget child;
        if (isSticker) {
          final isEmoji = item.content.runes.length == 1 ||
              item.content.length <= 2;
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
    } catch (_) {
      return [];
    }
  }

  Widget _buildPauseOverlay() {
    if (!isActive || !isUserPaused) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SojornColors.overlayDark,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.play_arrow,
          color: SojornColors.basicWhite,
          size: 48,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTogglePause,
      child: Container(
        color: SojornColors.basicBlack,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isActive ? 1 : 0.6,
              child: _buildVideo(),
            ),
            // Quip overlays (text + stickers, non-interactive in feed)
            ..._buildOverlayWidgets(constraints),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0x8A000000),
                    SojornColors.transparent,
                    const Color(0x73000000),
                  ],
                  stops: [0, 0.4, 1],
                ),
              ),
            ),
            _buildOverlay(),
            Positioned(
              right: 16,
              bottom: 80,
              child: _buildActions(),
            ),
            Positioned(
              top: 36,
              left: 16,
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x73000000),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x66000000),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Quips',
                      style: TextStyle(
                        color: SojornColors.basicWhite,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (quip.durationMs != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x73000000),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        '${(quip.durationMs! / 1000).toStringAsFixed(1)}s',
                        style: const TextStyle(
                          color: SojornColors.basicWhite,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _buildPauseOverlay(),
            if (!(controller?.value.isInitialized ?? false))
              Center(
                child: const CircularProgressIndicator(color: SojornColors.basicWhite),
              ),
          ],
        ),
        ),
      ),
    );
  }

  /// Build the enhanced video player with comments (for fullscreen view)
  Widget buildEnhancedVideoPlayer(BuildContext context) {
    return VideoPlayerWithComments(
      post: _toPost(),
      onLike: onLike,
      onShare: onShare,
      onCommentTap: () {
        // Comments are handled within the VideoPlayerWithComments widget
      },
    );
  }
}

class _QuipAction extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final Color color;

  const _QuipAction({
    required this.icon,
    required this.onTap,
    this.label,
    this.color = SojornColors.basicWhite,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0x8A000000),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0x66000000),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: color),
          ),
        ),
        if (label != null && label!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            label!,
            style: const TextStyle(
              color: SojornColors.basicWhite,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: const Color(0x8A000000),
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
}
